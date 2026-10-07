import QtQuick
import QtQuick.Window
import MP240.Video
import Components

Window {
    id: root
    flags: Qt.FramelessWindowHint | Qt.Window
    title: "OSD/OS"
    x:      Qt.platform.os === "osx" ? macScreenX      : Screen.virtualX
    y:      Qt.platform.os === "osx" ? macScreenY      : Screen.virtualY
    width:  Qt.platform.os === "osx" ? macScreenWidth  : Screen.width
    height: Qt.platform.os === "osx" ? macScreenHeight : Screen.height
    // macOS uses manual geometry (the target display chosen by the app-level
    // "display_index" setting, resolved in main.cpp) + a native fullscreen
    // call to keep the mpv-over-window layering intact. Everywhere else,
    // request true fullscreen so a desktop compositor's panel/dock (KDE on the
    // Steam Deck, labwc on the Pi) is covered rather than left stacked on top;
    // the Screen.* bindings track the window's screen, so they follow the
    // display_index move main.cpp performs after load. Headless EGLFS is
    // already fullscreen, so this is a no-op there.
    visibility: Qt.platform.os === "osx" ? Window.AutomaticVisibility
                                         : Window.FullScreen
    visible: true
    // Under everything: what OSD BACKGROUND puts around its window (black
    // but for FULL). OsdGround draws the ground itself, over it.
    color: root.osdBackground === "Full" ? root.surfaceColor : "#000000"

    // --- Color Schemes ---
    readonly property var themes: ({
        "Video 1": {
            "primary": "#FFFFFF",
            "secondary": "#C2BFE4",
            "tertiary": "#8480C9",
            "surface": "#0110C5", // the blue of a VCR's on-screen menu
            "accent": "#AECFFF"
        },
        "Late Night": {
            "primary": "#FFFFFF",
            "secondary": "#A1A1A1",
            "tertiary": "#444444",
            "surface": "#000000",
            "accent": "#FFD900"
        },
        "Synthwave": {
            "primary": "#FFFFFF",
            "secondary": "#D48BFF",
            "tertiary": "#7836B5",
            "surface": "#12012B",
            "accent": "#00E5FF"
        },
        "Terminal": {
            "primary": "#4AF626",
            "secondary": "#32A81B",
            "tertiary": "#1A590E",
            "surface": "#000000",
            "accent": "#4AF626"
        },
        "T-120": {
            "primary": "#000000",
            "secondary": "#818181",
            "tertiary": "#df9c27",
            "surface": "#FAF5E8",
            "accent": "#EE442F"
        },
        "Amber": {
            "primary": "#FFB000",
            "secondary": "#B37B00",
            "tertiary": "#B37B00",
            "surface": "#000000",
            "accent": "#FFEE11"
        },
        "Kinescope": {
            "primary": "#FFFFFF",
            "secondary": "#9E9E9E",
            "tertiary": "#424242",
            "surface": "#121212",
            "accent": "#FFFFFF"
        },
        "SMPTE ECR 1-1978": {  // 75% max 0xFF == 0xBF, 40% max 0xFF == 0x66, 7.5% max 0xFF == 0x13; 75/7.5 targets per https://en.wikipedia.org/wiki/SMPTE_color_bars#Analog_NTSC - mixed with 40% in "off channels" to both wash out and improve contrast
            "primary": "#BFBFBF",
            "secondary": "#66BF66",
            "tertiary": "#6666BF",
            "surface": "#131313",
            "accent": "#BF6666"
        }
    })
    property var allThemes: themes  // may gain a "Custom" entry on startup
    property string currentTheme: "Video 1"
    readonly property var theme: allThemes[currentTheme] || allThemes["Video 1"]
    // Settings' OSD BACKGROUND (app.osd_background), what the menus are drawn
    // on (Components/OsdGround): "Full", the default, the scheme's background
    // over the whole screen; "Window", a framed window of it behind what a
    // view shows (osdWindow), black around it; "Off", none: black, the menus
    // in whichever of the scheme's two colours is the lighter, as a deck's OSD
    // with nothing playing. A scheme's dark text (T-120's) would vanish on
    // black, so Off takes its background colour for the text instead.
    property string osdBackground: "Full"
    readonly property bool osdOff: osdBackground === "Off"
    property string primaryColor:   osdOff ? lighterOf(theme.primary, theme.surface) : theme.primary
    property string surfaceColor:   osdOff ? "#000000" : theme.surface
    // Two colours only, like a deck's on-screen display: everything is drawn in
    // the theme's primary colour on its surface colour. A selection is a solid
    // box with its text in the surface colour, and anything dimmed is dithered
    // (Components/Dither) rather than faded. The themes' other three colours
    // stay in their definitions, unused.
    property string secondaryColor: primaryColor
    property string tertiaryColor:  primaryColor
    property string accentColor:    primaryColor

    readonly property real sw: width
    readonly property real sh: height
    // One pixel of a 240-line picture, in screen pixels: the unit the
    // pixel-drawn OSD elements (Components/Osd*, PixelIcon) are built on.
    readonly property int px: Math.max(1, Math.floor(sh / 240))

    // The area the views lay their content out in: the title bar's logo to
    // the hint bar (74 to 566 across and 57 to 430 down, of 640×480).
    readonly property rect contentBox: Qt.rect(sw * 0.115625, sh * 0.11875, sw * 0.76875, sh * 0.7770833)
    // OSD BACKGROUND's window: the content box with a margin on every side,
    // on art pixels.
    readonly property real osdMargin: sh * 0.025 //12
    readonly property rect osdWindow: {
        var left = snapPx(contentBox.x - osdMargin), right = snapPx(contentBox.x + contentBox.width + osdMargin)
        var top = snapPx(contentBox.y - osdMargin), bottom = snapPx(contentBox.y + contentBox.height + osdMargin)
        return Qt.rect(left, top, right - left, bottom - top)
    }
    function snapPx(v) { return Math.round(v / px) * px }

    // A time as the players show it: h:mm:ss, or m:ss under an hour.
    function formatTime(ms) {
        var s = Math.floor(ms / 1000)
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var sec = s % 60
        return (h > 0 ? h + ":" + pad(m) : m) + ":" + pad(sec)
    }
    function pad(n) { return n < 10 ? "0" + n : "" + n }

    // The lighter of two colours, by how bright the eye finds them.
    function lighterOf(a, b) {
        function luma(c) { var k = Qt.color(c); return 0.2126 * k.r + 0.7152 * k.g + 0.0722 * k.b }
        return luma(a) >= luma(b) ? a : b
    }

    Connections {
        target: appCore
        function onAppSettingChanged(key, value) {
            if (key === "color_scheme") {
                root.currentTheme = value
            } else if (key === "transparent_background") {
                root.backdropSolidity = root.solidityOf(value)
            } else if (key === "loading_effect") {
                root.loadingEffect = value !== "Off"
            } else if (key === "hint_bar") {
                root.hintBar = value !== "Off"
            } else if (key === "help_line") {
                root.helpLine = value !== "Off"
            } else if (key === "osd_background") {
                root.osdBackground = root.osdBackgroundOf(value)
            } else if (key === "mouse_pointer") {
                root.pointerSetting = String(value)
                if (root.pointerShown)
                    pointerTimer.restart()
            } else if (key === "screensaver_timeout") {
                var sec = parseInt(value)
                if (sec > 0) {
                    idleTracker.threshold = sec
                    idleTracker.enabled = true
                } else {  // "OFF"
                    idleTracker.enabled = false
                    if (screenSaverActive) screenSaverActive = false
                }
            }
        }
    }

    Component.onCompleted: {
        var cfg = appCore.get_settings()

        var cThemes = appCore.getCustomColorSchemes()
        if (Object.keys(cThemes).length > 0) {
            var t = Object.assign({}, themes, root.allThemes)
            for (var cTheme in cThemes) {
                if (Object.keys(cThemes[cTheme]).length === 5) {
                    t[cTheme] = cThemes[cTheme]
                }
            }
            root.allThemes = t
        }

        var custom = appCore.getCustomColorScheme()
        if (Object.keys(custom).length === 5) {
            var t = Object.assign({}, themes, root.allThemes)
            t["Custom"] = custom
            root.allThemes = t
        }

        var savedTheme = (cfg.app && cfg.app.color_scheme) || "Video 1"
        if (savedTheme === "Custom" && !root.allThemes["Custom"]) {
            appCore.save_setting("", "color_scheme", "Video 1")
            savedTheme = "Video 1"
        }
        root.currentTheme = savedTheme
        root.backdropSolidity = root.solidityOf(cfg.app && cfg.app.transparent_background)
        root.pointerSetting = String((cfg.app && cfg.app.mouse_pointer) || "5")
        root.loadingEffect = !(cfg.app && cfg.app.loading_effect === "Off")
        root.hintBar = !(cfg.app && cfg.app.hint_bar === "Off")
        root.helpLine = !(cfg.app && cfg.app.help_line === "Off")
        root.osdBackground = root.osdBackgroundOf(cfg.app && cfg.app.osd_background)

        // Screensaver: the tracker starts disabled; this is the single place the
        // saved setting is applied (live changes land in onAppSettingChanged above,
        // mirroring color_scheme). parseInt("OFF") is NaN, so OFF stays disabled.
        var ssSec = parseInt(cfg.app && cfg.app.screensaver_timeout)
        if (ssSec > 0) {
            idleTracker.threshold = ssSec
            idleTracker.enabled = true
        }

        // Break declarative bindings on macOS so the C++ NSWindow override
        // in forceWindowFullScreenOnScreen() isn't immediately re-fought by QML.
        if (Qt.platform.os === "osx") {
            root.x = macScreenX
            root.y = macScreenY
            root.width = macScreenWidth
            root.height = macScreenHeight
        }
    }
    
    FontLoader {
        id: font; source: "assets/fonts/VCR_OSD_MONO_1.001.ttf"
    }
    // Unifont fills in glyphs VCR OSD Mono doesn't have (CJK, Hangul, etc.),
    // it's a bitmap-style font so it actually matches the retro CRT look
    // instead of a mismatched serif/sans fallback. This Qt build's font value
    // type has no font.families (checked plugins.qmltypes: family only), so
    // loading it here just registers it with Qt's fontconfig-backed font
    // database; Qt's own missing-glyph fallback then picks it up for every
    // existing font.family: root.globalFont binding with no further changes.
    FontLoader {
        id: unifontLoader; source: "assets/fonts/unifont.otf"
    }
    property string globalFont: font.name;

    // --- INPUT / APP INFO MIRRORS ---
    // Views must bind these via `root.*`, never the appCore/inputManager
    // context properties directly: when the module Loader swaps views, the
    // dying view's context properties resolve to null and any binding on them
    // throws a TypeError during teardown. id-resolved `root.*` stays valid
    // (root lives as long as the app), so these mirrors are teardown-safe.
    // The null guards absorb the same nulling here at app shutdown, when the
    // engine invalidates the root context itself.
    readonly property var hints: inputManager ? inputManager.hints : ({})
    readonly property string appVersion: appCore ? appCore.appVersion : ""
    readonly property string appBuild: appCore ? appCore.appBuild : ""

    // --- BOOT SCREEN (240-MP OS image only, see os/README.md) ---
    // bootProgress mirrors, for the same teardown-safety reason as above.
    readonly property bool   bootActive: bootProgress ? bootProgress.active : false
    readonly property real   bootValue:  bootProgress ? bootProgress.progress : 0
    readonly property var    bootSteps:  bootProgress ? bootProgress.steps : []
    readonly property string bootLabel:  bootProgress ? bootProgress.currentLabel : ""

    // The startup module waits for the boot screen: most modules need the
    // network the boot screen is waiting on.
    onBootActiveChanged: {
        if (bootActive) return
        if (moduleLoader.item) moduleLoader.item.forceActiveFocus()
        openStartupModule()
    }

    // --- SCREEN SAVER STATE ---
    property bool screenSaverActive: false

    // Playback counts as user activity even when no key started it (an NFC
    // card tap launches mpv directly). If the saver was showing at launch,
    // nothing key-driven ever reaches its dismiss handler — focus has moved
    // into the module's player view — so clear it on playback transitions.
    function dismissScreenSaver() {
        if (!screenSaverActive) return
        screenSaverActive = false
        moduleLoader.forceActiveFocus()
    }

    // --- APP-LEVEL NAV STACK ---
    property var appNavStack: []
    property var appCurrentParams: ({})
    property bool _startupNavigated: false

    // Opens the configured startup module, once per run. A favourite chosen to
    // PLAY AT STARTUP (EntryOptions) comes first: its module opens and plays
    // it straight away (navParams.startupPlay), as long as it is still one of
    // that module's favourites.
    function openStartupModule() {
        if (root._startupNavigated) return
        root._startupNavigated = true
        var params = { fromAppStartup: true }
        var entryPoint = ""
        var startup = appCore.get_setting("", "startup_favorite")
        if (startup && startup.module && startup.path) {
            var favorites = appCore.get_list(startup.module, "favorites")
            for (var i = 0; i < favorites.length; ++i) {
                if (favorites[i].path === startup.path) {
                    entryPoint = appCore.moduleEntryPoint(startup.module)
                    params.startupPlay = favorites[i]
                    break
                }
            }
        }
        if (!entryPoint) {
            delete params.startupPlay
            entryPoint = appCore.startupModuleEntryPoint()
        }
        if (entryPoint) {
            root.appNavStack.push({
                source: moduleLoader.source,
                params: root.appCurrentParams,
                listState: {}
            })
            moduleLoader.setSource(entryPoint, { "navParams": params })
        }
    }

    // --- MPV PLAYBACK TRACKING ---
    // Block the screen saver while mpv is playing so it never flashes during or
    // immediately after playback. The core guard is in IdleTracker (mpvActive
    // property), which also resets the idle timer on transitions.
    Connections {
        target: mpvController
        function onPositionChanged(ms) {
            if (ms > 0 && !idleTracker.mpvActive) {
                idleTracker.mpvActive = true
                idleTracker.resetActivity()
                root.dismissScreenSaver()
            }
        }
        function onPlaybackEnded(finalPositionMs, finalDurationMs, reason) {
            // A video left playing behind the menus is still playing.
            idleTracker.mpvActive = mpvController.videoActive
            idleTracker.resetActivity()
            root.dismissScreenSaver()
        }
        function onVideoActiveChanged() {
            idleTracker.mpvActive = mpvController.videoActive
            idleTracker.resetActivity()
        }
    }

    // --- VIDEO PLAYED INSIDE THIS WINDOW (Transparent Background) ---
    // MpvController plays it here rather than in an mpv window of its own
    // while the setting is on: its picture lies over everything while it
    // plays full screen, and under the menus once back has returned to them,
    // where it goes on playing (videoBehind). The menus draw no background of
    // their own, so the picture is theirs then; full-screen dialogs keep
    // theirs. The setting's slider says how solid their ground is over it.
    readonly property bool videoActive: mpvController ? mpvController.videoActive : false
    readonly property bool videoBehind: mpvController ? mpvController.background : false
    // What its player noted of the video behind the menus ({ module, title,
    // params }, see MpvController::noteSession): the main menu offers it
    // back as its first row. Empty for a player that notes nothing.
    readonly property var behindNote: mpvController ? mpvController.backgroundNote : ({})
    property int backdropSolidity: 100
    // Another process has the screen: mpv, or a script, on the Pi's console
    // (see DisplayHandoff). Nothing drawn here reaches it until it is back,
    // so what animates rests meanwhile (LoadingScreen).
    readonly property bool screenHandedOff: displayHandoff ? displayHandoff.held : false
    // "loading_effect": the tape's noise and bands on the screen a video
    // loads behind (LoadingScreen), "On" (the default, when unset) or "Off".
    property bool loadingEffect: true
    // "hint_bar": the key hints on the bar at the foot of every screen
    // (HintBar), "On" (the default, when unset) or "Off".
    property bool hintBar: true
    // "help_line": the line about the selected row in the box under a menu
    // (HelpLine), "On" (the default, when unset) or "Off".
    property bool helpLine: true

    // "transparent_background": how solid the menus' ground is over a video
    // behind them, 0 (TRANSPARENT) to 100 (SOLID: none of it shows, but it
    // plays on, sound and all), or "Off", the default when unset (back stops
    // the video, as it always has). Its first values were words: On (0) and
    // Dim (60). Read as MpvController::transparentBackground() reads it.
    function backgroundOn(raw) {
        var s = String(raw === undefined || raw === null ? "" : raw).trim().toLowerCase()
        return s === "on" || s === "dim" || !isNaN(parseInt(s))
    }
    function osdBackgroundOf(raw) {
        return raw === "Window" || raw === "Off" ? raw : "Full"
    }
    function solidityOf(raw) {
        var s = String(raw === undefined || raw === null ? "" : raw).toLowerCase()
        if (s === "on") return 0
        if (s === "dim") return 60
        var n = parseInt(s)
        return isNaN(n) ? 100 : Math.max(0, Math.min(100, n))
    }

    VideoSurface {
        anchors.fill: parent
        controller: mpvController
        visible: root.videoActive
        z: root.videoBehind ? -2 : 5000
    }
    // What the menus are drawn on (OSD BACKGROUND), under every view. Over a
    // video behind them, as solid as Transparent Background says, and in
    // WINDOW only the window, the picture showing whole around it.
    OsdGround {
        anchors.fill: parent
        z: -1
        visible: !root.videoBehind || root.backdropSolidity > 0
        opacity: root.videoBehind ? root.backdropSolidity / 100 : 1
        surround: !root.videoBehind
    }

    // A running user script suppresses the screen saver too — a takeover script
    // owns the display, and even a console one is legitimately silent for as long
    // as it takes. Its own flag rather than reusing mpvActive, so ending one
    // session can't unblock the saver while the other is still going.
    Connections {
        target: scriptsBackend
        function onScriptRunningChanged() {
            idleTracker.scriptActive = scriptsBackend.scriptBusy
            idleTracker.resetActivity()
            if (!scriptsBackend.scriptBusy)
                root.dismissScreenSaver()
        }
    }

    // --- MODULE LOADER ---
    Loader {
        id: moduleLoader;
        anchors.fill: parent;
        focus: true;
        source: "views/ModuleList.qml";

        // Playback follows the open module's own settings where it has them
        // (its Scaling).
        onSourceChanged: mpvController.setActiveModule(appCore.moduleIdForSource(source.toString()))

        Keys.onPressed: (event) => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Q) {
                Qt.quit()
            }
        }

        onLoaded: {
            // While the boot screen is up it keeps the focus; QML gives no
            // order between this and its own onLoaded, so don't race it.
            if (root.bootActive)
                return
            item.forceActiveFocus()
            root.openStartupModule()
        }

        Connections {
            target: moduleLoader.item
            ignoreUnknownSignals: true

            function onNavigateTo(path, params, listState) {
                root.appNavStack.push({ source: moduleLoader.source, params: root.appCurrentParams, listState: listState || {} })
                root.appCurrentParams = params || {}
                moduleLoader.setSource(path, { "navParams": params || {} })
            }

            function onGoBack() {
                if (root.appNavStack.length === 0) return
                var prev = root.appNavStack.pop()
                root.appCurrentParams = prev.params
                moduleLoader.setSource(prev.source, { "navParams": prev.params, "navListState": prev.listState || {} })
            }

        }
    }

    // --- SCREEN SAVER (Idle Tracker integration) ---
    Connections {
        target: idleTracker
        function onActiveChanged() {
            // Only show on active → true; never hide here — the overlay's
            // key handler owns dismissal, preventing the C++ event filter's
            // synchronous reset from stealing the key from QML. Never over the
            // boot screen, which would lose focus to it.
            if (idleTracker.active && idleTracker.enabled && !root.bootActive) {
                if (!screenSaverActive) {
                    var usableW = screenSaverOverlay.width - bounceLogo.width
                    var usableH = screenSaverOverlay.height - bounceLogo.height
                    bounceLogo.x = Math.random() * (usableW > 0 ? usableW : 1)
                    bounceLogo.y = Math.random() * (usableH > 0 ? usableH : 1)
                    bounceLogo.vx = (Math.random() > 0.5 ? 1 : -1) * (1 + Math.random() * 1.5)
                    bounceLogo.vy = (Math.random() > 0.5 ? 1 : -1) * (1 + Math.random() * 1.5)
                    screenSaverActive = true
                    screenSaverOverlay.forceActiveFocus()
                }
            }
        }
    }

    // Above the module views, below the screen saver. Declared after
    // moduleLoader so its focus grab wins over the first view's.
    Loader {
        id: bootScreenLoader
        anchors.fill: parent
        z: 9000
        active: root.bootActive
        source: "views/BootScreen.qml"
        onLoaded: item.forceActiveFocus()
    }

    Item {
        id: screenSaverOverlay
        anchors.fill: parent
        visible: screenSaverActive
        z: 9999
        focus: visible

        // Solid black background — no transparency so it serves as a true
        // CRT burn-in prevention black frame between the logo bounces.
        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }

        // Bouncing logo — classic DVD player screen saver
        Image {
            id: bounceLogo
            source: "assets/images/logo.svg"
            sourceSize.width: root.sw * 0.05
            sourceSize.height: root.sw * 0.05
            fillMode: Image.PreserveAspectFit
            antialiasing: true

            property real vx: 0
            property real vy: 0

            // Physics tick at ~60 fps while the overlay is visible
            Timer {
                interval: 16
                repeat: true
                running: screenSaverActive
                onTriggered: {
                    bounceLogo.x += bounceLogo.vx
                    bounceLogo.y += bounceLogo.vy

                    if (bounceLogo.x + bounceLogo.width > screenSaverOverlay.width) {
                        bounceLogo.x = screenSaverOverlay.width - bounceLogo.width
                        bounceLogo.vx = -Math.abs(bounceLogo.vx)
                    } else if (bounceLogo.x < 0) {
                        bounceLogo.x = 0
                        bounceLogo.vx = Math.abs(bounceLogo.vx)
                    }

                    if (bounceLogo.y + bounceLogo.height > screenSaverOverlay.height) {
                        bounceLogo.y = screenSaverOverlay.height - bounceLogo.height
                        bounceLogo.vy = -Math.abs(bounceLogo.vy)
                    } else if (bounceLogo.y < 0) {
                        bounceLogo.y = 0
                        bounceLogo.vy = Math.abs(bounceLogo.vy)
                    }
                }
            }
        }

        // Capture any keypress to dismiss — consumes the event so the
        // underlying view never sees it, preventing accidental navigation.
        // Ctrl+Q still quits (moduleLoader's handler is a sibling, so it
        // can't see keys focused here — handle the chord directly).
        Keys.onPressed: (event) => {
            event.accepted = true
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Q) {
                Qt.quit()
                return
            }
            screenSaverActive = false
            moduleLoader.forceActiveFocus()
        }
    }

    // --- MOUSE POINTER ---
    // Qt's own pointer stays hidden (main.cpp: on a headless screen it is a
    // hardware cursor that wouldn't stay hidden). This one is drawn in the
    // OSD's pixels, over everything: it shows as the mouse moves and goes
    // again after Settings' MOUSE POINTER seconds without moving
    // (app.mouse_pointer: "off", "always" or seconds; 5 when unset). Moving
    // the mouse counts as being there, for the screen saver too. The menus
    // themselves go by keys.
    property string pointerSetting: "5"
    property bool pointerShown: false

    MouseArea {
        anchors.fill: parent
        z: 20000
        enabled: root.pointerSetting !== "off"
        hoverEnabled: true
        // Only follows the mouse: clicks and the wheel go on to what is under it.
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
            pointer.x = mouse.x
            pointer.y = mouse.y
            root.pointerShown = true
            pointerTimer.restart()
            idleTracker.resetActivity()
            root.dismissScreenSaver()
        }
    }

    MousePointer {
        id: pointer
        z: 20001
        visible: root.pointerShown && root.pointerSetting !== "off"
    }

    Timer {
        id: pointerTimer
        interval: (parseInt(root.pointerSetting) || 5) * 1000
        onTriggered: {
            if (root.pointerSetting !== "always")
                root.pointerShown = false
        }
    }
}
