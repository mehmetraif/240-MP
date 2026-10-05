#include "TmdbCatalog.h"
#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QDebug>
#include <memory>
#include <utility>

namespace {

// Wikimedia asks every client to say who it is.
const char *const kUserAgent = "240-MP (https://github.com/anthonycaccese/240-MP)";
constexpr int kTimeoutMs = 12000;
// A list that failed is shown empty for this long before it is asked for again,
// so a tree refreshing on the failure can't loop on it.
constexpr qint64 kRetryAfterMs = 15000;

QVariantMap folder(const QString &name, const QString &path) {
    return { { "name", name }, { "path", path }, { "isFolder", true } };
}

QVariantMap action(const QString &name, const QString &kind, const QString &path) {
    return { { "name", name }, { "path", path }, { "isFolder", false }, { "kind", kind } };
}

QString encoded(const QList<QPair<QString, QString>> &query) {
    QStringList pairs;
    for (const auto &kv : query)
        pairs << kv.first + QLatin1Char('=') + QString::fromLatin1(QUrl::toPercentEncoding(kv.second));
    return pairs.join(QLatin1Char('&'));
}

} // namespace

TmdbCatalog::TmdbCatalog(const QString &dataRoot, const Service &service, QObject *parent)
    : QObject(parent), m_dataRoot(dataRoot), m_service(service)
{
    // Overridable so tests can stand a local server in for TMDB and Wikidata.
    m_tmdbUrl = qEnvironmentVariable("MP240_TMDB_URL", QStringLiteral("https://api.themoviedb.org/3"));
    m_wikidataUrl = qEnvironmentVariable("MP240_WIKIDATA_URL",
                                         QStringLiteral("https://query.wikidata.org/sparql"));
    m_nam.setTransferTimeout(kTimeoutMs);
}

void TmdbCatalog::setRegion(const QString &region) {
    if (region.isEmpty() || region == m_region) return;
    m_region = region;
    forget();
}

void TmdbCatalog::setLanguage(const QString &language) {
    if (language.isEmpty() || language == m_language) return;
    m_language = language;
    forget();
}

void TmdbCatalog::forget() {
    ++m_generation;
    m_providerId = 0;
    m_providerLookup = false;
    m_waitingForProvider.clear();
    m_genres.clear();
    m_genresLoading.clear();
    m_lists.clear();
    m_searches.clear();
    m_searching.clear();
    m_failedAt.clear();
}

