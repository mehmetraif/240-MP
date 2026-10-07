#include "PlaylistsBackend.h"

#include "../../AppCore.h"
#include "../../util/YtDlpLocator.h"
#include "../emby/EmbyBackend.h"
#include "../jellyfin/JellyfinBackend.h"
#include "../local_files/LocalFilesBackend.h"
#include "../youtube/YouTubeBackend.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QProcess>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QUuid>

#include <algorithm>

#ifdef Q_OS_UNIX
#include <fcntl.h>
#include <unistd.h>
#endif

namespace {

const QString kModuleId = QStringLiteral("com.240mp.playlists");
const QString kLocalFiles = QStringLiteral("com.240mp.local_files");
const QString kYouTube = QStringLiteral("com.240mp.youtube");
const QString kJellyfin = QStringLiteral("com.240mp.jellyfin");
const QString kEmby = QStringLiteral("com.240mp.emby");

// The prefix of an item's key, by module.
QString keyPrefix(const QString &moduleId) {
    if (moduleId == kLocalFiles) return QStringLiteral("local:");
    if (moduleId == kYouTube) return QStringLiteral("youtube:");
    if (moduleId == kJellyfin) return QStringLiteral("jellyfin:");
    if (moduleId == kEmby) return QStringLiteral("emby:");
    return {};
}

// A file name every filesystem the folder may be on takes: exFAT's rules,
// which are Windows' (no \ / : * ? " < > |, no control characters, no
// trailing dot or space), and short enough for any of them.
QString safeName(const QString &name) {
    static const QString kForbidden = QStringLiteral("\\/:*?\"<>|");
    QString out;
    for (const QChar c : name)
        out += (c.unicode() < 32 || kForbidden.contains(c)) ? QChar(QLatin1Char(' ')) : c;
    out = out.simplified();
    if (out.size() > 80)
        out = out.left(80).trimmed();
    while (out.endsWith(QLatin1Char('.')) || out.endsWith(QLatin1Char(' ')))
        out.chop(1);
    return out.isEmpty() ? QStringLiteral("video") : out;
}

// The file's data, then its folder's entry for it, flushed to the card: the
// film partition is exFAT, which a power cut mid-write can leave half done.
void syncToDisk(const QString &path) {
#ifdef Q_OS_UNIX
    const int fd = ::open(QFile::encodeName(path).constData(), O_RDONLY);
    if (fd >= 0) {
        ::fsync(fd);
        ::close(fd);
    }
    const int dir = ::open(QFile::encodeName(QFileInfo(path).absolutePath()).constData(),
                           O_RDONLY | O_DIRECTORY);
    if (dir >= 0) {
        ::fsync(dir);
        ::close(dir);
    }
#else
    Q_UNUSED(path)
#endif
}

// A YouTube video's id, from whichever of its fields an entry has.
QString youtubeId(const QVariantMap &entry) {
    QString id = entry.value(QStringLiteral("videoId")).toString();
    if (!id.isEmpty())
        return id;
    static const QRegularExpression kFromUrl(QStringLiteral("[?&]v=([A-Za-z0-9_-]{6,})"));
    const QRegularExpressionMatch m = kFromUrl.match(entry.value(QStringLiteral("url")).toString());
    if (m.hasMatch())
        return m.captured(1);
    const QString path = entry.value(QStringLiteral("path")).toString();
    if (path.startsWith(QLatin1String("video/")))
        return path.mid(6);
    return {};
}

// What a server's reply says the file is: from its Content-Disposition name,
// else its type.
QString extensionOf(QNetworkReply *reply) {
    static const QRegularExpression kName(
        QStringLiteral("filename\\*?=(?:UTF-8'')?\"?([^\";]+)\"?"), QRegularExpression::CaseInsensitiveOption);
    const QString disposition = QString::fromUtf8(reply->rawHeader("Content-Disposition"));
    const QRegularExpressionMatch m = kName.match(disposition);
    if (m.hasMatch()) {
        const QString suffix = QFileInfo(QUrl::fromPercentEncoding(m.captured(1).toUtf8())).suffix();
        if (!suffix.isEmpty() && suffix.size() <= 5)
            return suffix.toLower();
    }
    const QString type = reply->header(QNetworkRequest::ContentTypeHeader).toString().toLower();
    if (type.contains(QLatin1String("mp4"))) return QStringLiteral("mp4");
    if (type.contains(QLatin1String("webm"))) return QStringLiteral("webm");
    if (type.contains(QLatin1String("quicktime"))) return QStringLiteral("mov");
    if (type.contains(QLatin1String("msvideo"))) return QStringLiteral("avi");
    return QStringLiteral("mkv");
}

} // namespace

void PlaylistsBackend::removePartials(const QString &key) const {
    // What yt-dlp leaves of a video it didn't finish: its .part files and the
    // streams it was to merge (".f137.mp4"), all named with "[<id>]".
    if (!key.startsWith(QLatin1String("youtube:")))
        return;
    const QString tag = QLatin1Char('[') + key.mid(8) + QLatin1Char(']');
    QDir dir(QDir(downloadFolder()).filePath(QStringLiteral("YouTube")));
    for (const QFileInfo &f : dir.entryInfoList(QDir::Files))
        if (f.fileName().contains(tag))
            QFile::remove(f.absoluteFilePath());
}

