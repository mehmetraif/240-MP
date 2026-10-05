#include "YouTubeBackend.h"
#include "../../util/YtDlpLocator.h"

#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QTimer>
#include <QUrl>
#include <QXmlStreamReader>

#include <algorithm>
#include <utility>

static const char *kSubscriptionsFileName = "youtube_subscriptions.txt";
static const char *kPlaylistsFileName     = "youtube_playlists.txt";

// What the tree's help line says when a source fails.
static const char *kSubscriptionsProblem = "Could not load the subscriptions: check the network";
static const char *kPlaylistsProblem     = "Could not load the playlists: check the network,"
                                           " and that yt-dlp is installed";
static const char *kSearchProblem        = "Could not search YouTube: check the network,"
                                           " and that yt-dlp is up to date";
static const char *kNoYtDlpProblem       = "Searching needs yt-dlp, which is not installed";

static QString watchUrlFor(const QString &videoId) {
    return QStringLiteral("https://www.youtube.com/watch?v=") + videoId;
}

YouTubeBackend::YouTubeBackend(const QString &appRoot, const QString &dataRoot, QObject *parent)
    : QObject(parent), m_appRoot(appRoot), m_dataRoot(dataRoot)
{
}

// ---------------------------------------------------------------------------
// Subscriptions file
// ---------------------------------------------------------------------------

QStringList YouTubeBackend::readSubscriptionIds(QString *error) const {
    const QString path = m_dataRoot + "/" + kSubscriptionsFileName;
    if (!QFile::exists(path)) {
        if (error)
            *error = QStringLiteral("NO SUBSCRIPTIONS FILE FOUND\n"
                                    "CREATE YOUTUBE_SUBSCRIPTIONS.TXT IN THE DATA DIRECTORY\n"
                                    "WITH ONE CHANNEL ID PER LINE");
        return {};
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (error)
            *error = QStringLiteral("COULD NOT READ YOUTUBE_SUBSCRIPTIONS.TXT");
        return {};
    }
    QStringList ids;
    while (!f.atEnd()) {
        QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;
        // Be lenient with pasted channel URLs: take the segment after "channel/".
        const int slash = line.indexOf(QLatin1String("channel/"));
        if (slash >= 0) {
            line = line.mid(slash + 8);
            const int end = line.indexOf(QRegularExpression(QStringLiteral("[/?#]")));
            if (end >= 0)
                line = line.left(end);
        }
        if (!line.isEmpty() && !ids.contains(line))
            ids << line;
    }
    if (ids.isEmpty() && error)
        *error = QStringLiteral("NO CHANNELS FOUND IN YOUTUBE_SUBSCRIPTIONS.TXT");
    return ids;
}

QVariantMap YouTubeBackend::check_subscriptions() {
    QString error;
    const QStringList ids = readSubscriptionIds(&error);
    QVariantMap result;
    result["ok"]           = error.isEmpty();
    result["error"]        = error;
    result["fileExists"]   = QFile::exists(m_dataRoot + "/" + kSubscriptionsFileName);
    result["channelCount"] = ids.size();
    return result;
}

// ---------------------------------------------------------------------------
// Loaders — all route through one cache-fill path so a single in-flight
// refresh can serve every waiting view.
// ---------------------------------------------------------------------------

void YouTubeBackend::load_subscriptions_feed(bool forceRefresh) {
    m_emitFeedWhenDone = true;
    ensureFresh(forceRefresh);
}

void YouTubeBackend::load_channels(bool forceRefresh) {
    m_emitChannelsWhenDone = true;
    ensureFresh(forceRefresh);
}

void YouTubeBackend::load_channel_videos(const QString &channelId, bool forceRefresh) {
    m_emitChannelVideosWhenDone = channelId;
    ensureFresh(forceRefresh);
}

void YouTubeBackend::ensureFresh(bool forceRefresh) {
    if (m_pendingChannels > 0)
        return; // refresh already in flight — the emit flags queue on it

    QString error;
    const QStringList ids = readSubscriptionIds(&error);
    if (ids.isEmpty()) {
        m_emitFeedWhenDone     = false;
        m_emitChannelsWhenDone = false;
        m_emitChannelVideosWhenDone.clear();
        emit errorOccurred(error);
        return;
    }
    m_channelOrder = ids;

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QStringList stale;
    for (const QString &id : ids) {
        ChannelEntry &entry = m_channels[id];
        entry.channelId = id;
        if (forceRefresh || !entry.feedOk || now - entry.fetchedMs > kCacheTtlMs)
            stale << id;
    }

    if (stale.isEmpty()) {
        finishAggregate(); // everything fresh — serve from cache
        return;
    }
    m_pendingChannels = stale.size();
    for (const QString &id : stale)
        refreshChannel(id);
}

// ---------------------------------------------------------------------------
// Per-channel fetch: the official RSS feed
// ---------------------------------------------------------------------------

QNetworkRequest YouTubeBackend::makeRequest(const QUrl &url) const {
    QNetworkRequest req(url);
    req.setTransferTimeout(10000);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                                 "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"));
    return req;
}

