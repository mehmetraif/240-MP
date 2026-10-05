#include "NetflixBackend.h"
#include "../scripts/ScriptLauncher.h"
#include "../../util/DisplayHandoff.h"
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDebug>

namespace {

// The browsers netflix.sh looks for, in its order. Keep the two in step.
const char *const kBrowsers[] = { "chromium", "chromium-browser",
                                  "google-chrome-stable", "google-chrome" };

bool haveBrowser() {
#ifdef Q_OS_MACOS
    // netflix.sh falls back to Safari, which every Mac has.
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

NetflixBackend::NetflixBackend(const QString &appRoot, const QString &dataRoot,
                               DisplayHandoff *handoff, QObject *parent)
    : QObject(parent), m_appRoot(appRoot), m_dataRoot(dataRoot)
{
    m_launcher = new ScriptLauncher(m_appRoot, m_dataRoot, handoff, this);
    m_launcher->setHandoffOwner(QStringLiteral("netflix"));
    connect(m_launcher, &ScriptLauncher::runningChanged,
            this, &NetflixBackend::runningChanged);
    connect(m_launcher, &ScriptLauncher::finished,
            this, &NetflixBackend::finished);
}

bool NetflixBackend::running() const {
    return m_launcher->isBusy();
}

QString NetflixBackend::browserProfile() const {
    // Where netflix.sh keeps the browser's profile, and so the sign-in.
    return m_dataRoot + QStringLiteral("/netflix/browser");
}

bool NetflixBackend::launch() {
    m_lastError.clear();

    const QString script = m_appRoot + QStringLiteral("/modules/netflix/netflix.sh");
    if (!QFileInfo::exists(script)) {
        m_lastError = QStringLiteral("netflix.sh is missing from the app");
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
    entry.basename    = QStringLiteral("netflix.sh");
    entry.meta.name   = QStringLiteral("Netflix");
    entry.meta.mode   = QStringLiteral("takeover");
    // The browser is a family of processes; the screen comes back once all
    // of them have gone.
    entry.meta.wait   = QStringLiteral("pgroup");

    QString error;
    if (!m_launcher->start(entry, &error)) {
        m_lastError = error;
        return false;
    }
    return true;
}

QString NetflixBackend::output() const {
    return m_launcher->outputText();
}

void NetflixBackend::close() {
    if (m_launcher->isBusy())
        m_launcher->requestStop();
}

void NetflixBackend::signOut() {
    if (m_launcher->isBusy()) {
        qWarning("[Netflix] Not signing out while the browser is open");
        return;
    }
    if (QDir(browserProfile()).removeRecursively())
        qInfo("[Netflix] Signed out: browser profile removed");
}
