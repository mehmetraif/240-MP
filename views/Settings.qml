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
    // "Exit to Terminal" option that drops to a tty1 login without powering off; that
    // option is not needed on macOS/Desktop or when run by hand, so it's yes/no for that case.
    property bool autostartSession: false
    property var quitOptions: settingsRoot.autostartSession
        ? [{ label: "Power Off",        action: "quit"     },
           { label: "Exit to Terminal", action: "terminal" },
           { label: "Cancel",           action: "cancel"   }]
        : [{ label: "Yes", action: "quit" },
           { label: "No",  action: "cancel" }]

    function buildModel() {
        var cfg = appCore.get_settings()
        appSettings = cfg.app || {}
        installedModules = appCore.get_installed_modules()
        autostartSession = appCore.isAutostartSession()

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
                description: "[ON] Enable 1080p content playback, crop will not function\n[OFF] Enable crop, 1080p content playback will stutter",
                moduleId: ""
            })
        }

        // Auto Crop — default crop (panscan) state for every video. Off by default;
        // crop can still be toggled live during playback via the mpv OSC.
        items.push({
            type: "list_single",
            key: "auto_crop",
            label: "Auto Crop",
            options: ["Off", "On"],
            value: appSettings["auto_crop"] || "Off",
            description: "[ON] Video starts cropped to fill screen\n[OFF] Video starts at its original aspect ratio",
            moduleId: ""
        })

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
        }
        Keys.onDownPressed: {
            if (currentIndex < count - 1) currentIndex++
            else currentIndex = 0
            while (settingsItems[currentIndex].type == "section") {
                currentIndex++
            }
            settingsList.positionViewAtIndex(currentIndex, ListView.Contain)
        }

        Keys.onLeftPressed: {
            var row = settingsItems[currentIndex]
            if (row && row.type === "list_single") {
                var opts = row.options
                var idx = opts.indexOf(row.value)
                var newIdx = (idx - 1 + opts.length) % opts.length
                var newVal = opts[newIdx]
                // Display the label; persist the parallel value when one exists.
                var savedVal = row.values ? row.values[newIdx] : newVal
                var updated = settingsItems.slice()
                updated[currentIndex] = Object.assign({}, row, { value: newVal })
                var savedIndex = currentIndex
                settingsItems = updated
                currentIndex = savedIndex
                appCore.save_setting(row.moduleId, row.key, savedVal)
            }
        }

        Keys.onRightPressed: {
            var row = settingsItems[currentIndex]
            if (row && row.type === "list_single") {
                var opts = row.options
                var idx = opts.indexOf(row.value)
                var newIdx = (idx + 1) % opts.length
                var newVal = opts[newIdx]
                // Display the label; persist the parallel value when one exists.
                var savedVal = row.values ? row.values[newIdx] : newVal
                var updated = settingsItems.slice()
                updated[currentIndex] = Object.assign({}, row, { value: newVal })
                var savedIndex = currentIndex
                settingsItems = updated
                currentIndex = savedIndex
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
                else
                    settingsRoot.navigateTo("views/ModuleSettings.qml", { moduleId: row.moduleId }, { currentIndex: settingsList.currentIndex })
            } else if (row && row.type === "quit") {
                settingsRoot.quitChoiceIndex = 0
                settingsRoot.quitOverlayVisible = true
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                settingsRoot.goBack()
                event.accepted = true
            }
        }

        delegate: Item {
            width: settingsList.width
            height: root.sh * 0.0583333 //28

            // A line laid out like a camcorder's menu, "DISPLAY······ON", or a
            // section's heading, as large as the lines under it: "MODULES ─────".
            MenuRow {
                anchors.fill: parent
                heading: modelData.type === "section"
                label: modelData.label || ""
                value: modelData.type === "list_single" ? (modelData.value || "") : ""
                selected: settingsList.currentIndex === index
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
    Rectangle {
        anchors.fill: parent
        color: root.surfaceColor
        visible: quitOverlayVisible
        focus: quitOverlayVisible

        Keys.onUpPressed:   { quitChoiceIndex = Math.max(0, quitChoiceIndex - 1) }
        Keys.onDownPressed: { quitChoiceIndex = Math.min(quitOptions.length - 1, quitChoiceIndex + 1) }
        Keys.onReturnPressed: {
            var act = quitOptions[quitChoiceIndex].action
            if (act === "quit")          Qt.quit()
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

        Rectangle {
            color: root.surfaceColor
            anchors.centerIn: parent
            width: root.sw * 0.76875   //492
            height: root.sh * 0.2833333 //136

            Column {
                id: quitDialogColumn
                anchors.fill: parent
                spacing: root.sh * 0.05 //24

                Text {
                    text: "REALLY QUIT?"
                    color: root.secondaryColor
                    font.family: root.globalFont
                    font.pixelSize: root.sh * 0.0333333 //16
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Column {
                    Repeater {
                        model: quitOptions
                        delegate: Item {
                            width: quitDialogColumn.width
                            height: root.sh * 0.0583333 //28

                            Rectangle {
                                anchors.fill: quitOptionText
                                color: root.accentColor
                                visible: index === quitChoiceIndex
                            }

                            Text {
                                id: quitOptionText
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: index === quitChoiceIndex ? root.surfaceColor : root.primaryColor
                                font.family: root.globalFont
                                font.capitalization: Font.AllUppercase
                                topPadding: root.sh * 0.0041667 //2
                                leftPadding: root.sw * 0.009375 //6
                                rightPadding: root.sw * 0.009375 //6
                                bottomPadding: root.sh * 0.00625 //3
                                font.pixelSize: root.sh * 0.05 //24
                            }
                        }
                    }
                }

                HintBar {
                    text: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