// Atom feed → channel name + video maps (newest first, as served).
// Partial parses are kept: only a parse error with zero entries counts as failure.
static bool parseRssFeed(const QByteArray &data, const QString &channelId,
                         QString *channelName, QVariantList *videos) {
    static const QLatin1String kAtomNs("http://www.w3.org/2005/Atom");
    QXmlStreamReader xml(data);
    bool inEntry = false;
    QString videoId, title, altLink, description;
    QDateTime published;
    while (!xml.atEnd()) {
        xml.readNext();
        if (xml.isStartElement()) {
            const auto name = xml.name();
            if (name == QLatin1String("entry")) {
                inEntry = true;
                videoId.clear();
                title.clear();
                altLink.clear();
                description.clear();
                published = QDateTime();
            } else if (!inEntry && name == QLatin1String("title") && channelName->isEmpty()) {
                *channelName = xml.readElementText();
            } else if (inEntry && name == QLatin1String("videoId")) {
                videoId = xml.readElementText();
            } else if (inEntry && title.isEmpty() && name == QLatin1String("title")
                       && xml.namespaceUri() == kAtomNs) {
                // namespace check keeps <media:title> (inside media:group) out
                title = xml.readElementText();
            } else if (inEntry && name == QLatin1String("description")) {
                // media:description, inside media:group
                description = xml.readElementText();
            } else if (inEntry && name == QLatin1String("published")) {
                published = QDateTime::fromString(xml.readElementText(), Qt::ISODate);
            } else if (inEntry && name == QLatin1String("link")
                       && xml.attributes().value(QLatin1String("rel")) == QLatin1String("alternate")) {
                // Shorts expose a /shorts/<id> alternate href; normal uploads use /watch?v=<id>
                altLink = xml.attributes().value(QLatin1String("href")).toString();
            }
        } else if (xml.isEndElement() && xml.name() == QLatin1String("entry")) {
            inEntry = false;
            if (videoId.isEmpty())
                continue;
            QVariantMap v;
            v["videoId"]     = videoId;
            v["title"]       = title;
            v["channelId"]   = channelId;
            v["channelName"] = QString(); // filled in once the feed title is known
            v["publishedAt"] = published.isValid() ? published.toUTC().toString(Qt::ISODate)
                                                   : QString();
            v["publishedMs"] = published.isValid() ? published.toMSecsSinceEpoch() : qint64(0);
            v["url"]         = watchUrlFor(videoId);
            v["isShort"]     = altLink.contains(QLatin1String("/shorts/"));
            v["description"] = description;
            videos->append(v);
        }
    }
    return !(xml.hasError() && videos->isEmpty());
}

void YouTubeBackend::refreshChannel(const QString &channelId) {
    QUrl rssUrl(QStringLiteral("https://www.youtube.com/feeds/videos.xml"));
    rssUrl.setQuery(QStringLiteral("channel_id=") + channelId);
    QNetworkReply *reply = m_nam.get(makeRequest(rssUrl));
    connect(reply, &QNetworkReply::finished, this, [this, reply, channelId]() {
        reply->deleteLater();
        ChannelEntry &e = m_channels[channelId];
        if (reply->error() == QNetworkReply::NoError) {
            QString name;
            QVariantList videos;
            if (parseRssFeed(reply->readAll(), channelId, &name, &videos)) {
                for (QVariant &v : videos) {
                    QVariantMap m = v.toMap();
                    m["channelName"] = name;
                    v = m;
                }
                e.channelName = name;
                e.videos      = videos;
                e.feedOk      = true;
                e.fetchedMs   = QDateTime::currentMSecsSinceEpoch();
            }
        }
        // On failure: keep any previously cached videos (stale beats empty);
        // fetchedMs stays old so the next load retries this channel.
        if (--m_pendingChannels <= 0) {
            m_pendingChannels = 0;
            finishAggregate();
        }
    });
}

void YouTubeBackend::finishAggregate() {
    const bool    feedWanted     = m_emitFeedWhenDone;
    const bool    channelsWanted = m_emitChannelsWhenDone;
    const QString videosWanted   = m_emitChannelVideosWhenDone;
    m_emitFeedWhenDone     = false;
    m_emitChannelsWhenDone = false;
    m_emitChannelVideosWhenDone.clear();

    bool anyOk = false;
    for (const QString &id : m_channelOrder)
        anyOk = anyOk || m_channels.value(id).feedOk;

    // The tree's waits, answered from the cache once this has returned.
    if (anyOk) {
        m_channelsLoadedMs = QDateTime::currentMSecsSinceEpoch();
        m_channelsFailedMs = 0;
        setProblem(QString());
    } else {
        m_channelsFailedMs = QDateTime::currentMSecsSinceEpoch();
        setProblem(QString::fromLatin1(kSubscriptionsProblem));
    }
    answerLater(std::exchange(m_channelWaits, {}));

    if (!anyOk) {
        emit errorOccurred(QStringLiteral("COULD NOT LOAD SUBSCRIPTIONS\n"
                                          "CHECK YOUR NETWORK CONNECTION"));
        return;
    }

    if (feedWanted)
        emit subscriptionsFeedLoaded(buildFeed());
    if (channelsWanted)
        emit channelsLoaded(buildChannelList());
    if (!videosWanted.isEmpty()) {
        const ChannelEntry entry = m_channels.value(videosWanted);
        if (entry.feedOk)
            emit channelVideosLoaded(videosWanted, entry.videos);
        else
            emit errorOccurred(QStringLiteral("COULD NOT LOAD CHANNEL FEED"));
    }
}

QVariantList YouTubeBackend::buildFeed() const {
    QVariantList all;
    for (const QString &id : m_channelOrder)
        all += m_channels.value(id).videos;
    std::sort(all.begin(), all.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("publishedMs").toLongLong()
             > b.toMap().value("publishedMs").toLongLong();
    });
    return all.mid(0, kMaxFeedItems);
}