PlaylistsBackend::PlaylistsBackend(const QString &appRoot, const QString &dataRoot, AppCore *appCore,
                                   LocalFilesBackend *localFiles, YouTubeBackend *youtube,
                                   JellyfinBackend *jellyfin, EmbyBackend *emby, QObject *parent)
    : QObject(parent), m_appRoot(appRoot), m_dataRoot(dataRoot), m_appCore(appCore),
      m_localFiles(localFiles), m_youtube(youtube), m_jellyfin(jellyfin), m_emby(emby) {
    load();
    // What was left to download goes on once the app has settled (and the
    // network, at boot, has had a chance to come up).
    QTimer::singleShot(15000, this, &PlaylistsBackend::queueOfflineItems);
}

PlaylistsBackend::~PlaylistsBackend() {
    // A download cut short is begun again next time; its part file stays for
    // yt-dlp to carry on from.
    if (m_active.process) {
        m_active.process->disconnect(this);
        m_active.process->kill();
        m_active.process->waitForFinished(2000);
    }
    if (m_active.reply) {
        m_active.reply->disconnect(this);
        m_active.reply->abort();
    }
    delete m_active.file;
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

void PlaylistsBackend::load() {
    QFile file(m_dataRoot + QStringLiteral("/playlists.json"));
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    for (const QJsonValue &v : root.value(QStringLiteral("playlists")).toArray())
        m_playlists << v.toObject();
    const QJsonObject downloads = root.value(QStringLiteral("downloads")).toObject();
    for (auto it = downloads.begin(); it != downloads.end(); ++it)
        m_downloads.insert(it.key(), it.value().toObject());
}

void PlaylistsBackend::save() const {
    QJsonArray playlists;
    for (const QJsonObject &p : m_playlists)
        playlists << p;
    QJsonObject downloads;
    for (auto it = m_downloads.begin(); it != m_downloads.end(); ++it)
        downloads.insert(it.key(), it.value());
    QJsonObject root;
    root.insert(QStringLiteral("playlists"), playlists);
    root.insert(QStringLiteral("downloads"), downloads);
    QDir().mkpath(m_dataRoot);
    QSaveFile file(m_dataRoot + QStringLiteral("/playlists.json"));
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning("[Playlists] can't write playlists.json");
        return;
    }
    file.write(QJsonDocument(root).toJson());
    file.commit();
}

int PlaylistsBackend::indexOf(const QString &id) const {
    for (int i = 0; i < m_playlists.size(); ++i)
        if (m_playlists[i].value(QStringLiteral("id")).toString() == id)
            return i;
    return -1;
}

QString PlaylistsBackend::downloadFolder() const {
    const QString chosen = m_appCore
        ? m_appCore->get_setting(kModuleId, QStringLiteral("download_folder")).toString().trimmed()
        : QString();
    if (!chosen.isEmpty())
        return chosen;
    const QString media = m_localFiles ? m_localFiles->mediaRoot() : m_dataRoot + QStringLiteral("/media");
    return QDir(media).filePath(QStringLiteral("Playlists"));
}

QString PlaylistsBackend::sourceFolder(const QString &name) const {
    const QString folder = QDir(downloadFolder()).filePath(name);
    QDir().mkpath(folder);
    return folder;
}

void PlaylistsBackend::onSettingChanged(const QString &moduleId, const QString &key,
                                        const QVariant &value) {
    Q_UNUSED(value)
    // Downloads made so far stay where they are; what comes next goes to the
    // folder now chosen.
    if (moduleId == kModuleId && key == QLatin1String("download_folder"))
        emit playlistsChanged();
}

// ---------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------

QVariantList PlaylistsBackend::playlists() const {
    QVariantList out;
    for (const QJsonObject &p : m_playlists) {
        const QString kind = p.value(QStringLiteral("kind")).toString();
        const QJsonArray items = p.value(QStringLiteral("items")).toArray();
        int ready = 0;
        for (const QJsonValue &v : items) {
            int percent = 0;
            QString reason;
            if (itemState(v.toObject(), kind, &percent, &reason) == QLatin1String("ready"))
                ++ready;
        }
        out << QVariantMap{{QStringLiteral("id"), p.value(QStringLiteral("id")).toString()},
                           {QStringLiteral("name"), p.value(QStringLiteral("name")).toString()},
                           {QStringLiteral("kind"), kind},
                           {QStringLiteral("order"), p.value(QStringLiteral("order")).toString()},
                           {QStringLiteral("count"), int(items.size())},
                           {QStringLiteral("ready"), ready}};
    }
    return out;
}

QVariantMap PlaylistsBackend::playlist(const QString &id) const {
    const int i = indexOf(id);
    if (i < 0)
        return {};
    const QJsonObject p = m_playlists[i];
    const QString kind = p.value(QStringLiteral("kind")).toString();
    QVariantList items;
    for (const QJsonValue &v : p.value(QStringLiteral("items")).toArray()) {
        const QJsonObject item = v.toObject();
        int percent = 0;
        QString reason;
        const QString state = itemState(item, kind, &percent, &reason);
        QVariantMap row = item.toVariantMap();
        row.insert(QStringLiteral("state"), state);
        row.insert(QStringLiteral("percent"), percent);
        row.insert(QStringLiteral("reason"), reason);
        items << row;
    }
    return {{QStringLiteral("id"), id},
            {QStringLiteral("name"), p.value(QStringLiteral("name")).toString()},
            {QStringLiteral("kind"), kind},
            {QStringLiteral("order"), p.value(QStringLiteral("order")).toString()},
            {QStringLiteral("items"), items}};
}

