#include "WebPlayerBackend.h"
#include "../scripts/ScriptLauncher.h"
#include "../../util/DisplayHandoff.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QDebug>

namespace {

// The browsers web-player.sh looks for, in its order. Keep the two in step.
const char *const kBrowsers[] = { "chromium", "chromium-browser",
                                  "google-chrome-stable", "google-chrome" };

bool haveBrowser() {
#ifdef Q_OS_MACOS
    // web-player.sh falls back to Safari, which every Mac has.
    return true;
#else
    for (const char *name : kBrowsers) {
        if (!QStandardPaths::findExecutable(QLatin1String(name)).isEmpty())
            return true;
    }
    return false;
#endif
}

} // namespace

WebPlayerBackend::WebPlayerBackend(const Service &service,
                                   const QString &appRoot, const QString &dataRoot,
                                   DisplayHandoff *handoff, QObject *parent)
    : QObject(parent), m_service(service.id), m_url(service.homeUrl),
      m_appRoot(appRoot), m_dataRoot(dataRoot)
{
    m_catalog = new TmdbCatalog(m_dataRoot, service.catalog, this);
    // The catalogue's settings as they stand: AppCore isn't available to
    // backends at construction time, so straight from config.json, as the
    // other backends do.
    QFile f(m_dataRoot + QStringLiteral("/config.json"));
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonObject settings = QJsonDocument::fromJson(f.readAll()).object()
            .value(QStringLiteral("modules")).toObject().value(moduleId()).toObject();
        for (const QString &key : { QStringLiteral("region"), QStringLiteral("catalog_language") })
            applySetting(key, settings.value(key).toVariant());
    }

    m_launcher = new ScriptLauncher(m_appRoot, m_dataRoot, handoff, this);
    m_launcher->setHandoffOwner(m_service);
    connect(m_launcher, &ScriptLauncher::runningChanged,
            this, &WebPlayerBackend::runningChanged);
    connect(m_launcher, &ScriptLauncher::finished,
            this, &WebPlayerBackend::finished);
}

bool WebPlayerBackend::running() const {
    return m_launcher->isBusy();
}

QString WebPlayerBackend::browserProfile() const {
    // Where web-player.sh keeps the browser's profile, and so the sign-in.
    return m_dataRoot + QLatin1Char('/') + m_service + QStringLiteral("/browser");
}

void WebPlayerBackend::onSettingChanged(const QString &moduleId, const QString &key,
                                        const QVariant &value) {
    if (moduleId == this->moduleId())
        applySetting(key, value);
}

void WebPlayerBackend::applySetting(const QString &key, const QVariant &value) {
    if (key == QLatin1String("region")) {
        m_catalog->setRegion(value.toString());
    } else if (key == QLatin1String("catalog_language")) {
        const QString language = value.toString();
        if (!language.isEmpty())
            m_catalog->setLanguage(language == QLatin1String("Turkish") ? QStringLiteral("tr-TR")
                                                                        : QStringLiteral("en-US"));
    }
}

bool WebPlayerBackend::launch(const QString &url) {
    m_lastError.clear();

    const QString script = m_appRoot + QStringLiteral("/scripts/web-player.sh");
    if (!QFileInfo::exists(script)) {
        m_lastError = QStringLiteral("web-player.sh is missing from the app");
        return false;
    }
    if (!haveBrowser()) {
        m_lastError = QStringLiteral("Chromium is not installed");
        return false;
    }
    // Without a desktop there is nothing for a browser to open a window on;
    // cage gives it a screen of its own.
    if (DisplayHandoff::isHeadless()
        && QStandardPaths::findExecutable(QStringLiteral("cage")).isEmpty()) {
        m_lastError = QStringLiteral("cage is not installed");
        return false;
    }

    ScriptEntry entry;
    entry.path        = script;
    entry.basename    = QStringLiteral("web-player.sh");
    entry.meta.name   = m_service;
    entry.meta.mode   = QStringLiteral("takeover");
    // The browser is a family of processes; the screen comes back once all
    // of them have gone.
    entry.meta.wait   = QStringLiteral("pgroup");
    entry.meta.args   = QStringLiteral("\"%1\" \"%2\"").arg(m_service, url.isEmpty() ? m_url : url);

    QString error;
    if (!m_launcher->start(entry, &error)) {
        m_lastError = error;
        return false;
    }
    return true;
}

QString WebPlayerBackend::output() const {
    return m_launcher->outputText();
}

void WebPlayerBackend::close() {
    if (m_launcher->isBusy())
        m_launcher->requestStop();
}

void WebPlayerBackend::signOut() {
    if (m_launcher->isBusy()) {
        qWarning("[WebPlayer] Not signing out of %s while the browser is open",
                 qPrintable(m_service));
        return;
    }
    if (QDir(browserProfile()).removeRecursively())
        qInfo("[WebPlayer] Signed out of %s: browser profile removed", qPrintable(m_service));
}