QVariantList YouTubeBackend::buildChannelList() const {
    QVariantList channels;
    for (const QString &id : m_channelOrder) {
        const ChannelEntry entry = m_channels.value(id);
        QVariantMap c;
        // Fall back to the raw ID so a channel whose feed failed is still visible
        c["channelId"]  = id;
        c["title"]      = entry.channelName.isEmpty() ? id : entry.channelName;
        c["videoCount"] = entry.videos.size();
        channels << c;
    }
    std::sort(channels.begin(), channels.end(), [](const QVariant &a, const QVariant &b) {
        return QString::compare(a.toMap().value("title").toString(),
                                b.toMap().value("title").toString(),
                                Qt::CaseInsensitive) < 0;
    });
    return channels;
}

// ---------------------------------------------------------------------------
// Playlists file (youtube_playlists.txt)
// Line format: [My Display Name | ] <playlist URL or bare playlist ID>
// ---------------------------------------------------------------------------

// "list=" query param when present, bare token otherwise. A URL without a
// list= param isn't a playlist link — rejected so it can't be fed to yt-dlp
// as something else entirely.
static QString playlistIdFromToken(QString token) {
    const int listPos = token.indexOf(QLatin1String("list="));
    if (listPos >= 0) {
        token = token.mid(listPos + 5);
        const int end = token.indexOf(QRegularExpression(QStringLiteral("[&#?/]")));
        if (end >= 0)
            token = token.left(end);
        return token;
    }
    if (token.contains(QLatin1String("://")))
        return {};
    return token;
}

QList<YouTubeBackend::PlaylistFileRef> YouTubeBackend::readPlaylistEntries(QString *error) const {
    const QString path = m_dataRoot + "/" + kPlaylistsFileName;
    if (!QFile::exists(path)) {
        if (error)
            *error = QStringLiteral("NO PLAYLISTS FILE FOUND\n"
                                    "CREATE YOUTUBE_PLAYLISTS.TXT IN THE DATA DIRECTORY\n"
                                    "WITH ONE PLAYLIST URL PER LINE");
        return {};
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (error)
            *error = QStringLiteral("COULD NOT READ YOUTUBE_PLAYLISTS.TXT");
        return {};
    }
    QList<PlaylistFileRef> refs;
    QStringList seen;
    while (!f.atEnd()) {
        const QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;
        // Split the optional display-name prefix at the last '|' (URLs never
        // contain one, display names conceivably could).
        QString name, token = line;
        const int bar = line.lastIndexOf('|');
        if (bar >= 0) {
            name  = line.left(bar).trimmed();
            token = line.mid(bar + 1).trimmed();
        }
        const QString id = playlistIdFromToken(token);
        if (id.isEmpty() || seen.contains(id))
            continue;
        seen << id;
        refs.append({id, name});
    }
    if (refs.isEmpty() && error)
        *error = QStringLiteral("NO PLAYLISTS FOUND IN YOUTUBE_PLAYLISTS.TXT");
    return refs;
}

QVariantMap YouTubeBackend::check_playlists() {
    QString error;
    const QList<PlaylistFileRef> refs = readPlaylistEntries(&error);
    QVariantMap result;
    result["ok"]            = error.isEmpty();
    result["error"]         = error;
    result["fileExists"]    = QFile::exists(m_dataRoot + "/" + kPlaylistsFileName);
    result["playlistCount"] = refs.size();
    return result;
}

// ---------------------------------------------------------------------------
// Playlist loaders — yt-dlp --flat-playlist subprocesses feeding the same
// cache/queue shape as the RSS channel path. yt-dlp is used (rather than the
// playlist RSS feed) because the feed stops at 15 entries.
// ---------------------------------------------------------------------------

void YouTubeBackend::load_playlists(bool forceRefresh) {
    m_emitPlaylistsWhenDone = true;
    ensurePlaylistsFresh(forceRefresh);
}

void YouTubeBackend::load_playlist_videos(const QString &playlistId, bool forceRefresh) {
    m_emitPlaylistVideosWhenDone = playlistId;
    ensurePlaylistsFresh(forceRefresh);
}

void YouTubeBackend::ensurePlaylistsFresh(bool forceRefresh) {
    if (m_pendingPlaylists > 0)
        return; // refresh already in flight — the emit flags queue on it

    QString error;
    const QList<PlaylistFileRef> refs = readPlaylistEntries(&error);
    if (refs.isEmpty()) {
        m_emitPlaylistsWhenDone = false;
        m_emitPlaylistVideosWhenDone.clear();
        emit errorOccurred(error);
        return;
    }
    m_playlistOrder.clear();
    for (const PlaylistFileRef &ref : refs) {
        m_playlistOrder << ref.id;
        PlaylistEntry &entry = m_playlists[ref.id];
        entry.playlistId = ref.id;
        entry.fileName   = ref.name; // re-read every refresh so file edits apply
    }

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QStringList stale;
    for (const QString &id : m_playlistOrder) {
        const PlaylistEntry &entry = m_playlists.value(id);
        if (forceRefresh || !entry.fetchOk || now - entry.fetchedMs > kCacheTtlMs)
            stale << id;
    }

    if (stale.isEmpty()) {
        finishPlaylistAggregate(); // everything fresh — serve from cache
        return;
    }
    // Resolve the same user-updatable yt-dlp mpv's ytdl_hook will use at
    // playback time (data-dir drop-in → sibling → PATH), so app and mpv agree.
    if (ytdlp::locate(m_dataRoot).isEmpty()) {
        // Nothing can be fetched; report against whatever the cache holds.
        finishPlaylistAggregate();
        return;
    }
    m_pendingPlaylists   = stale.size();
    m_playlistFetchQueue = stale;
    spawnNextPlaylistFetch();
}