QString PlaylistsBackend::createPlaylist(const QString &name, const QString &kind) {
    QJsonObject p;
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    p.insert(QStringLiteral("id"), id);
    p.insert(QStringLiteral("name"), name.trimmed().isEmpty() ? QStringLiteral("Playlist") : name.trimmed());
    p.insert(QStringLiteral("kind"), kind == QLatin1String("offline") ? QStringLiteral("offline")
                                                                     : QStringLiteral("online"));
    p.insert(QStringLiteral("order"), QStringLiteral("inorder"));
    p.insert(QStringLiteral("items"), QJsonArray());
    m_playlists << p;
    save();
    emit playlistsChanged();
    return id;
}

void PlaylistsBackend::renamePlaylist(const QString &id, const QString &name) {
    const int i = indexOf(id);
    if (i < 0 || name.trimmed().isEmpty())
        return;
    m_playlists[i].insert(QStringLiteral("name"), name.trimmed());
    save();
    emit playlistsChanged();
}

void PlaylistsBackend::deletePlaylist(const QString &id) {
    const int i = indexOf(id);
    if (i < 0)
        return;
    m_playlists.removeAt(i);
    m_prepared.remove(id);
    removeM3us(id);
    dropUnreferenced();
    save();
    emit playlistsChanged();
}

void PlaylistsBackend::setOrder(const QString &id, const QString &order) {
    const int i = indexOf(id);
    if (i < 0)
        return;
    m_playlists[i].insert(QStringLiteral("order"), order == QLatin1String("shuffle") ? QStringLiteral("shuffle")
                                                                                    : QStringLiteral("inorder"));
    save();
    emit playlistsChanged();
}

bool PlaylistsBackend::supports(const QString &moduleId, const QString &kind) const {
    Q_UNUSED(kind)
    // Every source mpv plays here can also be put on the device: Local Files'
    // files are on it already, the others download.
    return !keyPrefix(moduleId).isEmpty();
}

QJsonObject PlaylistsBackend::itemFor(const QString &moduleId, const QVariantMap &entry) const {
    QJsonObject source;
    QString id;
    QString title = entry.value(QStringLiteral("title")).toString();
    if (title.isEmpty())
        title = entry.value(QStringLiteral("name")).toString();
    if (moduleId == kLocalFiles) {
        if (entry.value(QStringLiteral("isFolder")).toBool())
            return {};
        id = entry.value(QStringLiteral("path")).toString();
        source.insert(QStringLiteral("path"), id);
        if (title.isEmpty())
            title = QFileInfo(id).completeBaseName();
    } else if (moduleId == kYouTube) {
        id = youtubeId(entry);
        source.insert(QStringLiteral("videoId"), id);
        source.insert(QStringLiteral("channel"), entry.value(QStringLiteral("channelName")).toString());
    } else if (moduleId == kJellyfin || moduleId == kEmby) {
        id = entry.value(QStringLiteral("itemId")).toString();
        source.insert(QStringLiteral("itemId"), id);
        // An episode: its show, to tell it from another show's "Pilot".
        QString series = entry.value(QStringLiteral("seriesName")).toString();
        if (series.isEmpty())
            series = entry.value(QStringLiteral("grandparentTitle")).toString();
        if (!series.isEmpty() && !title.startsWith(series))
            title = series + QStringLiteral(" - ") + title;
    }
    if (id.isEmpty())
        return {};
    QJsonObject item;
    item.insert(QStringLiteral("id"), QUuid::createUuid().toString(QUuid::WithoutBraces));
    item.insert(QStringLiteral("module"), moduleId);
    item.insert(QStringLiteral("key"), keyPrefix(moduleId) + id);
    item.insert(QStringLiteral("title"), title.isEmpty() ? id : title);
    item.insert(QStringLiteral("source"), source);
    return item;
}

QVariantMap PlaylistsBackend::addEntry(const QString &playlistId, const QString &moduleId,
                                       const QVariantMap &entry) {
    const int i = indexOf(playlistId);
    if (i < 0)
        return {{QStringLiteral("ok"), false}, {QStringLiteral("reason"), QStringLiteral("unknown")}};
    const QString kind = m_playlists[i].value(QStringLiteral("kind")).toString();
    if (!supports(moduleId, kind))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("reason"), QStringLiteral("unsupported")}};
    const QJsonObject item = itemFor(moduleId, entry);
    if (item.isEmpty())
        return {{QStringLiteral("ok"), false}, {QStringLiteral("reason"), QStringLiteral("unsupported")}};

    QJsonArray items = m_playlists[i].value(QStringLiteral("items")).toArray();
    const QString key = item.value(QStringLiteral("key")).toString();
    for (const QJsonValue &v : items)
        if (v.toObject().value(QStringLiteral("key")).toString() == key)
            return {{QStringLiteral("ok"), false}, {QStringLiteral("reason"), QStringLiteral("duplicate")},
                    {QStringLiteral("title"), item.value(QStringLiteral("title")).toString()}};
    items << item;
    m_playlists[i].insert(QStringLiteral("items"), items);
    save();
    if (kind == QLatin1String("offline") && moduleId != kLocalFiles)
        enqueue(key);
    emit playlistsChanged();
    return {{QStringLiteral("ok"), true}, {QStringLiteral("title"), item.value(QStringLiteral("title")).toString()}};
}