QString TmdbCatalog::apiKey() const {
    QFile f(m_dataRoot + QStringLiteral("/tmdb_api_key.txt"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    for (const QByteArray &line : f.readAll().split('\n')) {
        const QString key = QString::fromUtf8(line).trimmed();
        if (!key.isEmpty() && !key.startsWith(QLatin1Char('#')))
            return key;
    }
    return {};
}

void TmdbCatalog::setProblem(const QString &problem) {
    if (problem == m_problem) return;
    m_problem = problem;
    emit problemChanged();
}

bool TmdbCatalog::failedRecently(const QString &path) const {
    const qint64 at = m_failedAt.value(path, 0);
    return at > 0 && QDateTime::currentMSecsSinceEpoch() - at < kRetryAfterMs;
}

QVariant TmdbCatalog::listing(const QString &path, bool preview) {
    Q_UNUSED(preview)
    if (path == QLatin1String("home")) {
        // A visit starts clean: what still stands in the way says so again
        // when the entries under it are asked for.
        setProblem(QString());
        return QVariantList{
            action(QStringLiteral("Search"), QStringLiteral("search"), QStringLiteral("home/search")),
            folder(QStringLiteral("Movies"), QStringLiteral("movie")),
            folder(QStringLiteral("Series"), QStringLiteral("tv")),
            action(m_service.homeLabel, QStringLiteral("home"), QStringLiteral("home/site")),
        };
    }
    if (apiKey().isEmpty()) {
        setProblem(QStringLiteral("No TMDB API key: put one in tmdb_api_key.txt in the data folder"
                                  " (free from themoviedb.org, Settings, API)"));
        return QVariantList();
    }
    if (failedRecently(path)) {
        setProblem(m_failure);
        return QVariantList();
    }

    const QString head = path.section(QLatin1Char('/'), 0, 0);
    if (path == QLatin1String("movie") || path == QLatin1String("tv")) {
        if (m_genres.contains(path))
            return m_genres.value(path);
        fetchGenres(path);
        return QVariant();
    }
    if (head == QLatin1String("search")) {
        if (m_searches.contains(path))
            return m_searches.value(path);
        search(path, path.section(QLatin1Char('/'), 1));
        return QVariant();
    }
    if ((head == QLatin1String("movie") || head == QLatin1String("tv")) && path.contains(QLatin1Char('/'))) {
        const TitleList list = m_lists.value(path);
        if (list.pages > 0) {
            QVariantList entries = list.titles;
            if (list.pages < list.totalPages)
                entries.append(action(QStringLiteral("More…"), QStringLiteral("more"),
                                      path + QStringLiteral("#more")));
            return entries;
        }
        fetchPage(path);
        return QVariant();
    }
    return QVariantList();
}

void TmdbCatalog::loadMore(const QString &path) {
    const TitleList list = m_lists.value(path);
    if (list.pages > 0 && list.pages < list.totalPages)
        fetchPage(path);
}

void TmdbCatalog::get(const QString &endpoint, QList<QPair<QString, QString>> query,
                      std::function<void(const QVariantMap &)> done) {
    const QString key = apiKey();
    QNetworkRequest request;
    // A v4 read access token is a JWT; a v3 key goes in the query.
    if (key.startsWith(QLatin1String("eyJ")))
        request.setRawHeader("Authorization", "Bearer " + key.toUtf8());
    else
        query.append({ QStringLiteral("api_key"), key });
    request.setUrl(QUrl(m_tmdbUrl + endpoint + QLatin1Char('?') + encoded(query)));
    request.setRawHeader("Accept", "application/json");
    request.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kUserAgent));

    QNetworkReply *reply = m_nam.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, done, generation = m_generation]() {
        reply->deleteLater();
        // Asked for another region or language than the one now set.
        if (generation != m_generation)
            return;
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status == 401) {
            m_failure = QStringLiteral("TMDB turned the API key down: check tmdb_api_key.txt");
            setProblem(m_failure);
            done({});
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qWarning("[TMDB] %s: %s", qPrintable(reply->url().path()),
                     qPrintable(reply->errorString()));
            m_failure = QStringLiteral("Could not reach TMDB: check the network");
            setProblem(m_failure);
            done({});
            return;
        }
        setProblem(QString());
        done(QJsonDocument::fromJson(reply->readAll()).object().toVariantMap());
    });
}

void TmdbCatalog::withProvider(std::function<void()> then) {
    if (m_providerId > 0) {
        then();
        return;
    }
    m_waitingForProvider.append(std::move(then));
    if (m_providerLookup)
        return;
    m_providerLookup = true;
    get(QStringLiteral("/watch/providers/movie"),
        { { QStringLiteral("watch_region"), m_region }, { QStringLiteral("language"), m_language } },
        [this](const QVariantMap &json) {
            m_providerLookup = false;
            int id = 0;
            for (const QVariant &v : json.value(QStringLiteral("results")).toList()) {
                const QVariantMap provider = v.toMap();
                if (provider.value(QStringLiteral("provider_name")).toString()
                        .compare(m_service.providerName, Qt::CaseInsensitive) == 0) {
                    id = provider.value(QStringLiteral("provider_id")).toInt();
                    break;
                }
            }
            m_providerId = id > 0 ? id : m_service.fallbackProviderId;
            const auto waiting = std::exchange(m_waitingForProvider, {});
            for (const auto &f : waiting)
                f();
        });
}