void YouTubeBackend::spawnNextPlaylistFetch() {
    const QString bin = ytdlp::locate(m_dataRoot);
    while (m_activePlaylistFetches < kMaxConcurrentPlaylistFetches
           && !m_playlistFetchQueue.isEmpty()) {
        const QString playlistId = m_playlistFetchQueue.takeFirst();
        ++m_activePlaylistFetches;

        auto *proc = new QProcess(this);
        const QStringList args{
            QStringLiteral("--flat-playlist"),
            QStringLiteral("-I"), QStringLiteral("1:%1").arg(kMaxPlaylistItems),
            QStringLiteral("--no-warnings"),
            // One JSON object per entry — robust against '|' etc. in titles
            QStringLiteral("--print"),
            QStringLiteral("%(.{id,title,channel,uploader,playlist_title})j"),
            QStringLiteral("--"),
            QStringLiteral("https://www.youtube.com/playlist?list=") + playlistId,
        };

        auto finish = [this, proc, playlistId]() {
            proc->deleteLater();
            QString      title;
            QVariantList videos;
            const QList<QByteArray> lines = proc->readAllStandardOutput().split('\n');
            for (const QByteArray &line : lines) {
                const QJsonObject obj = QJsonDocument::fromJson(line.trimmed()).object();
                if (obj.isEmpty())
                    continue;
                if (title.isEmpty())
                    title = obj.value(QLatin1String("playlist_title")).toString();
                const QString videoId    = obj.value(QLatin1String("id")).toString();
                const QString videoTitle = obj.value(QLatin1String("title")).toString();
                if (videoId.isEmpty())
                    continue;
                // Tombstones YouTube leaves in place of removed entries
                if (videoTitle == QLatin1String("[Private video]")
                    || videoTitle == QLatin1String("[Deleted video]"))
                    continue;
                QString channel = obj.value(QLatin1String("channel")).toString();
                if (channel.isEmpty())
                    channel = obj.value(QLatin1String("uploader")).toString();
                QVariantMap v;
                v["videoId"]     = videoId;
                v["title"]       = videoTitle;
                v["channelId"]   = QString();
                v["channelName"] = channel;
                // Flat entries carry no publish date; playlist order stands in
                v["publishedAt"] = QString();
                v["publishedMs"] = qint64(0);
                v["url"]         = watchUrlFor(videoId);
                v["isShort"]     = false; // not detectable from flat entries
                videos.append(v);
            }
            // Non-zero exit with parsed entries still counts (partial page
            // failures on huge lists) — same "partial parses kept" stance as RSS.
            const bool ok = proc->exitStatus() == QProcess::NormalExit
                            && (proc->exitCode() == 0 || !videos.isEmpty());
            if (ok) {
                PlaylistEntry &entry = m_playlists[playlistId];
                entry.fetchedTitle = title;
                entry.videos       = videos;
                entry.fetchOk      = true;
                entry.fetchedMs    = QDateTime::currentMSecsSinceEpoch();
            }
            // On failure: keep any previously cached videos (stale beats empty)

            --m_activePlaylistFetches;
            if (--m_pendingPlaylists <= 0) {
                m_pendingPlaylists      = 0;
                m_activePlaylistFetches = 0;
                m_playlistFetchQueue.clear();
                finishPlaylistAggregate();
            } else {
                spawnNextPlaylistFetch();
            }
        };
        connect(proc, &QProcess::finished, this, finish);
        // finished() is never emitted when the binary fails to launch
        connect(proc, &QProcess::errorOccurred, this,
                [finish](QProcess::ProcessError processError) {
                    if (processError == QProcess::FailedToStart)
                        finish();
                });
        QTimer::singleShot(kPlaylistFetchTimeoutMs, proc, [proc]() { proc->kill(); });
        proc->start(bin, args);
    }
}

void YouTubeBackend::finishPlaylistAggregate() {
    const bool    listWanted   = m_emitPlaylistsWhenDone;
    const QString videosWanted = m_emitPlaylistVideosWhenDone;
    m_emitPlaylistsWhenDone = false;
    m_emitPlaylistVideosWhenDone.clear();

    bool anyOk = false;
    for (const QString &id : m_playlistOrder)
        anyOk = anyOk || m_playlists.value(id).fetchOk;

    if (anyOk) {
        m_playlistsLoadedMs = QDateTime::currentMSecsSinceEpoch();
        m_playlistsFailedMs = 0;
        setProblem(QString());
    } else {
        m_playlistsFailedMs = QDateTime::currentMSecsSinceEpoch();
        setProblem(QString::fromLatin1(kPlaylistsProblem));
    }
    // The playlists folder too: its names may have come in with the videos.
    QStringList answered = std::exchange(m_playlistWaits, {});
    if (!answered.contains(QStringLiteral("playlists")))
        answered << QStringLiteral("playlists");
    answerLater(answered);

    if (!anyOk) {
        emit errorOccurred(QStringLiteral("COULD NOT LOAD PLAYLISTS\n"
                                          "CHECK YOUR NETWORK CONNECTION AND THAT\n"
                                          "YT-DLP IS INSTALLED AND UP TO DATE"));
        return;
    }

    if (listWanted)
        emit playlistsLoaded(buildPlaylistList());
    if (!videosWanted.isEmpty()) {
        const PlaylistEntry entry = m_playlists.value(videosWanted);
        if (entry.fetchOk)
            emit playlistVideosLoaded(videosWanted, entry.videos);
        else
            emit errorOccurred(QStringLiteral("COULD NOT LOAD PLAYLIST"));
    }
}

