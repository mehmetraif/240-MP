#include "EmbeddedMpv.h"
#include <QCoreApplication>
#include <QDebug>
#include <QLibrary>
#include <QMap>
#include <QMutexLocker>
#include <QThread>
#include <cstdlib>
#include <type_traits>
#include <vector>

#ifdef OSDOS_EMBEDDED_MPV
#include <mpv/client.h>
#include <mpv/render.h>

namespace {

// libmpv's entry points, resolved once from whichever copy is installed. It is
// opened rather than linked so the app runs where it is missing, and never
// unloaded: mpv's threads can outlive a session's last call into it.
struct MpvApi {
    decltype(&mpv_create)                             create = nullptr;
    decltype(&mpv_initialize)                         initialize = nullptr;
    decltype(&mpv_set_option_string)                  setOptionString = nullptr;
    decltype(&mpv_set_option)                         setOption = nullptr;
    decltype(&mpv_command)                            command = nullptr;
    decltype(&mpv_wait_event)                         waitEvent = nullptr;
    decltype(&mpv_set_wakeup_callback)                setWakeupCallback = nullptr;
    decltype(&mpv_request_log_messages)               requestLogMessages = nullptr;
    decltype(&mpv_terminate_destroy)                  terminateDestroy = nullptr;
    decltype(&mpv_error_string)                       errorString = nullptr;
    decltype(&mpv_render_context_create)              renderCreate = nullptr;
    decltype(&mpv_render_context_set_update_callback) renderSetUpdateCallback = nullptr;
    decltype(&mpv_render_context_update)              renderUpdate = nullptr;
    decltype(&mpv_render_context_render)              renderRender = nullptr;
    decltype(&mpv_render_context_free)                renderFree = nullptr;
    bool ok = false;
};

QStringList libraryCandidates() {
    const QString appDir = QCoreApplication::applicationDirPath();
#ifdef Q_OS_MACOS
    // Homebrew's prefixes aren't on the loader's default path.
    return { appDir + QStringLiteral("/../Frameworks/libmpv.2.dylib"),
             QStringLiteral("/opt/homebrew/lib/libmpv.2.dylib"),
             QStringLiteral("/usr/local/lib/libmpv.2.dylib"),
             QStringLiteral("libmpv.2.dylib") };
#else
    // A copy bundled beside the binary (the AppImage's lib/) first.
    return { appDir + QStringLiteral("/../lib/libmpv.so.2"),
             QStringLiteral("libmpv.so.2"), QStringLiteral("libmpv.so.1") };
#endif
}

const MpvApi &api() {
    static const MpvApi loaded = [] {
        MpvApi a;
        static QLibrary lib;
        for (const QString &name : libraryCandidates()) {
            lib.setFileName(name);
            if (lib.load())
                break;
        }
        if (!lib.isLoaded()) {
            qInfo("[EmbeddedMpv] libmpv not found: Transparent Background is unavailable");
            return a;
        }
        bool all = true;
        auto resolve = [&all](auto &fn, const char *name) {
            fn = reinterpret_cast<std::remove_reference_t<decltype(fn)>>(lib.resolve(name));
            if (!fn) {
                qWarning("[EmbeddedMpv] %s has no %s", qPrintable(lib.fileName()), name);
                all = false;
            }
        };
        resolve(a.create, "mpv_create");
        resolve(a.initialize, "mpv_initialize");
        resolve(a.setOptionString, "mpv_set_option_string");
        resolve(a.setOption, "mpv_set_option");
        resolve(a.command, "mpv_command");
        resolve(a.waitEvent, "mpv_wait_event");
        resolve(a.setWakeupCallback, "mpv_set_wakeup_callback");
        resolve(a.requestLogMessages, "mpv_request_log_messages");
        resolve(a.terminateDestroy, "mpv_terminate_destroy");
        resolve(a.errorString, "mpv_error_string");
        resolve(a.renderCreate, "mpv_render_context_create");
        resolve(a.renderSetUpdateCallback, "mpv_render_context_set_update_callback");
        resolve(a.renderUpdate, "mpv_render_context_update");
        resolve(a.renderRender, "mpv_render_context_render");
        resolve(a.renderFree, "mpv_render_context_free");
        a.ok = all;
        if (all)
            qInfo("[EmbeddedMpv] using %s", qPrintable(lib.fileName()));
        return a;
    }();
    return loaded;
}

QString endReasonName(int reason) {
    switch (reason) {
    case MPV_END_FILE_REASON_EOF:      return QStringLiteral("eof");
    case MPV_END_FILE_REASON_STOP:     return QStringLiteral("stop");
    case MPV_END_FILE_REASON_QUIT:     return QStringLiteral("quit");
    case MPV_END_FILE_REASON_ERROR:    return QStringLiteral("error");
    case MPV_END_FILE_REASON_REDIRECT: return QStringLiteral("redirect");
    }
    return {};
}

void freePixels(void *pixels) {
    std::free(pixels);
}

} // namespace