void PlaylistsBackend::removeItem(const QString &playlistId, const QString &itemId) {
    const int i = indexOf(playlistId);
    if (i < 0)
        return;
    QJsonArray items = m_playlists[i].value(QStringLiteral("items")).toArray();
    for (int j = 0; j < items.size(); ++j) {
        if (items[j].toObject().value(QStringLiteral("id")).toString() == itemId) {
            items.removeAt(j);
            break;
        }
    }
    m_playlists[i].insert(QStringLiteral("items"), items);
    dropUnreferenced();
    save();
    emit playlistsChanged();
}

void PlaylistsBackend::moveItem(const QString &playlistId, const QString &itemId, int delta) {
    const int i = indexOf(playlistId);
    if (i < 0)
        return;
    QJsonArray items = m_playlists[i].value(QStringLiteral("items")).toArray();
    for (int j = 0; j < items.size(); ++j) {
        if (items[j].toObject().value(QStringLiteral("id")).toString() != itemId)
            continue;
        const int to = j + delta;
        if (to < 0 || to >= items.size())
            return;
        const QJsonValue moved = items[j];
        items.removeAt(j);
        items.insert(to, moved);
        m_playlists[i].insert(QStringLiteral("items"), items);
        save();
        emit playlistsChanged();
        return;
    }
}

void PlaylistsBackend::retryDownloads(const QString &playlistId) {
    const int i = indexOf(playlistId);
    if (i < 0)
        return;
    for (const QJsonValue &v : m_playlists[i].value(QStringLiteral("items")).toArray()) {
        const QString key = v.toObject().value(QStringLiteral("key")).toString();
        if (m_downloads.value(key).value(QStringLiteral("state")).toString() == QLatin1String("failed"))
            m_downloads.remove(key);
    }
    save();
    queueOfflineItems();
    emit playlistsChanged();
}

// ---------------------------------------------------------------------------
// What plays
// ---------------------------------------------------------------------------

QString PlaylistsBackend::itemState(const QJsonObject &item, const QString &kind, int *percent,
                                    QString *reason) const {
    const QString module = item.value(QStringLiteral("module")).toString();
    const QJsonObject source = item.value(QStringLiteral("source")).toObject();
    if (module == kLocalFiles)
        return QFileInfo::exists(source.value(QStringLiteral("path")).toString()) ? QStringLiteral("ready")
                                                                                  : QStringLiteral("missing");
    if (kind != QLatin1String("offline")) {
        if (module == kJellyfin && !(m_jellyfin && m_jellyfin->signedIn())) {
            *reason = QStringLiteral("signed out");
            return QStringLiteral("missing");
        }
        if (module == kEmby && !(m_emby && m_emby->signedIn())) {
            *reason = QStringLiteral("signed out");
            return QStringLiteral("missing");
        }
        return QStringLiteral("ready");
    }
    const QString key = item.value(QStringLiteral("key")).toString();
    if (m_active.key == key) {
        *percent = m_active.percent;
        return QStringLiteral("downloading");
    }
    const QJsonObject download = m_downloads.value(key);
    const QString state = download.value(QStringLiteral("state")).toString();
    if (state == QLatin1String("done") && QFileInfo::exists(download.value(QStringLiteral("path")).toString()))
        return QStringLiteral("ready");
    if (state == QLatin1String("failed")) {
        *reason = download.value(QStringLiteral("reason")).toString();
        return QStringLiteral("failed");
    }
    return QStringLiteral("queued");
}

QString PlaylistsBackend::playableUrl(const QJsonObject &item, const QString &kind) const {
    const QString module = item.value(QStringLiteral("module")).toString();
    const QJsonObject source = item.value(QStringLiteral("source")).toObject();
    if (module == kLocalFiles) {
        const QString path = source.value(QStringLiteral("path")).toString();
        return QFileInfo::exists(path) ? path : QString();
    }
    if (kind == QLatin1String("offline")) {
        const QJsonObject download = m_downloads.value(item.value(QStringLiteral("key")).toString());
        const QString path = download.value(QStringLiteral("path")).toString();
        return download.value(QStringLiteral("state")).toString() == QLatin1String("done") && QFileInfo::exists(path)
                   ? path : QString();
    }
    if (module == kYouTube)
        return QStringLiteral("https://www.youtube.com/watch?v=") + source.value(QStringLiteral("videoId")).toString();
    const QString itemId = source.value(QStringLiteral("itemId")).toString();
    if (module == kJellyfin)
        return m_jellyfin && m_jellyfin->signedIn() ? m_jellyfin->streamUrl(itemId) : QString();
    if (module == kEmby)
        return m_emby && m_emby->signedIn() ? m_emby->streamUrl(itemId) : QString();
    return {};
}