QVariantList YouTubeBackend::buildPlaylistList() const {
    QVariantList playlists;
    for (const QString &id : m_playlistOrder) {
        const PlaylistEntry entry = m_playlists.value(id);
        QVariantMap p;
        p["playlistId"] = id;
        // File-name override wins; fall back to the raw ID so a playlist whose
        // fetch failed is still visible (same choice as buildChannelList)
        p["title"]      = !entry.fileName.isEmpty()     ? entry.fileName
                        : !entry.fetchedTitle.isEmpty() ? entry.fetchedTitle
                                                        : id;
        p["videoCount"] = entry.videos.size();
        playlists << p;
    }
    return playlists; // file order — the user's own curation is the sort
}

// ---------------------------------------------------------------------------
// Playback resolution → yt-dlp format
// ---------------------------------------------------------------------------

QString YouTubeBackend::ytdlFormatForResolution(const QString &resolution) const {
    int height = 480;
    if (resolution == QLatin1String("720p"))
        height = 720;
    else if (resolution == QLatin1String("1080p"))
        height = 1080;
    // H.264 first (RPi hardware decode), then any codec at the cap, then best
    return QStringLiteral("bestvideo[height<=?%1][vcodec^=avc1]+bestaudio/"
                          "bestvideo[height<=?%1]+bestaudio/"
                          "best[height<=?%1]/best")
        .arg(height);
}

// ---------------------------------------------------------------------------
// Watch history (youtube_history.json, keyed by videoId)
// Entry: { pos: <ms>, title, channelName, lastPlayed: <epoch ms> }
// Legacy pos-only entries are tolerated: they resume fine but are skipped by
// the History list (nothing to display) and pruned first (lastPlayed 0).
// ---------------------------------------------------------------------------

QString YouTubeBackend::historyFilePath() const {
    return m_dataRoot + "/youtube_history.json";
}

QVariantMap YouTubeBackend::loadHistory() const {
    QFile file(historyFilePath());
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
}

void YouTubeBackend::saveHistory(const QVariantMap &history) {
    QFile file(historyFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    file.write(QJsonDocument(QJsonObject::fromVariantMap(history)).toJson(QJsonDocument::Compact));
}

QVariantMap YouTubeBackend::getSavedPosition(const QString &videoId) {
    const QVariant val = loadHistory().value(videoId);
    if (!val.isValid())
        return {};
    return val.toMap();
}

void YouTubeBackend::savePosition(const QString &videoId, int positionMs,
                                  const QString &title, const QString &channelName) {
    QVariantMap history = loadHistory();
    QVariantMap entry;
    entry["pos"]         = positionMs;
    entry["title"]       = title;
    entry["channelName"] = channelName;
    entry["lastPlayed"]  = QDateTime::currentMSecsSinceEpoch();
    history[videoId] = entry;

    if (history.size() > kMaxHistoryItems) {
        QStringList keys = history.keys();
        std::sort(keys.begin(), keys.end(), [&history](const QString &a, const QString &b) {
            return history.value(a).toMap().value("lastPlayed").toLongLong()
                 > history.value(b).toMap().value("lastPlayed").toLongLong();
        });
        for (int i = kMaxHistoryItems; i < keys.size(); ++i)
            history.remove(keys[i]);
    }
    saveHistory(history);
}

QVariantList YouTubeBackend::getHistory() const {
    const QVariantMap history = loadHistory();
    QVariantList items;
    for (auto it = history.begin(); it != history.end(); ++it) {
        const QVariantMap entry = it.value().toMap();
        const QString title = entry.value("title").toString();
        if (title.isEmpty())
            continue; // legacy resume-only entry — nothing to display
        QVariantMap v;
        v["videoId"]     = it.key();
        v["title"]       = title;
        v["channelName"] = entry.value("channelName").toString();
        v["lastPlayed"]  = entry.value("lastPlayed").toLongLong();
        v["url"]         = watchUrlFor(it.key());
        items << v;
    }
    std::sort(items.begin(), items.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("lastPlayed").toLongLong()
             > b.toMap().value("lastPlayed").toLongLong();
    });
    return items;
}

void YouTubeBackend::delete_history() {
    QFile::remove(historyFilePath());
}

// ---------------------------------------------------------------------------
// Watch later (youtube_watch_later.json — JSON array, newest-saved first)
// Entry: { videoId, title, channelName, addedMs }
// ---------------------------------------------------------------------------

QString YouTubeBackend::watchLaterFilePath() const {
    return m_dataRoot + "/youtube_watch_later.json";
}

QVariantList YouTubeBackend::loadWatchLater() const {
    QFile file(watchLaterFilePath());
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).array().toVariantList();
}

