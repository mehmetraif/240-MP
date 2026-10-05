#pragma once
#include <QImage>
#include <QObject>
#include <QProcess>
#include <QLocalSocket>
#include <QSize>
#include <QTimer>
#include <QJsonArray>
#include <QStringList>

class AppCore;
class DisplayHandoff;
class EmbeddedMpv;

class MpvController : public QObject {
    Q_OBJECT
    Q_PROPERTY(int position    READ position    NOTIFY positionChanged)
    Q_PROPERTY(int duration    READ duration    NOTIFY durationChanged)
    Q_PROPERTY(int playlistPos READ playlistPos NOTIFY playlistPosChanged)
    // Transparent Background (see below): a session is playing inside the
    // app's own window, and VideoSurface shows its picture...
    Q_PROPERTY(bool videoActive READ videoActive NOTIFY videoActiveChanged)
    // ...and goes on behind the menus, back having returned to them.
    Q_PROPERTY(bool background READ background NOTIFY backgroundChanged)

public:
    explicit MpvController(const QString &appRoot, const QString &dataRoot,
                           AppCore *appCore = nullptr,
                           DisplayHandoff *handoff = nullptr,
                           QObject *parent = nullptr);
    ~MpvController() override;

    int position()    const { return m_position;    }
    int duration()    const { return m_duration;    }
    int playlistPos() const { return m_playlistPos; }

    Q_INVOKABLE void loadAndPlay(const QString &url, float startSeconds,
                                  int audioTrack, int subTrack,
                                  const QStringList &subFiles = {},
                                  const QStringList &subLangs = {},
                                  bool loop = false,
                                  int playlistStart = -1,
                                  float transcodeOffsetSec = 0.0f,
                                  const QString &plexToken = {},
                                  bool muteAudio = false,
                                  const QString &oscMode = {},
                                  bool shuffle = false,
                                  const QStringList &subTitles = {},
                                  float imageDurationSec = 0.0f,
                                  bool imageContent = false,
                                  const QStringList &extraArgs = {},
                                  const QString &jellyfinToken = {},
                                  const QStringList &extraUrls = {});
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seekTo(int positionMs);
    Q_INVOKABLE void sendKey(const QString &key);
    Q_INVOKABLE void showOsdSkipPrompt();
    Q_INVOKABLE void clearOsdPrompt();

    // True only on devices whose smooth-playback decode path can't crop/zoom (the
    // Pi 3 DRM-overlay path). Settings uses this to show the "Smooth Playback"
    // toggle only where the smoothness-vs-crop trade-off actually exists.
    Q_INVOKABLE bool hasSmoothPlaybackTradeoff() const;

    // The module whose views are open (Main.qml, as its loader changes), for
    // the settings a module can override: its own Scaling.
    Q_INVOKABLE void setActiveModule(const QString &moduleId) { m_activeModule = moduleId; }

    // Transparent Background (app setting "transparent_background", On or
    // Dim): video is played inside the app's own window (EmbeddedMpv) rather
    // than by an mpv process over it, so the menus can be drawn over the
    // picture. Back from playback then returns to the menus and leaves the
    // video playing behind them: the module takes it as stopped (it saves
    // where it got to, and goes back), while the picture and the sound go
    // on. Choosing the same thing again brings it back full screen where it
    // is; playing anything else, Main.qml's STOP, a takeover or the setting
    // turned off ends it.
    //
    // Needs libmpv, opened at run time: embeddedAvailable() says whether it is
    // there (Settings offers the setting only then).
    Q_INVOKABLE bool embeddedAvailable() const;
    bool videoActive() const;
    bool background() const { return m_background; }
    // Ends a session playing behind the menus.
    Q_INVOKABLE void stopBackground();
    // The embedded session's newest picture, and the size to draw it at
    // (VideoSurface).
    QImage videoFrame() const;
    void setVideoTargetSize(const QSize &size);

    // Which display fullscreen playback should open on, matching the UI's
    // app-level "display_index" (index into QGuiApplication::screens(), plus
    // that screen's QScreen::name()). main.cpp calls this once at startup;
    // index 0 (the default) adds no mpv args at all. Desktop launches only —
    // the headless VT-handoff path is unaffected.
    void setTargetDisplay(int index, const QString &screenName);

signals:
    void positionChanged(int ms);
    void durationChanged(int ms);
    void playlistPosChanged(int pos);
    // Emitted exactly once when mpv exits, with the reason it ended:
    //   "eof"     — file played to its natural end. (What a module does with this
    //               is its own concern.  as an example: Plex may autoplay the next episode)
    //   "stopped" — user quit/stopped before the end (also the safe default for a
    //               crash/kill with no end-file event).
    //   "failed"  — mpv exited with an error (code 2 — file could not be played;
    //               Up to the module as to when/how to use; for example Plex retries when transcoding).
    // A single signal (rather than one per reason) is deliberate: a Player view
    // connects one handler and branches on `reason`, so it can never silently drop
    // a case the way an unhandled per-reason signal would.
    void playbackEnded(int finalPositionMs, int finalDurationMs, const QString &reason);