QVariantMap PlaylistsBackend::prepare(const QString &playlistId, const QString &fromItemId) {
    const int i = indexOf(playlistId);
    if (i < 0)
        return {};
    const QJsonObject p = m_playlists[i];
    const QString kind = p.value(QStringLiteral("kind")).toString();
    const bool shuffled = p.value(QStringLiteral("order")).toString() == QLatin1String("shuffle");
    struct Entry {
        QString id;
        QString title;
        QString url;
    };
    QList<Entry> entries;
    int skipped = 0;
    bool youtube = false;
    bool images = false;
    for (const QJsonValue &v : p.value(QStringLiteral("items")).toArray()) {
        const QJsonObject item = v.toObject();
        const QString url = playableUrl(item, kind);
        if (url.isEmpty()) {
            ++skipped;
            continue;
        }
        const QString module = item.value(QStringLiteral("module")).toString();
        if (kind != QLatin1String("offline") && module == kYouTube)
            youtube = true;
        if (module == kLocalFiles && m_localFiles && m_localFiles->isImage(url))
            images = true;
        // The title mpv's display shows, on one line.
        entries << Entry{item.value(QStringLiteral("id")).toString(),
                         item.value(QStringLiteral("title")).toString().simplified(), url};
    }
    // Shuffled here rather than by mpv, so the m3u's order is the order it
    // plays in and a place in it names a video (savePosition). The video it
    // is played from, if any, first.
    if (shuffled) {
        std::shuffle(entries.begin(), entries.end(), *QRandomGenerator::global());
        for (int j = 0; j < entries.size(); ++j) {
            if (entries[j].id == fromItemId) {
                entries.move(j, 0);
                break;
            }
        }
    }
    QStringList ids;
    QString m3u = QStringLiteral("#EXTM3U\n");
    for (const Entry &e : entries) {
        m3u += QStringLiteral("#EXTINF:-1,") + e.title + QLatin1Char('\n') + e.url + QLatin1Char('\n');
        ids << e.id;
    }
    // A new file each time, so a list played afresh is never taken for the
    // same one still playing behind the menus (MpvController carries that
    // on when it is started again just as it was). It may hold a server's
    // token: for this user's eyes only, and the last one only.
    const QString folder = m_dataRoot + QStringLiteral("/playlists");
    QDir().mkpath(folder);
    removeM3us(playlistId);
    const QString path = folder + QLatin1Char('/') + playlistId + QLatin1Char('-')
                         + QString::number(++m_serial) + QStringLiteral(".m3u");
    QSaveFile file(path);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(m3u.toUtf8());
        file.commit();
        QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    }
    m_prepared.insert(playlistId, ids);

    // Where it stopped, for a list in order played from its start.
    const QJsonObject resume = p.value(QStringLiteral("resume")).toObject();
    const int resumeIndex = shuffled || !fromItemId.isEmpty()
                                ? -1 : int(ids.indexOf(resume.value(QStringLiteral("itemId")).toString()));
    return {{QStringLiteral("file"), path},
            {QStringLiteral("count"), int(ids.size())},
            {QStringLiteral("skipped"), skipped},
            {QStringLiteral("youtube"), youtube},
            {QStringLiteral("images"), images},
            {QStringLiteral("shuffled"), shuffled},
            {QStringLiteral("startIndex"), fromItemId.isEmpty() ? -1 : int(ids.indexOf(fromItemId))},
            {QStringLiteral("resumeIndex"), resumeIndex},
            {QStringLiteral("resumeMs"), resumeIndex >= 0 ? resume.value(QStringLiteral("positionMs")).toInt() : 0}};
}

void PlaylistsBackend::removeM3us(const QString &playlistId) const {
    QDir folder(m_dataRoot + QStringLiteral("/playlists"));
    for (const QString &name : folder.entryList({playlistId + QStringLiteral("*.m3u")}, QDir::Files))
        folder.remove(name);
}

int PlaylistsBackend::savedPositionMs(const QString &playlistId) const {
    const int i = indexOf(playlistId);
    if (i < 0)
        return 0;
    return m_playlists[i].value(QStringLiteral("resume")).toObject().value(QStringLiteral("positionMs")).toInt();
}

void PlaylistsBackend::savePosition(const QString &playlistId, int index, int positionMs) {
    const int i = indexOf(playlistId);
    const QStringList ids = m_prepared.value(playlistId);
    if (i < 0 || index < 0 || index >= ids.size())
        return;
    m_playlists[i].insert(QStringLiteral("resume"),
                          QJsonObject{{QStringLiteral("itemId"), ids[index]},
                                      {QStringLiteral("positionMs"), positionMs}});
    save();
}

void PlaylistsBackend::clearPosition(const QString &playlistId) {
    const int i = indexOf(playlistId);
    if (i < 0 || !m_playlists[i].contains(QStringLiteral("resume")))
        return;
    m_playlists[i].remove(QStringLiteral("resume"));
    save();
}

// ---------------------------------------------------------------------------
// The servers' folders
// ---------------------------------------------------------------------------

