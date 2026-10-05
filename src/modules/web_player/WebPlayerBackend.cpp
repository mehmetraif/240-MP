#include "WebPlayerBackend.h"
#include "../scripts/ScriptLauncher.h"
#include "../../util/DisplayHandoff.h"
#include <QDir>
#include <QFileInfo>
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

WebPlayerBackend::WebPlayerBackend(const QString &service, const QString &url,
                                   const QString &appRoot, const QString &dataRoot,
                                   DisplayHandoff *handoff, QObject *parent)
    : QObject(parent), m_service(service), m_url(url),
      m_appRoot(appRoot), m_dataRoot(dataRoot)
{
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

bool WebPlayerBackend::launch() {
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
    entry.meta.args   = QStringLiteral("\"%1\" \"%2\"").arg(m_service, m_url);

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