// Draws the pictures, on a thread of its own: the software renderer converts
// and scales on the CPU, which would hold the menus still on the GUI thread.
// Only it calls into the render context while it runs (libmpv's rule: one
// mpv_render_* call at a time, none from inside its callbacks).
class EmbeddedMpv::Renderer : public QObject {
public:
    explicit Renderer(EmbeddedMpv *owner) : m_owner(owner) {}

    // Set before the thread starts, and only looked at on it.
    mpv_render_context *context = nullptr;

    // From any thread, mpv's included: draw on the render thread, once however
    // often this is asked before it gets there. redraw draws the last picture
    // again even when mpv has no new one (a new size).
    void schedule(bool redraw = false) {
        if (redraw)
            m_redraw = true;
        if (!m_scheduled.exchange(true))
            QMetaObject::invokeMethod(this, [this] { render(); }, Qt::QueuedConnection);
    }

    static void onUpdate(void *self) { static_cast<Renderer *>(self)->schedule(); }

private:
    void render() {
        m_scheduled = false;
        if (!context)
            return;
        const bool newFrame = api().renderUpdate(context) & MPV_RENDER_UPDATE_FRAME;
        const bool redraw = m_redraw.exchange(false) && m_drawn;
        if (!newFrame && !redraw)
            return;
        QSize size;
        {
            QMutexLocker lock(&m_owner->m_frameLock);
            size = m_owner->m_targetSize;
        }
        if (size.isEmpty())
            return;
        // Lines and start on 64 bytes, for mpv's SIMD paths. Each picture has
        // memory of its own, freed with the last QImage holding it, so one
        // still on its way to the screen is never drawn over.
        const size_t stride = (size_t(size.width()) * 4 + 63) & ~size_t(63);
        void *pixels = nullptr;
        if (posix_memalign(&pixels, 64, stride * size_t(size.height())) != 0)
            return;
        int surface[2] = { size.width(), size.height() };
        char format[] = "rgb0";
        size_t strideParam = stride;
        mpv_render_param params[] = {
            { MPV_RENDER_PARAM_SW_SIZE, surface },
            { MPV_RENDER_PARAM_SW_FORMAT, format },
            { MPV_RENDER_PARAM_SW_STRIDE, &strideParam },
            { MPV_RENDER_PARAM_SW_POINTER, pixels },
            { MPV_RENDER_PARAM_INVALID, nullptr },
        };
        if (api().renderRender(context, params) < 0) {
            std::free(pixels);
            return;
        }
        m_drawn = true;
        const QImage picture(static_cast<uchar *>(pixels), size.width(), size.height(),
                             qsizetype(stride), QImage::Format_RGBX8888, freePixels, pixels);
        {
            QMutexLocker lock(&m_owner->m_frameLock);
            m_owner->m_frame = picture;
        }
        emit m_owner->frameReady();
    }

    EmbeddedMpv *m_owner;
    std::atomic<bool> m_scheduled { false };
    std::atomic<bool> m_redraw { false };
    bool m_drawn = false;
};

bool EmbeddedMpv::available() {
    return api().ok;
}

EmbeddedMpv::EmbeddedMpv(QObject *parent) : QObject(parent) {}

EmbeddedMpv::~EmbeddedMpv() {
    teardown();
}