QVariant PlaylistsBackend::serverListing(const QString &moduleId, const QString &parentId, bool preview) {
    const QString key = moduleId + QLatin1Char('|') + parentId;
    const auto cached = m_listings.constFind(key);
    if (cached != m_listings.constEnd())
        return *cached;
    const bool jellyfin = moduleId == kJellyfin;
    if (!jellyfin && moduleId != kEmby)
        return QVariantList();
    if (!(jellyfin ? (m_jellyfin && m_jellyfin->signedIn()) : (m_emby && m_emby->signedIn())))
        return QVariantList();
    if (preview || m_listingsPending.contains(key))
        return QVariant();
    m_listingsPending.insert(key);
    QNetworkReply *reply = m_nam.get(jellyfin ? m_jellyfin->browseRequest(parentId)
                                              : m_emby->browseRequest(parentId));
    const int epoch = m_listingsEpoch;
    connect(reply, &QNetworkReply::finished, this, [this, reply, key, moduleId, parentId, epoch]() {
        reply->deleteLater();
        // Asked for again since (forgetListings): this answer is not wanted.
        if (epoch != m_listingsEpoch)
            return;
        m_listingsPending.remove(key);
        QVariantList out;
        if (reply->error() != QNetworkReply::NoError) {
            qWarning("[Playlists] %s listing %s failed: %s", qPrintable(moduleId), qPrintable(parentId),
                     qPrintable(reply->errorString()));
        }
        const QJsonArray items = QJsonDocument::fromJson(reply->readAll()).object()
                                     .value(QStringLiteral("Items")).toArray();
        for (const QJsonValue &v : items) {
            const QJsonObject item = v.toObject();
            const bool folder = item.value(QStringLiteral("IsFolder")).toBool();
            if (parentId.isEmpty()) {
                // The libraries with videos in them.
                static const QStringList kNoVideo{QStringLiteral("music"), QStringLiteral("books"),
                                                  QStringLiteral("photos"), QStringLiteral("livetv")};
                if (kNoVideo.contains(item.value(QStringLiteral("CollectionType")).toString().toLower()))
                    continue;
            } else if (!folder && item.value(QStringLiteral("MediaType")).toString() != QLatin1String("Video")) {
                continue;
            }
            const QString type = item.value(QStringLiteral("Type")).toString();
            QString name = item.value(QStringLiteral("Name")).toString();
            // An episode in a season: its number first.
            if (type == QLatin1String("Episode") && item.contains(QStringLiteral("IndexNumber"))
                && parentId != QLatin1String("resume") && parentId != QLatin1String("nextup"))
                name = QString::number(item.value(QStringLiteral("IndexNumber")).toInt()) + QStringLiteral(". ") + name;
            out << QVariantMap{{QStringLiteral("name"), name},
                               {QStringLiteral("title"), item.value(QStringLiteral("Name")).toString()},
                               {QStringLiteral("itemId"), item.value(QStringLiteral("Id")).toString()},
                               {QStringLiteral("isFolder"), folder},
                               {QStringLiteral("type"), type.toLower()},
                               {QStringLiteral("seriesName"), item.value(QStringLiteral("SeriesName")).toString()}};
        }
        m_listings.insert(key, out);
        emit serverListingReady(moduleId, parentId);
    });
    return QVariant();
}

void PlaylistsBackend::forgetListings() {
    m_listings.clear();
    m_listingsPending.clear();
    ++m_listingsEpoch;
}

// ---------------------------------------------------------------------------
// Downloads
// ---------------------------------------------------------------------------

bool PlaylistsBackend::referencedOffline(const QString &key) const {
    for (const QJsonObject &p : m_playlists) {
        if (p.value(QStringLiteral("kind")).toString() != QLatin1String("offline"))
            continue;
        for (const QJsonValue &v : p.value(QStringLiteral("items")).toArray())
            if (v.toObject().value(QStringLiteral("key")).toString() == key)
                return true;
    }
    return false;
}

void PlaylistsBackend::dropUnreferenced() {
    QStringList keys = m_downloads.keys() + m_queue;
    if (!m_active.key.isEmpty())
        keys << m_active.key;
    keys.removeDuplicates();
    for (const QString &key : keys) {
        if (referencedOffline(key))
            continue;
        cancel(key);
        const QJsonObject download = m_downloads.take(key);
        const QString path = download.value(QStringLiteral("path")).toString();
        if (!path.isEmpty() && QFile::remove(path))
            syncToDisk(path);
    }
}

void PlaylistsBackend::queueOfflineItems() {
    for (const QJsonObject &p : m_playlists) {
        if (p.value(QStringLiteral("kind")).toString() != QLatin1String("offline"))
            continue;
        for (const QJsonValue &v : p.value(QStringLiteral("items")).toArray()) {
            const QJsonObject item = v.toObject();
            if (item.value(QStringLiteral("module")).toString() == kLocalFiles)
                continue;
            const QString key = item.value(QStringLiteral("key")).toString();
            const QJsonObject download = m_downloads.value(key);
            const QString state = download.value(QStringLiteral("state")).toString();
            // One the server refused stays refused until asked again.
            if (state == QLatin1String("failed")
                && download.value(QStringLiteral("reason")).toString() == QLatin1String("not allowed"))
                continue;
            enqueue(key);
        }
    }
}

void PlaylistsBackend::enqueue(const QString &key) {
    if (m_active.key == key || m_queue.contains(key))
        return;
    // On the device already, for another list: never fetched twice.
    const QJsonObject download = m_downloads.value(key);
    if (download.value(QStringLiteral("state")).toString() == QLatin1String("done")
        && QFileInfo::exists(download.value(QStringLiteral("path")).toString()))
        return;
    m_queue << key;
    QTimer::singleShot(0, this, &PlaylistsBackend::startNext);
}