void TmdbCatalog::fetchGenres(const QString &type) {
    if (m_genresLoading.contains(type))
        return;
    m_genresLoading.append(type);
    get(QStringLiteral("/genre/%1/list").arg(type), { { QStringLiteral("language"), m_language } },
        [this, type](const QVariantMap &json) {
            m_genresLoading.removeAll(type);
            if (json.isEmpty()) {
                m_failedAt.insert(type, QDateTime::currentMSecsSinceEpoch());
            } else {
                QVariantList entries{ folder(QStringLiteral("Popular"), type + QStringLiteral("/popular")) };
                for (const QVariant &v : json.value(QStringLiteral("genres")).toList()) {
                    const QVariantMap genre = v.toMap();
                    entries.append(folder(genre.value(QStringLiteral("name")).toString(),
                                          QStringLiteral("%1/genre/%2").arg(type)
                                              .arg(genre.value(QStringLiteral("id")).toInt())));
                }
                m_genres.insert(type, entries);
            }
            emit listingReady(type);
        });
}

void TmdbCatalog::fetchPage(const QString &path) {
    if (m_lists[path].loading)
        return;
    m_lists[path].loading = true;
    withProvider([this, path]() {
        const QString type = path.section(QLatin1Char('/'), 0, 0);
        QList<QPair<QString, QString>> query{
            { QStringLiteral("language"), m_language },
            { QStringLiteral("watch_region"), m_region },
            { QStringLiteral("with_watch_providers"), QString::number(m_providerId) },
            // On the subscription, not to rent or buy.
            { QStringLiteral("with_watch_monetization_types"), QStringLiteral("flatrate") },
            { QStringLiteral("sort_by"), QStringLiteral("popularity.desc") },
            { QStringLiteral("page"), QString::number(m_lists.value(path).pages + 1) },
        };
        if (path.section(QLatin1Char('/'), 1, 1) == QLatin1String("genre"))
            query.append({ QStringLiteral("with_genres"), path.section(QLatin1Char('/'), 2, 2) });
        get(QStringLiteral("/discover/") + type, query, [this, path, type](const QVariantMap &json) {
            TitleList &list = m_lists[path];
            list.loading = false;
            if (json.isEmpty()) {
                if (list.pages == 0)
                    m_failedAt.insert(path, QDateTime::currentMSecsSinceEpoch());
            } else {
                for (const QVariant &r : json.value(QStringLiteral("results")).toList())
                    list.titles.append(titleEntry(r.toMap(), type));
                list.pages = json.value(QStringLiteral("page")).toInt();
                // TMDB serves no page past 500.
                list.totalPages = qMin(json.value(QStringLiteral("total_pages")).toInt(), 500);
            }
            emit listingReady(path);
        });
    });
}

void TmdbCatalog::search(const QString &path, const QString &words) {
    if (m_searching.contains(path))
        return;
    m_searching.append(path);
    withProvider([this, path, words]() {
        get(QStringLiteral("/search/multi"),
            { { QStringLiteral("query"), words }, { QStringLiteral("language"), m_language },
              { QStringLiteral("include_adult"), QStringLiteral("false") } },
            [this, path](const QVariantMap &json) {
                if (json.isEmpty()) {
                    // Failed, not found nothing: asked again after a while.
                    m_searching.removeAll(path);
                    m_failedAt.insert(path, QDateTime::currentMSecsSinceEpoch());
                    emit listingReady(path);
                    return;
                }
                QVariantList candidates;
                for (const QVariant &v : json.value(QStringLiteral("results")).toList()) {
                    const QVariantMap r = v.toMap();
                    const QString type = r.value(QStringLiteral("media_type")).toString();
                    if (type == QLatin1String("movie") || type == QLatin1String("tv"))
                        candidates.append(titleEntry(r, type));
                }
                const auto finish = [this, path](const QVariantList &titles) {
                    m_searches.insert(path, titles);
                    m_searching.removeAll(path);
                    emit listingReady(path);
                };
                if (candidates.isEmpty()) {
                    finish({});
                    return;
                }
                // Keep the matches the service carries here, in TMDB's order.
                auto carried = std::make_shared<QVector<bool>>(candidates.size(), false);
                auto pending = std::make_shared<int>(candidates.size());
                for (int i = 0; i < candidates.size(); ++i) {
                    const QVariantMap c = candidates.at(i).toMap();
                    get(QStringLiteral("/%1/%2/watch/providers")
                            .arg(c.value(QStringLiteral("mediaType")).toString())
                            .arg(c.value(QStringLiteral("tmdbId")).toInt()),
                        {},
                        [this, candidates, carried, pending, finish, i](const QVariantMap &providers) {
                            const QVariantMap here = providers.value(QStringLiteral("results")).toMap()
                                                         .value(m_region).toMap();
                            for (const QVariant &p : here.value(QStringLiteral("flatrate")).toList()) {
                                if (p.toMap().value(QStringLiteral("provider_id")).toInt() == m_providerId)
                                    (*carried)[i] = true;
                            }
                            if (--*pending > 0)
                                return;
                            QVariantList titles;
                            for (int k = 0; k < candidates.size(); ++k) {
                                if ((*carried)[k])
                                    titles.append(candidates.at(k));
                            }
                            finish(titles);
                        });
                }
            });
    });
}