void YouTubeBackend::saveWatchLater(const QVariantList &list) {
    QFile file(watchLaterFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    file.write(QJsonDocument(QJsonArray::fromVariantList(list)).toJson(QJsonDocument::Compact));
}

QVariantList YouTubeBackend::getWatchLater() const {
    QVariantList items = loadWatchLater();
    for (QVariant &v : items) {
        QVariantMap m = v.toMap();
        m["url"] = watchUrlFor(m.value("videoId").toString());
        v = m;
    }
    return items;
}

bool YouTubeBackend::isInWatchLater(const QString &videoId) const {
    const QVariantList list = loadWatchLater();
    for (const QVariant &v : list) {
        if (v.toMap().value("videoId").toString() == videoId)
            return true;
    }
    return false;
}

void YouTubeBackend::addToWatchLater(const QString &videoId, const QString &title,
                                     const QString &channelName) {
    if (videoId.isEmpty() || isInWatchLater(videoId))
        return;
    QVariantList list = loadWatchLater();
    QVariantMap entry;
    entry["videoId"]     = videoId;
    entry["title"]       = title;
    entry["channelName"] = channelName;
    entry["addedMs"]     = QDateTime::currentMSecsSinceEpoch();
    list.prepend(entry);
    saveWatchLater(list);
}

void YouTubeBackend::removeFromWatchLater(const QString &videoId) {
    QVariantList list = loadWatchLater();
    for (int i = list.size() - 1; i >= 0; --i) {
        if (list[i].toMap().value("videoId").toString() == videoId)
            list.removeAt(i);
    }
    if (list.isEmpty())
        QFile::remove(watchLaterFilePath());
    else
        saveWatchLater(list);
}

void YouTubeBackend::delete_watch_later() {
    QFile::remove(watchLaterFilePath());
}

// ---------------------------------------------------------------------------
// The module's tree (TreeBrowser): every list above as a folder, and search.
// The feeds and playlists come from the same caches the loaders fill; a path
// that has to wait for one is answered (listingReady) once it is in.
// ---------------------------------------------------------------------------

static QVariantMap treeFolder(const QString &name, const QString &path) {
    return { { "name", name }, { "path", path }, { "isFolder", true } };
}

static QVariantMap treeAction(const QString &name, const QString &kind, const QString &path) {
    return { { "name", name }, { "path", path }, { "isFolder", false }, { "kind", kind } };
}

QVariant YouTubeBackend::listing(const QString &path, bool preview) {
    if (path == QLatin1String("home")) {
        // A visit starts clean: a source that is still failing says so
        // again when it is asked.
        setProblem(QString());
        QVariantList entries{ treeAction(QStringLiteral("Search"), QStringLiteral("search"),
                                         QStringLiteral("home/search")) };
        if (!readSubscriptionIds().isEmpty())
            entries << treeFolder(QStringLiteral("Subscriptions"), QStringLiteral("subscriptions"))
                    << treeFolder(QStringLiteral("Channels"), QStringLiteral("channels"));
        if (!readPlaylistEntries().isEmpty())
            entries << treeFolder(QStringLiteral("Playlists"), QStringLiteral("playlists"));
        if (!loadWatchLater().isEmpty())
            entries << treeFolder(QStringLiteral("Watch Later"), QStringLiteral("watchlater"));
        if (!getHistory().isEmpty())
            entries << treeFolder(QStringLiteral("History"), QStringLiteral("history"));
        return entries;
    }
    if (path == QLatin1String("watchlater"))
        return videoEntries(getWatchLater());
    if (path == QLatin1String("history"))
        return videoEntries(getHistory());
    if (path == QLatin1String("subscriptions") || path == QLatin1String("channels")
        || path.startsWith(QLatin1String("channel/")))
        return channelListing(path);
    if (path == QLatin1String("playlists") || path.startsWith(QLatin1String("playlist/")))
        return playlistListing(path, preview);
    if (path.startsWith(QLatin1String("search/")))
        return searchListing(path);
    return QVariantList();
}

QVariant YouTubeBackend::channelListing(const QString &path) {
    const QStringList ids = readSubscriptionIds();
    if (ids.isEmpty())
        return QVariantList();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_channelsFailedMs < kRetryAfterMs) {
        setProblem(QString::fromLatin1(kSubscriptionsProblem));
        return QVariantList();
    }
    // Fresh as a whole: a channel whose own feed failed stays empty until the
    // next load, rather than having the tree ask again and again.
    const bool fresh = m_channelsLoadedMs > 0 && now - m_channelsLoadedMs < kCacheTtlMs
                       && ids == m_channelOrder;
    if (!fresh) {
        if (!m_channelWaits.contains(path))
            m_channelWaits << path;
        ensureFresh(false);
        return QVariant();
    }
    if (path == QLatin1String("subscriptions"))
        return videoEntries(buildFeed());
    if (path == QLatin1String("channels")) {
        QVariantList entries;
        for (const QVariant &v : buildChannelList()) {
            const QVariantMap channel = v.toMap();
            entries << treeFolder(channel.value("title").toString(),
                                  QStringLiteral("channel/") + channel.value("channelId").toString());
        }
        return entries;
    }
    return videoEntries(m_channels.value(path.section(QLatin1Char('/'), 1)).videos);
}