void PlaylistsBackend::startNext() {
    if (!m_active.key.isEmpty())
        return;
    while (!m_queue.isEmpty()) {
        const QString key = m_queue.takeFirst();
        if (!referencedOffline(key))
            continue;
        QJsonObject item;
        for (const QJsonObject &p : m_playlists) {
            for (const QJsonValue &v : p.value(QStringLiteral("items")).toArray())
                if (v.toObject().value(QStringLiteral("key")).toString() == key) {
                    item = v.toObject();
                    break;
                }
            if (!item.isEmpty())
                break;
        }
        const QString module = item.value(QStringLiteral("module")).toString();
        m_active = Active();
        m_active.key = key;
        if (module == kYouTube)
            startYouTube(key, item);
        else if (module == kJellyfin || module == kEmby)
            startServer(key, item);
        else {
            m_active = Active();
            continue;
        }
        emit playlistsChanged();
        return;
    }
}

bool PlaylistsBackend::writable(const QString &folder) {
    const QFileInfo info(folder);
    if (info.isDir() && info.isWritable())
        return true;
    // A card from before the film partition was writable, say (ro in fstab).
    m_active.reason = QStringLiteral("can't write to ") + downloadFolder();
    QTimer::singleShot(0, this, [this]() { finish(false); });
    return false;
}

void PlaylistsBackend::startYouTube(const QString &key, const QJsonObject &item) {
    const QString program = ytdlp::locate(m_dataRoot);
    if (program.isEmpty() || !m_youtube) {
        m_active.reason = QStringLiteral("no yt-dlp");
        QTimer::singleShot(0, this, [this]() { finish(false); });
        return;
    }
    const QString folder = sourceFolder(QStringLiteral("YouTube"));
    if (!writable(folder))
        return;
    const QString videoId = item.value(QStringLiteral("source")).toObject().value(QStringLiteral("videoId")).toString();
    // The way the YouTube module plays it (its ADVANCED settings), as a file.
    auto setting = [this](const QString &key, const QString &fallback) {
        const QString value = m_appCore ? m_appCore->get_setting(kYouTube, key).toString() : QString();
        return value.isEmpty() ? fallback : value;
    };
    const QString resolution = setting(QStringLiteral("playback_resolution"), QStringLiteral("480p"));
    QStringList args = m_youtube->downloadArgs({
        {QStringLiteral("resolution"), resolution},
        {QStringLiteral("codec"), setting(QStringLiteral("video_codec"), QStringLiteral("H.264"))},
        {QStringLiteral("maxFrameRate"), setting(QStringLiteral("max_frame_rate"), QStringLiteral("Any"))},
        {QStringLiteral("audioLanguage"), setting(QStringLiteral("audio_language"), QStringLiteral("original"))}});
    // Video and sound come apart above 360p, and only ffmpeg puts them back
    // together; without it, the best file that has both.
    if (!QStandardPaths::findExecutable(QStringLiteral("ffmpeg")).isEmpty()) {
        args << QStringLiteral("--merge-output-format") << QStringLiteral("mp4");
    } else {
        const int height = QString(resolution).remove(QLatin1Char('p')).toInt();
        args[1] = QStringLiteral("best[height<=?%1][vcodec^=avc1]/best[height<=?%1]/best").arg(height > 0 ? height : 480);
    }
    args << QStringLiteral("--newline") << QStringLiteral("--no-playlist") << QStringLiteral("--no-mtime")
         // exFAT's rules for names, which are Windows'.
         << QStringLiteral("--windows-filenames")
         << QStringLiteral("-o") << folder + QStringLiteral("/%(title).80B [%(id)s].%(ext)s")
         // The file's path once it is complete; quiet otherwise, but for the progress.
         << QStringLiteral("--print") << QStringLiteral("after_move:filepath")
         << QStringLiteral("--no-simulate") << QStringLiteral("--progress")
         << QStringLiteral("--") << QStringLiteral("https://www.youtube.com/watch?v=") + videoId;

    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_active.process = process;
    connect(process, &QProcess::readyRead, this, [this, process, key]() {
        static const QRegularExpression kPercent(QStringLiteral("\\[download\\]\\s+([0-9.]+)%"));
        while (process->canReadLine()) {
            const QString line = QString::fromUtf8(process->readLine()).trimmed();
            const QRegularExpressionMatch m = kPercent.match(line);
            if (m.hasMatch()) {
                const int percent = int(m.captured(1).toDouble());
                if (percent != m_active.percent) {
                    m_active.percent = percent;
                    emit downloadProgress(key, percent);
                }
            } else if (line.startsWith(QLatin1Char('/')) && QFileInfo::exists(line)) {
                m_active.finalPath = line;
            } else if (line.startsWith(QLatin1String("ERROR:"))) {
                m_active.reason = line.mid(6).trimmed();
            }
        }
    });
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        const QString rest = QString::fromUtf8(process->readAll()).trimmed();
        for (const QString &line : rest.split(QLatin1Char('\n'))) {
            const QString l = line.trimmed();
            if (l.startsWith(QLatin1Char('/')) && QFileInfo::exists(l))
                m_active.finalPath = l;
        }
        finish(status == QProcess::NormalExit && code == 0 && !m_active.finalPath.isEmpty());
    });
    connect(process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_active.reason = QStringLiteral("no yt-dlp");
            finish(false);
        }
    });
    qDebug("[Playlists] downloading %s", qPrintable(key));
    process->start(program, args);
}