bool EmbeddedMpv::start(const QStringList &args) {
    stop();
    const MpvApi &a = api();
    if (!a.ok)
        return false;
    mpv_handle *mpv = a.create();
    if (!mpv) {
        qWarning("[EmbeddedMpv] mpv_create failed");
        return false;
    }

    // An option mpv doesn't know (one newer than this libmpv, say) is left
    // out, where the mpv command line would refuse to start.
    auto set = [&](const QString &name, const QString &value) {
        const int err = a.setOptionString(mpv, name.toUtf8().constData(), value.toUtf8().constData());
        if (err < 0)
            qWarning("[EmbeddedMpv] --%s=%s: %s", qPrintable(name), qPrintable(value), a.errorString(err));
    };
    // What libmpv leaves off and the mpv command line has on. Idle "once"
    // waits for the playlist below, and quits once it has played out.
    set(QStringLiteral("vo"), QStringLiteral("libmpv"));
    set(QStringLiteral("idle"), QStringLiteral("once"));
    set(QStringLiteral("input-default-bindings"), QStringLiteral("yes"));

    // A list option given more than once on the command line (--script,
    // --sub-file, ...) adds to its list there. Here the lists are gathered and
    // given whole, as lists rather than joined strings, so an item keeps any
    // character: a subtitle URL's ':' and ','.
    QMap<QString, QStringList> lists;
    auto setList = [&](const QString &name, const QStringList &values) {
        std::vector<QByteArray> utf8;
        utf8.reserve(size_t(values.size()));
        std::vector<mpv_node> items(size_t(values.size()));
        for (int i = 0; i < values.size(); ++i) {
            utf8.push_back(values[i].toUtf8());
            items[size_t(i)].format = MPV_FORMAT_STRING;
            items[size_t(i)].u.string = utf8.back().data();
        }
        mpv_node_list list { int(items.size()), items.data(), nullptr };
        mpv_node root;
        root.format = MPV_FORMAT_NODE_ARRAY;
        root.u.list = &list;
        const int err = a.setOption(mpv, name.toUtf8().constData(), MPV_FORMAT_NODE, &root);
        if (err < 0)
            qWarning("[EmbeddedMpv] --%s: %s", qPrintable(name), a.errorString(err));
    };

    // The command line as options, its other words, and every word after a
    // "--", as the playlist.
    QStringList urls;
    int playlistStart = -1;
    bool shuffle = false;
    bool files = false;
    for (const QString &arg : args) {
        if (files || !arg.startsWith(QLatin1String("--"))) {
            urls << arg;
            continue;
        }
        if (arg == QLatin1String("--")) {
            files = true;
            continue;
        }
        QString name = arg.mid(2);
        QString value = QStringLiteral("yes");
        const int eq = name.indexOf(QLatin1Char('='));
        if (eq >= 0) {
            value = name.mid(eq + 1);
            name = name.left(eq);
        } else if (name.startsWith(QLatin1String("no-"))) {
            name = name.mid(3);
            value = QStringLiteral("no");
        }
        if (name == QLatin1String("script")) {
            lists[QStringLiteral("scripts")] << value;
            continue;
        }
        if (name == QLatin1String("sub-file")) {
            lists[QStringLiteral("sub-files")] << value;
            continue;
        }
        if (name == QLatin1String("audio-file")) {
            lists[QStringLiteral("audio-files")] << value;
            continue;
        }
        if (name == QLatin1String("http-header-fields")) {
            lists[name] << value;
            continue;
        }
        if (name == QLatin1String("playlist-start"))
            playlistStart = value.toInt();
        else if (name == QLatin1String("shuffle"))
            shuffle = value == QLatin1String("yes");
        set(name, value);
    }
    for (auto it = lists.cbegin(); it != lists.cend(); ++it)
        setList(it.key(), it.value());

    if (a.initialize(mpv) < 0) {
        qWarning("[EmbeddedMpv] mpv_initialize failed");
        a.terminateDestroy(mpv);
        return false;
    }
    a.requestLogMessages(mpv, "warn");

    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_SW) },
        { MPV_RENDER_PARAM_INVALID, nullptr },
    };
    mpv_render_context *render = nullptr;
    if (a.renderCreate(&render, mpv, params) < 0) {
        qWarning("[EmbeddedMpv] the software renderer could not be set up");
        a.terminateDestroy(mpv);
        return false;
    }

    m_mpv = mpv;
    m_render = render;
    m_lastEndReason.clear();
    m_thread = new QThread;
    m_thread->setObjectName(QStringLiteral("mpv-render"));
    m_renderer = new Renderer(this);
    m_renderer->context = render;
    m_renderer->moveToThread(m_thread);
    m_thread->start();
    a.renderSetUpdateCallback(render, &Renderer::onUpdate, m_renderer);
    a.setWakeupCallback(mpv, &EmbeddedMpv::onWakeup, this);

    // The playlist, mixed (shuffle) and started (playlist-start) as the
    // command line would. A lone playlist file (m3u) mpv mixes and starts
    // where it opens it, by the same options.
    for (const QString &url : urls) {
        const QByteArray u = url.toUtf8();
        const char *load[] = { "loadfile", u.constData(), "append", nullptr };
        a.command(mpv, load);
    }
    if (urls.size() > 1 && shuffle) {
        const char *mix[] = { "playlist-shuffle", nullptr };
        a.command(mpv, mix);
    }
    const QByteArray first = QByteArray::number(urls.size() > 1 && playlistStart > 0 ? playlistStart : 0);
    const char *play[] = { "playlist-play-index", first.constData(), nullptr };
    if (a.command(mpv, play) < 0) {
        // Before mpv 0.33.
        const char *pos[] = { "set", "playlist-pos", first.constData(), nullptr };
        a.command(mpv, pos);
    }
    return true;
}