QVariant YouTubeBackend::playlistListing(const QString &path, bool preview) {
    const QList<PlaylistFileRef> refs = readPlaylistEntries();
    if (refs.isEmpty())
        return QVariantList();
    if (path == QLatin1String("playlists")) {
        // Straight from the file: named as it names them, or as yt-dlp last
        // reported. Their videos are fetched once one is opened.
        QVariantList entries;
        for (const PlaylistFileRef &ref : refs) {
            const QString fetched = m_playlists.value(ref.id).fetchedTitle;
            entries << treeFolder(!ref.name.isEmpty() ? ref.name : !fetched.isEmpty() ? fetched : ref.id,
                                  QStringLiteral("playlist/") + ref.id);
        }
        return entries;
    }
    QStringList ids;
    for (const PlaylistFileRef &ref : refs)
        ids << ref.id;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const bool fresh = m_playlistsLoadedMs > 0 && now - m_playlistsLoadedMs < kCacheTtlMs
                       && ids == m_playlistOrder;
    if (fresh)
        return videoEntries(m_playlists.value(path.section(QLatin1Char('/'), 1)).videos);
    if (now - m_playlistsFailedMs < kRetryAfterMs) {
        setProblem(QString::fromLatin1(kPlaylistsProblem));
        return QVariantList();
    }
    if (preview)
        return QVariant();
    if (!m_playlistWaits.contains(path))
        m_playlistWaits << path;
    ensurePlaylistsFresh(false);
    return QVariant();
}

QVariant YouTubeBackend::searchListing(const QString &path) {
    const Search search = m_searches.value(path);
    if (search.requested > 0) {
        QVariantList entries = videoEntries(search.videos);
        if (!search.exhausted)
            entries << treeAction(QStringLiteral("More…"), QStringLiteral("more"),
                                  path + QStringLiteral("#more"));
        return entries;
    }
    if (QDateTime::currentMSecsSinceEpoch() - search.failedMs < kRetryAfterMs) {
        setProblem(QString::fromLatin1(ytdlp::locate(m_dataRoot).isEmpty() ? kNoYtDlpProblem
                                                                           : kSearchProblem));
        return QVariantList();
    }
    searchPage(path);
    return QVariant();
}

void YouTubeBackend::loadMore(const QString &path) {
    if (m_searches.value(path).requested > 0)
        searchPage(path);
}

// One page of matches, through the same yt-dlp mpv plays them with.
void YouTubeBackend::searchPage(const QString &path) {
    Search &search = m_searches[path];
    if (search.loading || search.exhausted)
        return;
    const QString bin = ytdlp::locate(m_dataRoot);
    if (bin.isEmpty()) {
        search.failedMs = QDateTime::currentMSecsSinceEpoch();
        setProblem(QString::fromLatin1(kNoYtDlpProblem));
        answerLater({ path });
        return;
    }
    search.loading = true;
    const int first = search.requested + 1;
    const int last  = search.requested + kSearchPageSize;
    const QStringList args{
        QStringLiteral("--flat-playlist"),
        QStringLiteral("--no-warnings"),
        QStringLiteral("-I"), QStringLiteral("%1:%2").arg(first).arg(last),
        QStringLiteral("--print"),
        QStringLiteral("%(.{id,title,channel,uploader,url,live_status})j"),
        QStringLiteral("--"),
        QStringLiteral("ytsearch%1:%2").arg(last).arg(path.section(QLatin1Char('/'), 1)),
    };

    auto *proc = new QProcess(this);
    auto finish = [this, proc, path, last]() {
        proc->deleteLater();
        int found = 0;
        QVariantList videos;
        const QList<QByteArray> lines = proc->readAllStandardOutput().split('\n');
        for (const QByteArray &line : lines) {
            const QJsonObject obj = QJsonDocument::fromJson(line.trimmed()).object();
            const QString videoId = obj.value(QLatin1String("id")).toString();
            if (videoId.isEmpty())
                continue;
            ++found;
            // Announced, not on yet: nothing to play.
            if (obj.value(QLatin1String("live_status")).toString() == QLatin1String("is_upcoming"))
                continue;
            QString channel = obj.value(QLatin1String("channel")).toString();
            if (channel.isEmpty())
                channel = obj.value(QLatin1String("uploader")).toString();
            QVariantMap v;
            v["videoId"]     = videoId;
            v["title"]       = obj.value(QLatin1String("title")).toString();
            v["channelId"]   = QString();
            v["channelName"] = channel;
            v["publishedAt"] = QString();
            v["publishedMs"] = qint64(0);
            v["url"]         = watchUrlFor(videoId);
            v["isShort"]     = obj.value(QLatin1String("url")).toString().contains(QLatin1String("/shorts/"));
            videos.append(v);
        }
        Search &search = m_searches[path];
        search.loading = false;
        if (proc->exitStatus() == QProcess::NormalExit && (proc->exitCode() == 0 || found > 0)) {
            search.videos   += videos;
            search.requested = last;
            // Fewer than asked for: YouTube has no more.
            search.exhausted = found < kSearchPageSize;
            setProblem(QString());
        } else {
            search.failedMs = QDateTime::currentMSecsSinceEpoch();
            setProblem(QString::fromLatin1(kSearchProblem));
        }
        emit listingReady(path);
    };
    connect(proc, &QProcess::finished, this, finish);
    // finished() is never emitted when the binary fails to launch
    connect(proc, &QProcess::errorOccurred, this,
            [finish](QProcess::ProcessError processError) {
                if (processError == QProcess::FailedToStart)
                    finish();
            });
    QTimer::singleShot(kPlaylistFetchTimeoutMs, proc, [proc]() { proc->kill(); });
    proc->start(bin, args);
}