void PlaylistsBackend::startServer(const QString &key, const QJsonObject &item) {
    const bool jellyfin = item.value(QStringLiteral("module")).toString() == kJellyfin;
    const QString itemId = item.value(QStringLiteral("source")).toObject().value(QStringLiteral("itemId")).toString();
    const bool signedIn = jellyfin ? (m_jellyfin && m_jellyfin->signedIn()) : (m_emby && m_emby->signedIn());
    if (!signedIn) {
        m_active.reason = QStringLiteral("signed out");
        QTimer::singleShot(0, this, [this]() { finish(false); });
        return;
    }
    const QString folder = sourceFolder(jellyfin ? QStringLiteral("Jellyfin") : QStringLiteral("Emby"));
    if (!writable(folder))
        return;
    const QString base = folder + QLatin1Char('/') + safeName(item.value(QStringLiteral("title")).toString())
                         + QStringLiteral(" [") + itemId + QLatin1Char(']');
    m_active.partPath = base + QStringLiteral(".part");
    m_active.file = new QFile(m_active.partPath);
    if (!m_active.file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        m_active.reason = QStringLiteral("can't write to ") + downloadFolder();
        QTimer::singleShot(0, this, [this]() { finish(false); });
        return;
    }
    const QNetworkRequest request = jellyfin ? m_jellyfin->downloadRequest(itemId) : m_emby->downloadRequest(itemId);
    QNetworkReply *reply = m_nam.get(request);
    m_active.reply = reply;
    connect(reply, &QNetworkReply::readyRead, this, [this, reply]() {
        if (m_active.file && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() < 300)
            m_active.file->write(reply->readAll());
    });
    connect(reply, &QNetworkReply::downloadProgress, this, [this, key](qint64 received, qint64 total) {
        if (total <= 0)
            return;
        const int percent = int(received * 100 / total);
        if (percent != m_active.percent) {
            m_active.percent = percent;
            emit downloadProgress(key, percent);
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, base]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        bool ok = reply->error() == QNetworkReply::NoError && status < 300 && m_active.file;
        if (ok) {
            m_active.file->write(reply->readAll());
            ok = m_active.file->flush();
            m_active.file->close();
            const QString finalPath = base + QLatin1Char('.') + extensionOf(reply);
            QFile::remove(finalPath);
            ok = ok && QFile::rename(m_active.partPath, finalPath);
            if (ok)
                m_active.finalPath = finalPath;
        } else {
            m_active.reason = (status == 401 || status == 403) ? QStringLiteral("not allowed")
                                                               : reply->errorString();
        }
        reply->deleteLater();
        finish(ok);
    });
    qDebug("[Playlists] downloading %s", qPrintable(key));
}

void PlaylistsBackend::finish(bool ok) {
    const QString key = m_active.key;
    if (key.isEmpty())
        return;
    if (m_active.file) {
        m_active.file->close();
        delete m_active.file;
        m_active.file = nullptr;
    }
    if (m_active.process)
        m_active.process->deleteLater();
    if (ok) {
        syncToDisk(m_active.finalPath);
        m_downloads.insert(key, QJsonObject{{QStringLiteral("path"), m_active.finalPath},
                                            {QStringLiteral("state"), QStringLiteral("done")},
                                            {QStringLiteral("bytes"), double(QFileInfo(m_active.finalPath).size())}});
        qDebug("[Playlists] downloaded %s: %s", qPrintable(key), qPrintable(m_active.finalPath));
    } else {
        if (!m_active.partPath.isEmpty())
            QFile::remove(m_active.partPath);
        removePartials(key);
        const QString reason = m_active.reason.isEmpty() ? QStringLiteral("error") : m_active.reason;
        m_downloads.insert(key, QJsonObject{{QStringLiteral("state"), QStringLiteral("failed")},
                                            {QStringLiteral("reason"), reason}});
        qWarning("[Playlists] download of %s failed: %s", qPrintable(key), qPrintable(reason));
    }
    m_active = Active();
    // Taken off every offline list while it came: not kept.
    if (!referencedOffline(key))
        dropUnreferenced();
    save();
    emit playlistsChanged();
    QTimer::singleShot(0, this, &PlaylistsBackend::startNext);
}

void PlaylistsBackend::cancel(const QString &key) {
    m_queue.removeAll(key);
    if (m_active.key != key)
        return;
    if (m_active.process) {
        m_active.process->disconnect(this);
        m_active.process->kill();
        m_active.process->waitForFinished(2000);
        m_active.process->deleteLater();
    }
    if (m_active.reply) {
        m_active.reply->disconnect(this);
        m_active.reply->abort();
        m_active.reply->deleteLater();
    }
    if (m_active.file) {
        m_active.file->close();
        delete m_active.file;
    }
    if (!m_active.partPath.isEmpty())
        QFile::remove(m_active.partPath);
    removePartials(key);
    m_active = Active();
    QTimer::singleShot(0, this, &PlaylistsBackend::startNext);
}
