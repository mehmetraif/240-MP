import QtQuick
import Components

// ABOUT, from Settings: the wordmark with its tagline, then what OSD/OS is
// made of, who makes it and under which licence, as menu lines whose help
// line carries each one's detail (it stays whatever Settings' HELP LINE says:
// these lines are the page). Behind the LICENSE line is the licence itself: the notice the GNU
// GPL asks an interactive program to show (whose copyright, no warranty, the
// freedom to pass it on, where the licence is), then the licence's text, the
// LICENSE file every build carries next to the app (appCore.licenseText()),
// a page at a time.
FocusScope {
    id: aboutRoot

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    property var navParams: ({})
    property var navListState: ({})

    // Who makes OSD/OS, and whose work it carries on.
    readonly property string developer: "Mehmet Raif"
    readonly property string developerUrl: "github.com/mehmetraif"
    readonly property string sourceUrl: "github.com/mehmetraif/OSD-OS"
    readonly property string upstreamAuthor: "Anthony Caccese"
    readonly property string upstreamUrl: "github.com/anthonycaccese/240-MP"
    readonly property string year: "2026"

    readonly property var rows: [
        { key: "build", label: "Build", value: root.appBuild,
          description: "Version " + root.appVersion + " • The commit this build was made from, and the day"
                       + " • A retro VHS-style media player for CRT televisions, on a Raspberry Pi or a Mac" },
        { key: "developer", label: "Developer", value: aboutRoot.developer,
          description: "OSD/OS is developed by " + aboutRoot.developer + " • " + aboutRoot.developerUrl },
        { key: "upstream", label: "Based On", value: "240-MP",
          description: "240-MP by " + aboutRoot.upstreamAuthor + " and its contributors, " + aboutRoot.upstreamUrl
                       + " • OSD/OS is a modified version of it, from " + aboutRoot.year + ", under the same license" },
        { key: "license", label: "License", value: "GNU GPL v3",
          description: "Free software under the GNU General Public License, version 3: use it, share it and change it, under the same license"
                       + " • It comes with no warranty • " + root.hints.select + " The notice and the license's text" },
        { key: "source", label: "Source", value: aboutRoot.sourceUrl,
          description: "The source code, the releases and the issues • Changes are welcome: see CONTRIBUTING.md there" },
        { key: "fonts", label: "Fonts", value: "VCR OSD Mono, Unifont",
          description: "VCR OSD Mono by Riciery Santos Leal (mrmanet), free from dafont.com"
                       + " • GNU Unifont by Roman Czyborra, Paul Hardy and others, under the SIL Open Font License 1.1" },
        { key: "built", label: "Built With", value: "Qt, SDL2, mpv",
          description: "Qt 6 (LGPL v3) • SDL2 (zlib) • mpv and libmpv (GPL v2+)"
                       + " • On the OSD/OS image: yt-dlp (Unlicense), Deno (MIT), FFmpeg (LGPL/GPL), Chromium (BSD), Raspberry Pi OS" }
    ]

    // The notice at the head of the licence page: the GPL's own, for this
    // program.
    readonly property string notice:
        "OSD/OS " + root.appVersion + "\n"
        + "Copyright (C) " + aboutRoot.year + " " + aboutRoot.developer + "\n"
        + "A modified version of 240-MP, Copyright (C) " + aboutRoot.year + " " + aboutRoot.upstreamAuthor
        + " and the 240-MP contributors (" + aboutRoot.upstreamUrl + ").\n\n"
        + "This program is free software: you can redistribute it and/or modify it under the terms of the"
        + " GNU General Public License as published by the Free Software Foundation, version 3.\n\n"
        + "This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;"
        + " without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE."
        + " See the GNU General Public License below for more details, or at gnu.org/licenses/gpl-3.0.html."

    AppBar {
        iconSource: "../../assets/images/logo.svg"
        title: "About"
        subtitle: licensePage.visible ? "License" : root.appVersion
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // The wordmark, as on the logo: the letters in the scheme's colour, the
    // slash in its own three, and SMART TV FOR CRTS under a rule, in the
    // deck's own letters so a CRT reads it.
    Item {
        id: mark
        visible: !licensePage.visible
        x: root.sw * 0.125 //80
        y: root.sh * 0.2083333 //100
        width: root.sw * 0.75 //480
        height: tagline.y + tagline.height

        Image {
            id: letters
            anchors.horizontalCenter: parent.horizontalCenter
            height: root.sh * 0.075 //36
            width: implicitWidth
            sourceSize.height: height
            source: "image://osdicon/" + root.primaryColor.toString().replace("#", "")
                    + "/" + Qt.resolvedUrl("../assets/images/logo-wordmark.svg")
        }
        // The slash over the letters' own, in its colours: the same frame.
        Image {
            anchors.fill: letters
            sourceSize.width: letters.width
            sourceSize.height: letters.height
            source: "../assets/images/logo-slash.svg"
        }
        Rectangle {
            id: rule
            anchors.horizontalCenter: parent.horizontalCenter
            y: letters.height + root.px * 4
            width: Math.round(letters.width * 1.15)
            height: root.px
            color: root.primaryColor
            antialiasing: false
        }
        Text {
            id: tagline
            anchors.horizontalCenter: parent.horizontalCenter
            y: rule.y + rule.height + root.px * 3
            text: "SMART TV FOR CRTS"
            color: root.primaryColor
            font.family: root.globalFont
            font.pixelSize: root.sh * 0.0291667 //14
            font.letterSpacing: root.px * 2
        }
    }

    MenuList {
        id: list
        model: aboutRoot.rows
        visible: !licensePage.visible
        focus: !licensePage.visible
        // Under the wordmark: six lines, the rest on ▼.
        anchors.topMargin: root.sh * 0.3583333 //172
        height: root.sh * 0.35 //168

        delegate: MenuRow {
            width: list.width
            height: root.sh * 0.0583333 //28
            label: modelData.label
            value: modelData.value
            selected: list.currentIndex === index
        }

        Keys.onReturnPressed: {
            var row = aboutRoot.rows[currentIndex]
            if (row && row.key === "license")
                licensePage.open()
        }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                aboutRoot.goBack()
                event.accepted = true
            }
        }
    }

    HelpLine {
        readonly property var row: aboutRoot.rows[list.currentIndex]
        always: true
        visible: !licensePage.visible
        text: row ? row.description : ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1583333 //76
        anchors.leftMargin: root.sw * 0.125 //80
    }

    HintBar {
        readonly property var row: aboutRoot.rows[list.currentIndex]
        visible: !licensePage.visible
        text: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE"
              + (row && row.key === "license" ? " " + root.hints.select + ":LICENSE" : "")
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // The licence, in place of the lines below the title bar: the notice,
    // then the text, a page at a time with ▲ ▼.
    FocusScope {
        id: licensePage
        anchors.fill: parent
        visible: false

        // The text, read once it is first asked for.
        property string text: ""

        function open() {
            if (text === "") {
                var t = appCore ? appCore.licenseText() : ""
                text = t !== "" ? t
                     : "The license's text is missing from this build. It is at gnu.org/licenses/gpl-3.0.html."
            }
            flick.contentY = 0
            visible = true
            forceActiveFocus()
        }
        function close() {
            visible = false
            list.forceActiveFocus()
        }

        Keys.onUpPressed: flick.scrollBy(-1)
        Keys.onDownPressed: flick.scrollBy(1)
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                licensePage.close()
                event.accepted = true
            }
        }

        // Everything under the title bar, on the ground every view has.
        OsdGround {
            y: root.sh * 0.1916667 //92
            width: parent.width
            height: parent.height - y
        }

        Rectangle {
            id: page
            x: root.sw * 0.125 //80
            y: root.sh * 0.25 //120
            width: root.sw * 0.75 //480
            // Down to just above the hint bar, the help line's room included.
            height: root.sh * 0.575 //276
            color: "transparent"
            border.width: root.px
            border.color: root.primaryColor
            antialiasing: false

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: root.sw * 0.009375 //6
                contentHeight: column.height
                clip: true

                // A page at a time, with a little of the last one kept.
                function scrollBy(direction) {
                    var step = height * 0.8
                    var maxY = Math.max(0, contentHeight - height)
                    contentY = Math.max(0, Math.min(maxY, contentY + direction * step))
                }

                Column {
                    id: column
                    width: flick.width
                    spacing: root.sh * 0.0291667 //14

                    Text {
                        width: parent.width
                        text: aboutRoot.notice
                        textFormat: Text.PlainText
                        color: root.primaryColor
                        font.family: root.globalFont
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        font.pixelSize: root.sh * 0.0333333 //16
                    }
                    Text {
                        width: parent.width
                        text: licensePage.text
                        textFormat: Text.PlainText
                        color: root.primaryColor
                        font.family: root.globalFont
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        font.pixelSize: root.sh * 0.0291667 //14
                    }
                }
            }
        }

        ScrollMarks {
            anchors.fill: page
            list: flick
        }

        HintBar {
            text: root.hints.back + ":BACK " + root.hints.navigate + ":SCROLL"
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.bottomMargin: root.sh * 0.1041667 //50
            anchors.leftMargin: root.sw * 0.125 //80
        }
    }
}