QVariantMap TmdbCatalog::titleEntry(const QVariantMap &result, const QString &type) const {
    const bool movie = type == QLatin1String("movie");
    const QString title = result.value(movie ? QStringLiteral("title") : QStringLiteral("name")).toString();
    const QString year = result.value(movie ? QStringLiteral("release_date")
                                            : QStringLiteral("first_air_date")).toString().left(4);
    const int id = result.value(QStringLiteral("id")).toInt();
    return {
        { "name", year.isEmpty() ? title : QStringLiteral("%1 (%2)").arg(title, year) },
        { "path", QStringLiteral("title/%1/%2").arg(type).arg(id) },
        { "isFolder", false },
        { "kind", QStringLiteral("title") },
        { "title", title },
        { "mediaType", type },
        { "tmdbId", id },
    };
}

void TmdbCatalog::resolveTitleUrl(const QVariantMap &title) {
    const QString path = title.value(QStringLiteral("path")).toString();
    const QString name = title.value(QStringLiteral("title")).toString();
    const QString fallback = m_service.searchUrl.arg(QString::fromLatin1(QUrl::toPercentEncoding(name)));
    const int id = title.value(QStringLiteral("tmdbId")).toInt();
    if (id <= 0 || m_service.wikidataProperty.isEmpty()) {
        emit titleUrlReady(path, fallback);
        return;
    }
    // Wikidata keeps both TMDB's id and the service's for many titles.
    const QString tmdbProperty = title.value(QStringLiteral("mediaType")).toString() == QLatin1String("tv")
                                     ? QStringLiteral("P4983") : QStringLiteral("P4947");
    const QString sparql = QStringLiteral("SELECT ?id WHERE { ?item wdt:%1 \"%2\" ; wdt:%3 ?id } LIMIT 1")
                               .arg(tmdbProperty).arg(id).arg(m_service.wikidataProperty);
    QNetworkRequest request(QUrl(m_wikidataUrl + QLatin1Char('?')
                                 + encoded({ { QStringLiteral("format"), QStringLiteral("json") },
                                             { QStringLiteral("query"), sparql } })));
    request.setRawHeader("Accept", "application/sparql-results+json");
    request.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kUserAgent));
    QNetworkReply *reply = m_nam.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, path, fallback]() {
        reply->deleteLater();
        const QJsonArray rows = QJsonDocument::fromJson(reply->readAll()).object()
                                    .value(QStringLiteral("results")).toObject()
                                    .value(QStringLiteral("bindings")).toArray();
        const QString serviceId = rows.isEmpty() ? QString()
            : rows.first().toObject().value(QStringLiteral("id")).toObject()
                  .value(QStringLiteral("value")).toString();
        emit titleUrlReady(path, serviceId.isEmpty() ? fallback : m_service.titleUrl.arg(serviceId));
    });
}
