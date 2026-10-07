#include "LocalFilesBackend.h"
#include "util/LegacyNames.h"
#include "../../AppCore.h"
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QVariantMap>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <algorithm>

// supported image types
static const QStringList kImageExts = {
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff"
};
// supported playlist types
static const QStringList kPlaylistExts = { 
    "m3u", "m3u8" 
};
// full list of supported playback types (combo of video, image and playlist)
static const QStringList kMediaExts =
    QStringList{ "mp4", "mkv", "avi", "mov", "m4v", "webm", "wmv", "flv", "f4v", "mpg", "mpeg", "vob" }
    + kImageExts
    + kPlaylistExts;

// A search under way (search()).
struct LocalFilesBackend::SearchRun {
    QString path;
    QStringList words;
    std::unique_ptr<QDirIterator> it;
    QVariantList found;
};

// No more matches than a tree column is good for: the first, by name.
static constexpr int kSearchLimit = 200;
// Entries looked at between two turns of the event loop.
static constexpr int kSearchSlice = 400;

LocalFilesBackend::~LocalFilesBackend() = default;

LocalFilesBackend::LocalFilesBackend(const QString &appRoot, const QString &dataRoot, AppCore *appCore,
                                     QObject *parent)
    : QObject(parent), m_appRoot(appRoot), m_dataRoot(dataRoot), m_appCore(appCore)
{
    m_mediaRoot = defaultMediaRoot();
    // Resolve the configured media directory (falls back to the default above).
    QFile f(m_dataRoot + "/config.json");
    if (f.open(QIODevice::ReadOnly)) {
        QJsonObject cfg = QJsonDocument::fromJson(f.readAll()).object();
        QString dir = cfg["modules"].toObject()["com.osdos.local_files"].toObject()
                          ["media_directory"].toString();
        if (!dir.isEmpty())
            setMediaRoot(dir);
    }
}

bool LocalFilesBackend::isImage(const QString &path) const {
    return kImageExts.contains(QFileInfo(path).suffix().toLower());
}

bool LocalFilesBackend::isPlaylist(const QString &path) const {
    return kPlaylistExts.contains(QFileInfo(path).suffix().toLower());
}

// True if an .m3u/.m3u8 references at least one image entry. Used to decide whether
// the slideshow-redraw mpv script is needed (see MpvController::loadAndPlay): mpv's
// KMS output won't repaint consecutive same-size stills without it.
bool LocalFilesBackend::playlistContainsImages(const QString &path) const {
    if (!isPlaylist(path))
        return false;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    while (!f.atEnd()) {
        const QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;
        if (isImage(line))
            return true;
    }
    return false;
}

QString LocalFilesBackend::historyFilePath() const {
    return m_dataRoot + "/local_files_history.json";
}

QVariantMap LocalFilesBackend::loadHistory() const {
    QFile file(historyFilePath());
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
}

