#pragma once
#include <QImage>
#include <QMutex>
#include <QObject>
#include <QSize>
#include <QStringList>
#include <atomic>

class QThread;
struct mpv_handle;
struct mpv_render_context;

// mpv played inside 240-MP's own window rather than as a process of its own,
// for the Transparent Background setting: the menus can then be drawn over the
// picture while it plays (MpvController, VideoSurface).
//
// libmpv is opened at run time (libmpv.so.2 / libmpv.2.dylib), so the app
// still starts where it isn't installed; available() says whether it is. The
// picture comes from libmpv's software renderer, on a thread of its own, at
// the size the VideoSurface asks for: the same CPU colour conversion and
// scaling --vo=drm does on a Pi 4, into memory rather than a KMS buffer.
//
// A session takes an mpv command line (start(args), the one MpvController
// builds) and turns it into options and a playlist. It ends when mpv quits,
// or its playlist has played out: finished(lastEndReason), with the reason the
// last file ended ("eof", "quit", "stop", "error", "redirect").
class EmbeddedMpv : public QObject {
    Q_OBJECT
public:
    // libmpv can be loaded, with everything this needs from it.
    static bool available();

    explicit EmbeddedMpv(QObject *parent = nullptr);
    ~EmbeddedMpv() override;

    // Starts playing what an mpv command line asks for. False if libmpv
    // could not be set up (finished() does not follow then).
    bool start(const QStringList &args);
    // Ends the session at once, without finished().
    void stop();
    // Asks mpv to quit, as its own quit command does: finished() follows.
    void quit();
    bool running() const { return m_mpv != nullptr; }

    // The picture's size in device pixels; it is drawn again at a new size.
    void setTargetSize(const QSize &size);
    // The newest picture, or a null image before the first.
    QImage frame() const;

signals:
    void frameReady();
    void finished(const QString &lastEndReason);

private:
    class Renderer;

    static void onWakeup(void *self);
    void drainEvents();
    void teardown();

    mpv_handle         *m_mpv    = nullptr;
    mpv_render_context *m_render = nullptr;
    QThread            *m_thread   = nullptr;
    Renderer           *m_renderer = nullptr;
    std::atomic<bool>   m_drainQueued { false };
    QString             m_lastEndReason;

    mutable QMutex m_frameLock;
    QImage         m_frame;
    QSize          m_targetSize { 640, 480 };
};
