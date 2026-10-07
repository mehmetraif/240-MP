import QtQuick
import Components

FocusScope {
    id: settingsRoot

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    property var navParams: ({})
    property var navListState: ({})

    property var appSettings: ({})
    property var installedModules: []

    // Flat model: mix of section headers and rows
    property var settingsItems: []

    property bool quitOverlayVisible: false
    property int quitChoiceIndex: 0

    // Quit overlay choices. Under the autostart service (headless RPi) the quit menu has an
    // "Exit to Terminal" option that drops to a tty1 login without powering off, and a
    // "Restart" that reboots (where the stop helper knows how, see canRestartSystem());
    // they are not needed on macOS/Desktop or when run by hand, so it's yes/no for that case.
    property bool autostartSession: false
    property bool canRestart: false
    property var quitOptions: settingsRoot.autostartSession
        ? [{ label: "Power Off",        action: "quit"     }]
          .concat(settingsRoot.canRestart ? [{ label: "Restart", action: "restart" }] : [])
          .concat([{ label: "Exit to Terminal", action: "terminal" },
                   { label: "Cancel",           action: "cancel"   }])
        : [{ label: "Yes", action: "quit" },
           { label: "No",  action: "cancel" }]

    function buildModel() {
        var cfg = appCore.get_settings()
        appSettings = cfg.app || {}
        installedModules = appCore.get_installed_modules()
        autostartSession = appCore.isAutostartSession()
        canRestart = appCore.canRestartSystem()

        var items = []

        // APPLICATION section
        var colorOpts = ["Video 1","Late Night","Synthwave","Terminal","T-120","Amber","Kinescope","SMPTE ECR 1-1978"]
        // Adding a new approach to add multiple custom themes at once
        var cThemes = appCore.getCustomColorSchemes()
        if (Object.keys(cThemes).length > 0) {
            for (var cTheme in cThemes) {
                if (!colorOpts.includes(cTheme) && Object.keys(cThemes[cTheme]).length === 5) colorOpts.push(cTheme)
            }
        }
        // Still support the single-theme approach
        var custom = appCore.getCustomColorScheme()
        if (!colorOpts.includes("Custom") && Object.keys(custom).length === 5) colorOpts.push("Custom")
        items.push({
            type: "list_single",
            key: "color_scheme",
            label: "Color Scheme",
            options: colorOpts,
            value: appSettings["color_scheme"] || "Video 1",
            description: "Choose your prefered color scheme\nPlease see the wiki for details on adding a custom one",
            moduleId: ""
        })

        // OSD Background — what the menus are drawn on (Components/OsdGround,
        // read in Main.qml): the colour scheme's background over the whole
        // screen, none (black), or a framed window of it behind the menus.
        items.push({
            type: "list_single",
            key: "osd_background",
            label: "OSD Background",
            options: ["Full", "Off", "Window"],
            value: root.osdBackgroundOf(appSettings["osd_background"]),
            description: "What the menus are drawn on\n[FULL] The color scheme's background, all over  [OFF] None, the menus on black like a deck's on-screen display  [WINDOW] A framed window of it behind the menus, black around it",
            moduleId: ""
        })

        // Start on Module — pick a module to auto-launch into on startup.
        // Only present enabled modules as options so disabled ones won't display.
        // The setting is keyed by module id and the picker shows the display name
        // If the stored id isn't an enabled module, the display falls back to None.
        var moduleOpts = ["None"] // display labels
        var moduleVals = ["None"] // stored values (module ids)
        var startupId = appSettings["startup_module"] || "None"
        var startupValue = "None"
        for (var mi = 0; mi < installedModules.length; mi++) {
            if (!installedModules[mi].enabled) continue
            moduleOpts.push(installedModules[mi].name)
            moduleVals.push(installedModules[mi].id)
            if (installedModules[mi].id === startupId) startupValue = installedModules[mi].name
        }
        items.push({
            type: "list_single",
            key: "startup_module",
            label: "Start on Module",
            options: moduleOpts,
            values: moduleVals,
            value: startupValue,
            description: "Directly launch into a specific module on startup",
            moduleId: ""
        })

        // Play at Startup — a favourite played straight after the boot screen,
        // ahead of Start on Module. It is chosen in its module (right on it,
        // OPTIONS, PLAY AT STARTUP); here it can only be turned off.
        var startupFav = appSettings["startup_favorite"]
        var favName = startupFav && startupFav.path ? (startupFav.name || "Favorite") : ""
        items.push({
            type: "list_single",
            key: "startup_favorite",
            label: "Play at Startup",
            options: favName !== "" ? ["None", favName] : ["None"],
            values: favName !== "" ? ["", startupFav] : [""],
            value: favName !== "" ? favName : "None",
            description: "A favourite played straight after the boot screen, instead of opening a module\nChoose one with right on it in its module: OPTIONS, PLAY AT STARTUP",
            moduleId: ""
        })

        // Startup From — where that favourite begins. Either way it begins
        // without asking: a resume prompt is no question to put to a player
        // switched on to play. Offered while there is one.
        if (favName !== "") {
            items.push({
                type: "list_single",
                key: "startup_from",
                label: "Startup From",
                options: ["Resume", "Beginning"],
                value: appSettings["startup_from"] === "Beginning" ? "Beginning" : "Resume",
                description: "Where the favourite played at startup begins, without asking\n[RESUME] Where it was stopped  [BEGINNING] From the start",
                moduleId: ""
            })
        }

        // Smooth Playback — only shown on devices whose smooth decode path can't
        // crop/zoom (the Pi 3 overlay path). Default ON; turning it off restores the
        // crop-capable video output. Takes effect on the next video.
        if (mpvController.hasSmoothPlaybackTradeoff()) {
            items.push({
                type: "list_single",
                key: "smooth_playback",
                label: "1080p Playback",
                options: ["On", "Off"],
                value: appSettings["smooth_playback"] || "On",
                description: "[ON] Enable 1080p content playback, crop, 14:9 and Pan & Scan will not function\n[OFF] Enable crop, 1080p content playback will stutter",
                moduleId: ""
            })
        }

        // Scaling — how a picture of another shape fills the screen: a 16:9 film
        // on a 4:3 tube above all. Every video module's settings can override
        // it for that module. It replaces Auto Crop, whose ON reads as Pan &
        // Scan until a Scaling is chosen. The OSC's CROP still toggles live.
        var scalingOpts = ["Letterbox", "14:9", "Pan & Scan", "Anamorphic"]
        var scaling = appSettings["video_scaling"]
                      || (appSettings["auto_crop"] === "On" ? "Pan & Scan" : "Letterbox")
        items.push({
            type: "list_single",
            key: "video_scaling",
            label: "Scaling",
            options: scalingOpts,
            value: scalingOpts.indexOf(scaling) >= 0 ? scaling : "Letterbox",
            description: "How a 16:9 picture fills the 4:3 screen, in every module that doesn't set its own\n[LETTERBOX] All of it, bars above and below  [14:9] A little of the sides cut, thinner bars  [PAN & SCAN] Fills it, the sides cut  [ANAMORPHIC] Fills it squeezed, for a TV set to 16:9",
            moduleId: ""
        })

        // Transparent Background — video played inside the app's own window,
        // so back from it returns to the menus with the picture going on
        // behind them (MpvController). A slider, like the deck's tape bar,
        // from TRANSPARENT to SOLID: how solid the menus' ground is over the
        // picture, in tenths, and seen at once over a video behind them.
        // SOLID hides the picture, which plays on, sound and all; select turns
        // the setting off and on, as it does a module's toggles. It needs
        // libmpv, so it is offered only where that is installed.
        if (mpvController.embeddedAvailable()) {
            var backgroundRaw = appSettings["transparent_background"]
            var backgroundOn = root.backgroundOn(backgroundRaw)
            items.push({
                type: "slider",
                key: "transparent_background",
                label: "Transparent Background",
                on: backgroundOn,
                offValue: "Off",
                // Off, the bar waits where turning it on puts it.
                value: backgroundOn ? root.solidityOf(backgroundRaw) : 40,
                step: 10,
                startText: "TRANSPARENT",
                endText: "SOLID",
                description: "How much of a video shows through the menus when back returns to them and leaves it playing behind, until you play something else or stop it on the main menu, whose first row takes it back to full screen\n[SOLID] None of it, but it plays on, sound and all  [ENTER] On or off: off, back stops the video, as it always has",
                moduleId: ""
            })
        }

        // Video Output Range, the RGB range mpv converts YUV into. mpv's default
        // is full range; a display expecting studio (limited) levels renders that
        // as crushed blacks and blown whites, and the reverse reads as washed-out
        // gray. Takes effect on the next video.
        // The key keeps mpv's own name for the option; the label uses the wording
        // TVs and GPU drivers use for the same control (HDMI RGB range, DRM
        // "Broadcast RGB"), since that's what the setting is matching.
        items.push({
            type: "list_single",
            key: "video_output_levels",
            label: "Video Levels",
            options: ["Auto", "Limited", "Full"],
            value: appSettings["video_output_levels"] || "Auto",
            description: "Match the color range your display expects\n[LIMITED] If blacks crush  [FULL] If blacks look gray",
            moduleId: ""
        })

        // Loading Effect — the screen a video loads behind is a tape loading
        // (Components/LoadingScreen): its noise and tracking bands, or, off,
        // the deck's display alone on the plain background. Read in Main.qml.
        items.push({
            type: "list_single",
            key: "loading_effect",
            label: "Loading Effect",
            options: ["On", "Off"],
            value: appSettings["loading_effect"] === "Off" ? "Off" : "On",
            description: "While a video loads, a tape's noise and tracking bands roll over its counters\n[OFF] The counters alone, on the plain background",
            moduleId: ""
        })

        // SCREEN SAVER section — single control: OFF disables, a number sets the
        // timeout for both menu idle and playback pause (handled inside mpv).
        items.push({
            type: "list_single",
            key: "screensaver_timeout",
            label: "Screen Saver",
            options: ["OFF", "30", "60", "120"],
            value: appSettings["screensaver_timeout"] || "OFF",
            description: "Prevent CRT burn-in after seconds of inactivity or pause",
            moduleId: ""
        })

        // MOUSE POINTER — drawn by Main.qml: it shows as the mouse moves and
        // goes again after this many seconds without moving.
        var pointerVals = ["off", "2", "5", "10", "30", "always"]
        var pointerOpts = ["Off", "2 sec", "5 sec", "10 sec", "30 sec", "Always"]
        var pointerIdx = pointerVals.indexOf(appSettings["mouse_pointer"] || "5")
        items.push({
            type: "list_single",
            key: "mouse_pointer",
            label: "Mouse Pointer",
            options: pointerOpts,
            values: pointerVals,
            value: pointerOpts[pointerIdx < 0 ? pointerVals.indexOf("5") : pointerIdx],
            description: "A mouse's pointer shows as it moves, and goes again after these seconds without moving\n[OFF] Never shown  [ALWAYS] Stays on screen",
            moduleId: ""
        })

        // INFO SCREEN — a film's details in the trees (Netflix, Prime Video,
        // YouTube): with right on it always, and with a number also on its own
        // once the cursor has rested on it that many seconds. One control, like
        // the screen saver's.
        var infoVals = ["off", "key", "1", "2", "3", "5"]
        var infoOpts = ["Off", "Key", "1 sec", "2 sec", "3 sec", "5 sec"]
        var infoIdx = infoVals.indexOf(appSettings["info_screen"] || "3")
        items.push({
            type: "list_single",
            key: "info_screen",
            label: "Info Screen",
            options: infoOpts,
            values: infoVals,
            value: infoOpts[infoIdx < 0 ? infoVals.indexOf("3") : infoIdx],
            description: "A film's details in Netflix, Prime Video and YouTube\n[KEY] With right on a film  [SEC] Also on its own once the cursor rests on it",
            moduleId: ""
        })

        // MODULES section — only show modules with has_settings
        var hasModuleSettings = false
        for (var i = 0; i < installedModules.length; i++) {
            if (installedModules[i].has_settings) { hasModuleSettings = true; break }
        }

        if (hasModuleSettings) {
            items.push({ type: "section", label: "Modules" })
            for (var j = 0; j < installedModules.length; j++) {
                var m = installedModules[j]
                if (m.has_settings) {
                    items.push({ type: "submenu", label: m.name, moduleId: m.id })
                }
            }
        }

        // SYSTEM section
        items.push({ type: "section", label: "Application" })
        items.push({
            type: "submenu",
            key: "remap_controls",
            label: "Controls",
            moduleId: ""
        })
        // Pairing a Bluetooth keyboard, gamepad or remote (BlueZ, so Linux).
        if (bluetoothManager && bluetoothManager.supported) {
            items.push({
                type: "submenu",
                key: "bluetooth",
                label: "Bluetooth",
                moduleId: ""
            })
        }
        items.push({
            type: "submenu",
            key: "software_update",
            label: "Update",
            moduleId: ""
        })
        items.push({ type: "quit", label: "Quit" })

        settingsItems = items

        // Restore saved position, or default to first selectable row
        if (navListState.currentIndex !== undefined) {
            settingsList.currentIndex = Math.min(navListState.currentIndex, items.length - 1)
        } else {
            for (var k = 0; k < items.length; k++) {
                if (items[k].type !== "section") {
                    settingsList.currentIndex = k
                    break
                }
            }
        }
        settingsList.positionViewAtIndex(settingsList.currentIndex, ListView.Contain)
        settingsList.showWholeRows()
    }

    function firstSelectableAfter(idx) {
        for (var i = idx + 1; i < settingsItems.length; i++) {
            if (settingsItems[i].type !== "section") return i
        }
        return settingsList.currentIndex
    }

    function firstSelectableBefore(idx) {
        for (var i = idx - 1; i >= 0; i--) {
            if (settingsItems[i].type !== "section") return i
        }
        return settingsList.currentIndex
    }

    Component.onCompleted: buildModel()

    // Header
    AppBar {
        iconSource: "../../assets/images/settings.svg"
        title: "Settings"
        subtitle: root.appVersion
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // IP address
    property string ipAddress: ""
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: settingsRoot.ipAddress = appCore.localIpAddress()
    }
    Text {
        text: settingsRoot.ipAddress
        visible: settingsRoot.ipAddress !== ""
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.sh * 0.125 //60
        anchors.rightMargin: root.sw * 0.125 //80
        font.pixelSize: root.sh * 0.0291667 //14
        // On the title bar, so in the bar's text colour.
        color: root.surfaceColor
        font.family: root.globalFont
        font.capitalization: Font.AllUppercase
        topPadding: root.sh * 0.0125 //6
        rightPadding: root.sw * 0.00625 //4
    }

    ListView {
        id: settingsList
        model: settingsItems
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.25 //120
        anchors.leftMargin: root.sw * 0.115625 //74
        width: root.sw * 0.76875 //492
        // One row short of the space, so the ▼ fits above the help line.
        height: root.sh * 0.4666667 //224
        clip: true
        focus: true

        Keys.onUpPressed: {
            if (currentIndex > 0) currentIndex-- 
            else {
                currentIndex = settingsItems.length-1
            }
            while (settingsItems[currentIndex].type == "section") {
                currentIndex--
            }
            settingsList.positionViewAtIndex(currentIndex, ListView.Contain)
            showWholeRows()
        }
        Keys.onDownPressed: {
            if (currentIndex < count - 1) currentIndex++
            else currentIndex = 0
            while (settingsItems[currentIndex].type == "section") {
                currentIndex++
            }
            settingsList.positionViewAtIndex(currentIndex, ListView.Contain)
            showWholeRows()
        }

        // Rows are whole lines, a slider's several, so a scroll can stop with
        // a slider cut by an edge: carry on past it, keeping the current row.
        function showWholeRows() {
            var top = itemAt(0, contentY + 1)
            if (top && top !== currentItem && top.y < contentY - 1)
                contentY = Math.min(top.y + top.height, originY + contentHeight - height)
            var bottom = itemAt(0, contentY + height - 1)
            if (bottom && bottom !== currentItem && bottom.y + bottom.height > contentY + height + 1)
                contentY = Math.max(bottom.y - height, originY)
        }

        // The current row, changed, in place of the old one. A new model
        // starts the list from the top, so it is put back where it was.
        function replaceCurrentRow(row) {
            var updated = settingsItems.slice()
            updated[currentIndex] = row
            var savedIndex = currentIndex
            var savedY = contentY
            settingsItems = updated
            currentIndex = savedIndex
            contentY = savedY
        }

        // A slider's step toward one end (-1 left, 1 right), kept and saved.
        // One that is off turns on instead, where its bar waits.
        function moveSlider(direction) {
            var row = settingsItems[currentIndex]
            if (row.on === false) {
                toggleSlider()
                return
            }
            var v = Math.max(0, Math.min(100, row.value + direction * row.step))
            if (v === row.value)
                return
            replaceCurrentRow(Object.assign({}, row, { value: v }))
            appCore.save_setting(row.moduleId, row.key, v)
        }

        // A slider that can be off (one with `on`), turned off, saved as its
        // offValue, or back on at its value.
        function toggleSlider() {
            var row = settingsItems[currentIndex]
            var on = !row.on
            replaceCurrentRow(Object.assign({}, row, { on: on }))
            appCore.save_setting(row.moduleId, row.key, on ? row.value : row.offValue)
        }

        Keys.onLeftPressed: {
            var row = settingsItems[currentIndex]
            if (row && row.type === "slider") {
                moveSlider(-1)
            } else if (row && row.type === "list_single") {
                var opts = row.options
                var idx = opts.indexOf(row.value)
                var newIdx = (idx - 1 + opts.length) % opts.length
                var newVal = opts[newIdx]
                // Display the label; persist the parallel value when one exists.
                var savedVal = row.values ? row.values[newIdx] : newVal
                replaceCurrentRow(Object.assign({}, row, { value: newVal }))
                appCore.save_setting(row.moduleId, row.key, savedVal)
            }
        }

        Keys.onRightPressed: {
            var row = settingsItems[currentIndex]
            if (row && row.type === "slider") {
                moveSlider(1)
            } else if (row && row.type === "list_single") {
                var opts = row.options
                var idx = opts.indexOf(row.value)
                var newIdx = (idx + 1) % opts.length
                var newVal = opts[newIdx]
                // Display the label; persist the parallel value when one exists.
                var savedVal = row.values ? row.values[newIdx] : newVal
                replaceCurrentRow(Object.assign({}, row, { value: newVal }))
                appCore.save_setting(row.moduleId, row.key, savedVal)
            }
        }

        Keys.onReturnPressed: {
            var row = settingsItems[currentIndex]
            if (row && row.type === "submenu") {
                if (row.key === "software_update")
                    settingsRoot.navigateTo("views/Update.qml", {}, { currentIndex: settingsList.currentIndex })
                else if (row.key === "remap_controls")
                    settingsRoot.navigateTo("views/RemapControls.qml", {}, { currentIndex: settingsList.currentIndex })
                else if (row.key === "bluetooth")
                    settingsRoot.navigateTo("views/Bluetooth.qml", {}, { currentIndex: settingsList.currentIndex })
                else
                    settingsRoot.navigateTo("views/ModuleSettings.qml", { moduleId: row.moduleId }, { currentIndex: settingsList.currentIndex })
            } else if (row && row.type === "quit") {
                settingsRoot.quitChoiceIndex = 0
                settingsRoot.quitOverlayVisible = true
            } else if (row && row.type === "slider" && row.on !== undefined) {
                toggleSlider()
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                settingsRoot.goBack()
                event.accepted = true
            }
        }

        delegate: Item {
            id: rowItem
            readonly property bool slider: modelData.type === "slider"
            readonly property real lineHeight: root.sh * 0.0583333 //28
            // A slider's bar takes whole lines under its own, so every line
            // keeps to the list's rule as it scrolls.
            readonly property int barLines: slider ? Math.ceil((tape.height + 2 * root.px) / lineHeight) : 0
            width: settingsList.width
            height: lineHeight * (1 + barLines)

            // A line laid out like a camcorder's menu, "DISPLAY······ON", or a
            // section's heading, as large as the lines under it: "MODULES ─────".
            MenuRow {
                width: parent.width
                height: rowItem.lineHeight
                heading: modelData.type === "section"
                label: modelData.label || ""
                value: modelData.type === "list_single" ? (modelData.value || "")
                     : rowItem.slider && modelData.on !== undefined ? (modelData.on ? "On" : "Off") : ""
                selected: settingsList.currentIndex === index
            }

            // A slider's setting, as the deck's tape bar shows how far the
            // tape is: ◄ ► move the ▼ between the two ends. Off, its lines
            // stay, empty.
            Loader {
                id: tape
                active: rowItem.slider
                visible: modelData.on !== false
                x: root.sw * 0.009375 //6
                y: rowItem.lineHeight + Math.round((rowItem.barLines * rowItem.lineHeight - height) / 2)
                width: parent.width - 2 * x
                sourceComponent: OsdTapeBar {
                    fontSize: root.sh * 0.0333333 //16
                    value: modelData.value / 100
                    startText: modelData.startText
                    endText: modelData.endText
                }
            }
        }
    }

    // ▲ / ▼ while lines are hidden above or below.
    ScrollMarks {
        anchors.fill: settingsList
        list: settingsList
    }

    // --- HELP TEXT --- (shown when a focused row has a description), on one
    // line that scrolls when it is too long for the box.
    HelpLine {
        property var currentRow: settingsRoot.settingsItems[settingsList.currentIndex]
        visible: !!(currentRow && currentRow.description)
        text: (currentRow && currentRow.description) || ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1583333 //76
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // --- FOOTER ---
    HintBar {
        id: footer
        text: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.change + ":CHANGE " + root.hints.select + ":SELECT"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // --- QUIT CONFIRMATION OVERLAY ---
    PromptScreen {
        visible: quitOverlayVisible
        focus: quitOverlayVisible
        title: "Really quit?"
        choices: quitOptions
        currentIndex: quitChoiceIndex
        hint: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"

        Keys.onUpPressed:   { quitChoiceIndex = Math.max(0, quitChoiceIndex - 1) }
        Keys.onDownPressed: { quitChoiceIndex = Math.min(quitOptions.length - 1, quitChoiceIndex + 1) }
        Keys.onReturnPressed: {
            var act = quitOptions[quitChoiceIndex].action
            if (act === "quit")          Qt.quit()
            else if (act === "restart")  Qt.exit(12)   // 240mp-stop reboots on it
            else if (act === "terminal") Qt.exit(10)   // matches EXIT_STATUS check in 240mp-stop
            else { quitOverlayVisible = false; settingsList.forceActiveFocus() }
        }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                quitOverlayVisible = false
                settingsList.forceActiveFocus()
                event.accepted = true
            }
        }
    }
}