void LocalFilesBackend::saveHistory(const QVariantMap &history) {
    QFile file(historyFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    file.write(QJsonDocument(QJsonObject::fromVariantMap(history)).toJson(QJsonDocument::Compact));
}

QVariantMap LocalFilesBackend::getSavedPosition(const QString &filePath) {
    const QVariant val = loadHistory().value(filePath);
    if (!val.isValid())
        return {};
    if (val.canConvert<QVariantMap>()) {
        QVariantMap entry = val.toMap();
        if (!entry.contains("plPos")) entry["plPos"] = -1;
        return entry;
    }
    // Legacy: plain int stored (pos only)
    return {{"pos", val.toInt()}, {"plPos", -1}};
}

void LocalFilesBackend::savePosition(const QString &filePath, int positionMs, int playlistPos) {
    QVariantMap history = loadHistory();
    QVariantMap entry;
    entry["pos"]   = positionMs;
    entry["plPos"] = playlistPos;
    history[filePath] = entry;
    saveHistory(history);
}

void LocalFilesBackend::clearPosition(const QString &filePath) {
    QVariantMap history = loadHistory();
    history.remove(filePath);
    saveHistory(history);
}

void LocalFilesBackend::get_auto_subtitles_options() {
    QVariantList options;
    QVariantMap forced; forced["id"] = "forced"; forced["label"] = "Forced Only"; forced["old"] = false;
    QVariantMap on;     on["id"] = "on";         on["label"] = "On";              on["old"] = true;
    QVariantMap off;    off["id"] = "off";       off["label"] = "Off";
    options << forced << on << off;
    emit dynamicOptionsReady("auto_subtitles", options);
}

void LocalFilesBackend::get_resume_playback_options() {
    QVariantList options;
    QVariantMap ask; ask["id"] = "ask"; ask["label"] = "Ask";
    QVariantMap yes; yes["id"] = "yes"; yes["label"] = "Always";
    QVariantMap no;  no["id"]  = "no";  no["label"]  = "Never";
    options << ask << yes << no;
    emit dynamicOptionsReady("resume_playback", options);
}

void LocalFilesBackend::get_shuffle_playback_options() {
    QVariantList options;
    QVariantMap ask; ask["id"] = "ask"; ask["label"] = "Ask";
    QVariantMap yes; yes["id"] = "yes"; yes["label"] = "Always"; yes["old"] = true;
    QVariantMap no;  no["id"]  = "no";  no["label"]  = "Never";  no["old"]  = false;
    options << ask << yes << no;
    emit dynamicOptionsReady("shuffle_playback", options);
}

void LocalFilesBackend::get_image_duration_options() {
    QVariantList options;
    QVariantMap five;   five["id"]   = "5";  five["label"]   = "5 Seconds";
    QVariantMap ten;    ten["id"]    = "10"; ten["label"]    = "10 Seconds";
    QVariantMap thirty; thirty["id"] = "30"; thirty["label"] = "30 Seconds";
    QVariantMap sixty;  sixty["id"]  = "60"; sixty["label"]  = "60 Seconds";
    options << five << ten << thirty << sixty;
    emit dynamicOptionsReady("image_duration", options);
}

void LocalFilesBackend::get_subtitle_languages() {
    QStringList addedLabels;
    QVariantList options;

    QFile file(m_appRoot + "/modules/local_files/iso639-1.json");
    if (!file.open(QIODevice::ReadOnly))
        return;

    options.append(QVariantMap{{"id","-"},{"label","Any"}});

    QVariantList locList = QJsonDocument::fromJson(file.readAll()).toVariant().toList();
    for (const QVariant loc : locList)
    {
        QVariantMap langOption = QVariantMap{{"id",loc.toJsonObject()["id"].toString()},{"label",loc.toJsonObject()["label"].toString()}};
        if (langOption["label"].toString() == "" || addedLabels.contains(langOption["label"].toString())) continue;
        addedLabels.append(langOption["label"].toString());
        options.append(langOption);
    }

    emit dynamicOptionsReady("sub_lang", options);
}

QVariant LocalFilesBackend::entries(const QString &path) {
    static const QString kModuleId = QStringLiteral("com.osdos.local_files");
    if (path == QLatin1String("recent") || path == QLatin1String("favorites"))
        return existing(m_appCore ? m_appCore->get_list(kModuleId, path) : QVariantList());
    if (path.startsWith(QLatin1String("search/")))
        return search(path, path.mid(7));
    QVariantList items = getItems(path);
    // An empty media folder has nothing to search either.
    if (path == m_mediaRoot && !items.isEmpty()) {
        auto folder = [](const char *name, const char *path) {
            return QVariantMap{{QStringLiteral("name"), QString::fromLatin1(name)},
                               {QStringLiteral("path"), QString::fromLatin1(path)},
                               {QStringLiteral("isFolder"), true}};
        };
        items = QVariantList{folder("Recently Watched", "recent"), folder("Favorites", "favorites"),
                             QVariantMap{{QStringLiteral("name"), QStringLiteral("Search")},
                                         {QStringLiteral("path"), QStringLiteral("search")},
                                         {QStringLiteral("isFolder"), false},
                                         {QStringLiteral("kind"), QStringLiteral("search")}}} + items;
    }
    return items;
}

QString LocalFilesBackend::mediaRoot() const {
    return m_mediaRoot;
}

QString LocalFilesBackend::defaultMediaRoot() const {
    const QString dir = legacy::env("MEDIA_DIR");
    return dir.isEmpty() ? m_dataRoot + QStringLiteral("/media") : dir;
}

void LocalFilesBackend::setMediaRoot(const QString &path) {
    // An empty (reset) setting means back to the default.
    m_mediaRoot = path.isEmpty() ? defaultMediaRoot() : path;
    QDir().mkpath(m_mediaRoot);
    // What was found was found in the old folder.
    m_search.reset();
    m_foundPath.clear();
    m_found.clear();
    qDebug("[LocalFiles] media root: %s", qPrintable(m_mediaRoot));
}

void LocalFilesBackend::onSettingChanged(const QString &moduleId, const QString &key, const QVariant &value) {
    if (moduleId == QLatin1String("com.osdos.local_files") && key == QLatin1String("media_directory"))
        setMediaRoot(value.toString());
}

QVariantList LocalFilesBackend::getItems(const QString &path) {
    QVariantList result;
    QDir dir(path);
    if (!dir.exists()) {
        qWarning("[LocalFiles] directory not found: %s", qPrintable(path));
        return result;
    }
    // Validate against the media root lexically (absolutePath cleans "." / ".."
    // without resolving symlinks) so intentional symlinks placed inside the media
    // root are followed, while ".." traversal out of the root is still blocked.
    QString clean = QDir(path).absolutePath();
    QString root  = QDir(m_mediaRoot).absolutePath();
    bool inside = (clean == root) ||
                  clean.startsWith(root.endsWith('/') ? root : root + '/');
    if (!inside) {
        qWarning("[LocalFiles] path escapes media root: %s", qPrintable(path));
        return result;
    }

    for (const QString &name : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        if (isPlaylist(name)) {
            QString innerPath = dir.absoluteFilePath(name) + "/" + name;
            if (QFileInfo::exists(innerPath)) {
                QVariantMap item;
                item["name"]     = name;
                item["path"]     = innerPath;
                item["isFolder"] = false;
                result.append(item);
                continue;
            }
        }
        QVariantMap item;
        item["name"]     = name;
        item["path"]     = dir.absoluteFilePath(name);
        item["isFolder"] = true;
        result.append(item);
    }

    for (const QString &name : dir.entryList(QDir::Files, QDir::Name)) {
        if (!kMediaExts.contains(QFileInfo(name).suffix().toLower())) continue;
        QVariantMap item;
        item["name"]     = name;
        item["path"]     = dir.absoluteFilePath(name);
        item["isFolder"] = false;
        result.append(item);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Search: names under the media folder, walked a slice at a time.
// ---------------------------------------------------------------------------

// A tree entry for a name, as getItems() makes them; empty for a file that
// isn't media.
QVariantMap LocalFilesBackend::entryFor(const QString &dirPath, const QString &name, bool isDir) const {
    const QString full = QDir(dirPath).absoluteFilePath(name);
    QVariantMap item;
    if (isDir) {
        if (isPlaylist(name) && QFileInfo::exists(full + QLatin1Char('/') + name)) {
            item["name"] = name;
            item["path"] = full + QLatin1Char('/') + name;
            item["isFolder"] = false;
            return item;
        }
        item["name"] = name;
        item["path"] = full;
        item["isFolder"] = true;
        return item;
    }
    if (!kMediaExts.contains(QFileInfo(name).suffix().toLower()))
        return {};
    item["name"] = name;
    item["path"] = full;
    item["isFolder"] = false;
    return item;
}

QVariant LocalFilesBackend::search(const QString &path, const QString &words, bool fresh) {
    if (!fresh && path == m_foundPath)
        return m_found;
    if (!fresh && m_search && m_search->path == path)
        return QVariant();
    m_foundPath.clear();
    m_found.clear();
    // A run under way always has its next slice waiting: one more would make two.
    const bool running = m_search != nullptr;
    m_search = std::make_unique<SearchRun>();
    m_search->path = path;
    m_search->words = words.simplified().toLower().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    // Not through symbolic links: one pointing back up would never end.
    m_search->it = std::make_unique<QDirIterator>(
        m_mediaRoot, QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    if (!running)
        QTimer::singleShot(0, this, &LocalFilesBackend::searchSlice);
    return QVariant();
}

QVariantList LocalFilesBackend::existing(const QVariantList &entries) const {
    QVariantList kept;
    for (const QVariant &v : entries) {
        if (QFileInfo::exists(v.toMap().value("path").toString()))
            kept << v;
    }
    return kept;
}

void LocalFilesBackend::searchSlice() {
    if (!m_search)
        return;
    SearchRun &run = *m_search;
    for (int n = 0; n < kSearchSlice && run.it->hasNext(); ++n) {
        run.it->next();
        const QFileInfo info = run.it->fileInfo();
        const QString name = info.fileName().toLower();
        if (run.words.isEmpty() || !std::all_of(run.words.cbegin(), run.words.cend(),
                                                [&name](const QString &w) { return name.contains(w); }))
            continue;
        const QVariantMap item = entryFor(info.absolutePath(), info.fileName(), info.isDir());
        if (!item.isEmpty())
            run.found.append(item);
    }
    if (run.it->hasNext()) {
        QTimer::singleShot(0, this, &LocalFilesBackend::searchSlice);
        return;
    }
    std::sort(run.found.begin(), run.found.end(), [](const QVariant &a, const QVariant &b) {
        return QString::compare(a.toMap().value("name").toString(), b.toMap().value("name").toString(),
                                Qt::CaseInsensitive) < 0;
    });
    m_foundPath = run.path;
    m_found = run.found.mid(0, kSearchLimit);
    m_search.reset();
    emit searchReady(m_foundPath);
}
