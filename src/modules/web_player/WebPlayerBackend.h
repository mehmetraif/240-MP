#pragma once
#include <QObject>
#include <QString>
#include <QVariant>
#include "TmdbCatalog.h"

class DisplayHandoff;
class ScriptLauncher;

// A streaming service opened as its own web player, full screen: Netflix and
// Prime Video, one instance each. Neither has an API a front end like this one
// could browse with, and their streams are Widevine-protected, so mpv can't
// play them; Chromium with Widevine can. scripts/web-player.sh works out how
// to run the browser on each target, under the cage kiosk compositor on a
// headless Pi, and this runs it as a takeover through its own ScriptLauncher,
// the way the Scripts module runs a takeover script: on a headless Pi
// DisplayHandoff brackets the run, and the screen comes back once the browser
// and everything it started have exited. Its catalog (TmdbCatalog) is what the
// module browses before it opens a title.
class WebPlayerBackend : public QObject {
    Q_OBJECT
    // Not done with the screen yet: the browser is open, or it has closed and
    // the processes it left behind are still exiting.
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QObject *catalog READ catalog CONSTANT)

public:
    struct Service {
        QString id;       // the short name the run and the browser profile go by ("netflix")
        QString homeUrl;  // the page the service opens at
        TmdbCatalog::Service catalog;
    };

    explicit WebPlayerBackend(const Service &service,
                              const QString &appRoot, const QString &dataRoot,
                              DisplayHandoff *handoff, QObject *parent = nullptr);

    bool running() const;
    QObject *catalog() const { return m_catalog; }

    // Opens the service at url, or at its home page. Returns false, with
    // lastError() saying why, when nothing was started: no browser, or no
    // kiosk compositor on a headless Pi. Those are checked before the screen is
    // handed over, so a missing package never blanks the screen.
    Q_INVOKABLE bool launch(const QString &url = QString());
    Q_INVOKABLE QString lastError() const { return m_lastError; }

    // The last lines the launcher printed: the only diagnostic a user gets
    // when the browser exits at once on a headless Pi.
    Q_INVOKABLE QString output() const;

    // Closes the browser and everything it started: the way back without a
    // keyboard to close it with.
    Q_INVOKABLE void close();

    // manifest: sign_out (action). Deletes the browser profile, which is where
    // the service's sign-in lives.
    Q_INVOKABLE void signOut();

public slots:
    // The module's catalogue region and language (wired by registerModule).
    void onSettingChanged(const QString &moduleId, const QString &key, const QVariant &value);

signals:
    void runningChanged();
    // Once per launch. reason: "ok" (the browser was closed), "failed",
    // "stopped" (close() ended it) or "failed_to_start".
    void finished(int exitCode, const QString &reason);

private:
    QString browserProfile() const;
    QString moduleId() const { return QStringLiteral("com.240mp.") + m_service; }
    void    applySetting(const QString &key, const QVariant &value);

    QString         m_service;
    QString         m_url;
    TmdbCatalog    *m_catalog = nullptr;
    QString         m_appRoot;
    QString         m_dataRoot;
    QString         m_lastError;
    ScriptLauncher *m_launcher = nullptr;
};