    void skipRequested();
    void videoActiveChanged();
    void backgroundChanged();
    void videoFrameReady();
    // The OSC's SUBTITLE button when the sub is burned into the stream and mpv
    // has nothing to cycle (see `sub-cycle` in scripts/mpv-osc.lua). The module
    // owns the change — typically stop, re-request the stream, relaunch.
    void subtitleCycleRequested();
    // The OSC's AUDIO button when the track is baked into the stream and mpv has
    // nothing to cycle (see `audio-cycle` in scripts/mpv-osc.lua). As above, the
    // module owns the change.
    void audioCycleRequested();

private slots:
    void onProcessFinished();
    void tryConnectIpc();
    void onIpcReadyRead();

private:
    // Hardware video-decode profile, detected once from /proc/device-tree/model.
    enum class VideoProfile { Pi3, Pi4, PiFullKms, Generic };

    void sendCommand(const QJsonArray &args);
    // The mpv command line for a session, up to how its picture is shown.
    QStringList sessionArgs(const QString &url, float startSeconds, int audioTrack, int subTrack,
                            const QStringList &subFiles, const QStringList &subLangs, bool loop,
                            int playlistStart, float transcodeOffsetSec, const QString &plexToken,
                            bool muteAudio, const QString &oscMode, bool shuffle,
                            const QStringList &subTitles, float imageDurationSec, bool imageContent,
                            const QStringList &extraArgs, const QString &jellyfinToken,
                            const QStringList &extraUrls, bool embedded);
    // Transparent Background is on, and libmpv is there to play inside the app.
    bool transparentBackground() const;
    // The decode flags for a session played inside the app: the hardware
    // decoders' copy-back modes, which hand frames to the software renderer.
    void appendEmbeddedVideoArgs(QStringList &args) const;
    void startEmbedded(QStringList args);
    // Ends an embedded session without a word to its module: as a process
    // replaced by the next is, or one left playing behind the menus.
    void endEmbedded();
    void onEmbeddedFinished(const QString &lastEndReason);
    // Back during an embedded session: the menus come back over the picture.
    void detachToMenus();
    // The session behind the menus chosen again: full screen, where it is.
    void reattach(float startSeconds);
    VideoProfile detectVideoProfile() const;
    // Appends the profile-specific --vo/--gpu-context/--hwdec flags (honouring the
    // app-level "mpv_video_args" override) to a forming mpv argument list.
    void appendVideoArgs(QStringList &args) const;
    // App-level "smooth_playback" setting (default ON). On the Pi 3 this selects the
    // smooth zero-copy overlay path; turning it OFF restores the crop-capable scaler path.
    bool smoothPlaybackEnabled() const;
    // App-level "auto_crop" setting (default OFF), from before Scaling: its ON
    // reads as Pan & Scan while no Scaling has been chosen.
    bool autoCropEnabled() const;
    // The Scaling in force ("Letterbox", "14:9", "Pan & Scan", "Anamorphic"):
    // the active module's own "video_scaling", unless it is "Default", then the
    // app's.
    QString videoScaling() const;
    // True when the active decode path can't crop (Pi 3 overlay path with smooth
    // playback ON): --panscan blanks the video there. Gates auto-crop and tells
    // the OSC scripts to hide their CROP button.
    bool cropUnavailable() const;
    // App-level "video_output_levels" setting (default "Auto"). Returns the mpv
    // value for --video-output-levels ("limited"/"full"), or empty on Auto/unset.
    QString videoOutputLevels() const;

    // Owner token handed to DisplayHandoff, so the app can tell who has the screen.
    static constexpr const char *kHandoffOwner = "mpv";

    AppCore        *m_appCore      = nullptr;
    QString         m_activeModule;
    EmbeddedMpv    *m_embedded     = nullptr;
    bool            m_background   = false;
    int             m_detachPositionMs = 0;
    // The embedded session's command line, to know it when it is asked for again.
    QStringList     m_sessionArgs;
    QSize           m_videoTargetSize { 640, 480 };
    QString         m_embeddedInputConfPath;
    DisplayHandoff *m_handoff      = nullptr;
    VideoProfile  m_videoProfile  = VideoProfile::Generic;
    QProcess     *m_process        = nullptr;
    QLocalSocket *m_ipc            = nullptr;
    QTimer       *m_connectTimer   = nullptr;
    QTimer       *m_watchdogTimer  = nullptr;
    qint64        m_lastIpcEventMs = 0;
    bool          m_paused         = false;  // mirrors mpv's pause property (watchdog exemption)
    QString       m_appRoot;
    QString       m_dataRoot;
    QString       m_socketPath;
    QString       m_inputConfPath;
    QString       m_logFilePath;
    QString       m_subInfoPath;       // JSON map: external sub URL -> friendly name (for the OSC)
    QString       m_lastEndFileReason;  // mpv end-file "reason" for the current session
    // Set when this session passed --start; cleared once mpv has applied it. See
    // onIpcReadyRead's playback-restart handling for why the option can't just stay set.
    bool          m_pendingStartClear = false;
    int           m_position     = 0;
    int           m_duration     = 0;
    int           m_playlistPos  = -1;
    bool          m_headlessMode = false;
    int           m_displayIndex = 0;   // see setTargetDisplay()
    QString       m_displayScreenName;
    int           m_previousVt   = -1;
    bool          m_hasMpvOscScript     = false;
    bool          m_hasAmbientOscScript = false;
    bool          m_hasMediaKeysScript  = false;
};