void EmbeddedMpv::stop() {
    teardown();
}

void EmbeddedMpv::quit() {
    if (!m_mpv)
        return;
    const char *cmd[] = { "quit", nullptr };
    api().command(m_mpv, cmd);
}

void EmbeddedMpv::setTargetSize(const QSize &size) {
    {
        QMutexLocker lock(&m_frameLock);
        if (size == m_targetSize || size.isEmpty())
            return;
        m_targetSize = size;
    }
    if (m_renderer)
        m_renderer->schedule(true);
}

QImage EmbeddedMpv::frame() const {
    QMutexLocker lock(&m_frameLock);
    return m_frame;
}

void EmbeddedMpv::onWakeup(void *self) {
    // From one of mpv's threads: the events are read on the GUI thread.
    auto *embedded = static_cast<EmbeddedMpv *>(self);
    if (!embedded->m_drainQueued.exchange(true))
        QMetaObject::invokeMethod(embedded, [embedded] { embedded->drainEvents(); }, Qt::QueuedConnection);
}

void EmbeddedMpv::drainEvents() {
    m_drainQueued = false;
    while (m_mpv) {
        mpv_event *event = api().waitEvent(m_mpv, 0);
        switch (event->event_id) {
        case MPV_EVENT_NONE:
            return;
        case MPV_EVENT_LOG_MESSAGE: {
            const auto *msg = static_cast<mpv_event_log_message *>(event->data);
            qWarning("[mpv] %s: %s", msg->prefix, QByteArray(msg->text).trimmed().constData());
            break;
        }
        case MPV_EVENT_END_FILE:
            m_lastEndReason = endReasonName(static_cast<mpv_event_end_file *>(event->data)->reason);
            break;
        case MPV_EVENT_SHUTDOWN: {
            const QString reason = m_lastEndReason;
            teardown();
            emit finished(reason);
            return;
        }
        default:
            break;
        }
    }
}

void EmbeddedMpv::teardown() {
    if (!m_mpv)
        return;
    const MpvApi &a = api();
    a.setWakeupCallback(m_mpv, nullptr, nullptr);
    // The render thread finishes before its context goes, and the context
    // before the core (libmpv's order).
    m_thread->quit();
    m_thread->wait();
    a.renderSetUpdateCallback(m_render, nullptr, nullptr);
    a.renderFree(m_render);
    m_render = nullptr;
    delete m_renderer;
    m_renderer = nullptr;
    delete m_thread;
    m_thread = nullptr;
    a.terminateDestroy(m_mpv);
    m_mpv = nullptr;
    QMutexLocker lock(&m_frameLock);
    m_frame = QImage();
}

#else // !OSDOS_EMBEDDED_MPV — built without libmpv's headers: never available.

class EmbeddedMpv::Renderer {};

bool EmbeddedMpv::available() { return false; }
EmbeddedMpv::EmbeddedMpv(QObject *parent) : QObject(parent) {}
EmbeddedMpv::~EmbeddedMpv() = default;
bool EmbeddedMpv::start(const QStringList &) { return false; }
void EmbeddedMpv::stop() {}
void EmbeddedMpv::quit() {}
void EmbeddedMpv::setTargetSize(const QSize &size) {
    QMutexLocker lock(&m_frameLock);
    m_targetSize = size;
}
QImage EmbeddedMpv::frame() const { return {}; }
void EmbeddedMpv::onWakeup(void *) {}
void EmbeddedMpv::drainEvents() {}
void EmbeddedMpv::teardown() {}

#endif