QVariantList YouTubeBackend::videoEntries(const QVariantList &videos) const {
    QVariantList entries;
    for (const QVariant &v : videos) {
        QVariantMap video = v.toMap();
        video["name"]     = video.value("title");
        video["path"]     = QStringLiteral("video/") + video.value("videoId").toString();
        video["isFolder"] = false;
        video["kind"]     = QStringLiteral("video");
        entries << video;
    }
    return entries;
}

// After the caller has returned: a tree asking listing() must never be
// refreshed from inside that call.
void YouTubeBackend::answerLater(const QStringList &paths) {
    if (paths.isEmpty())
        return;
    QTimer::singleShot(0, this, [this, paths]() {
        for (const QString &path : paths)
            emit listingReady(path);
    });
}

void YouTubeBackend::setProblem(const QString &problem) {
    if (problem == m_problem)
        return;
    m_problem = problem;
    emit problemChanged();
}

// ---------------------------------------------------------------------------
// A video's info screen: what the list knows at once, then what yt-dlp adds.
// ---------------------------------------------------------------------------

QVariantMap YouTubeBackend::detailsOf(const QVariantMap &video, bool complete) const {
    const QVariantMap extra = m_details.value(video.value("videoId").toString());
    const auto pick = [&video, &extra](const char *key) {
        const QString value = extra.value(QLatin1String(key)).toString();
        return value.isEmpty() ? video.value(QLatin1String(key)).toString() : value;
    };
    // YYYYMMDD from yt-dlp, an ISO date from the feed.
    QString date = extra.value("upload_date").toString();
    if (date.size() == 8)
        date = date.left(4) + QLatin1Char('-') + date.mid(4, 2) + QLatin1Char('-') + date.mid(6, 2);
    if (date.isEmpty())
        date = video.value("publishedAt").toString().left(10);
    QString channel = pick("channel");
    if (channel.isEmpty())
        channel = video.value("channelName").toString();

    QVariantMap details;
    details["title"] = pick("title");
    QStringList facts;
    if (!channel.isEmpty())
        facts << channel;
    if (!date.isEmpty())
        facts << date;
    details["facts"] = facts.join(QStringLiteral(" - "));
    details["summary"] = pick("description");

    QVariantList rows;
    const auto row = [&rows](const QString &label, const QString &value) {
        if (!value.isEmpty())
            rows << QVariantMap{ { "label", label }, { "value", value } };
    };
    row(QStringLiteral("Channel"), channel);
    row(QStringLiteral("Date"), date);
    row(QStringLiteral("Length"), extra.value("duration_string").toString());
    const qint64 views = extra.value("view_count").toLongLong();
    if (views > 0)
        row(QStringLiteral("Views"), QLocale(QLocale::English).toString(views));
    details["rows"] = rows;
    details["complete"] = complete;
    return details;
}

void YouTubeBackend::loadDetails(const QVariantMap &video) {
    const QString path = video.value("path").toString();
    const QString videoId = video.value("videoId").toString();
    const bool known = m_details.contains(videoId);
    const QVariantMap now = detailsOf(video, known || ytdlp::locate(m_dataRoot).isEmpty());
    // Never from inside the call: the view showing them is still opening.
    QTimer::singleShot(0, this, [this, path, now]() { emit detailsReady(path, now); });
    if (!known && !now.value("complete").toBool())
        fetchDetails(video);
}

// One video's metadata from yt-dlp, a few seconds' work on a Pi: one fetch at
// a time, and only the last video asked for while one runs.
void YouTubeBackend::fetchDetails(const QVariantMap &video) {
    if (m_fetchingDetails) {
        m_detailsNext = video;
        return;
    }
    m_fetchingDetails = true;
    auto *proc = new QProcess(this);
    const QStringList args{
        QStringLiteral("--skip-download"),
        QStringLiteral("--no-warnings"),
        QStringLiteral("--no-playlist"),
        QStringLiteral("--print"),
        QStringLiteral("%(.{title,channel,uploader,upload_date,duration_string,view_count,description})j"),
        QStringLiteral("--"),
        video.value("url").toString(),
    };
    auto finish = [this, proc, video]() {
        proc->deleteLater();
        m_fetchingDetails = false;
        const QJsonObject obj = QJsonDocument::fromJson(
            proc->readAllStandardOutput().trimmed().split('\n').value(0)).object();
        QVariantMap extra = obj.toVariantMap();
        if (extra.value("channel").toString().isEmpty())
            extra["channel"] = extra.value("uploader");
        const QString videoId = video.value("videoId").toString();
        if (!obj.isEmpty())
            m_details.insert(videoId, extra);
        // Complete either way: what yt-dlp couldn't say, the screen does without.
        emit detailsReady(video.value("path").toString(), detailsOf(video, true));
        if (!m_detailsNext.isEmpty()) {
            const QVariantMap next = std::exchange(m_detailsNext, {});
            if (!m_details.contains(next.value("videoId").toString()))
                fetchDetails(next);
        }
    };
    connect(proc, &QProcess::finished, this, finish);
    connect(proc, &QProcess::errorOccurred, this,
            [finish](QProcess::ProcessError processError) {
                if (processError == QProcess::FailedToStart)
                    finish();
            });
    QTimer::singleShot(kPlaylistFetchTimeoutMs, proc, [proc]() { proc->kill(); });
    proc->start(ytdlp::locate(m_dataRoot), args);
}
