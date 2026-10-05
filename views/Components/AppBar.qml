import QtQuick

// The title bar every view starts with, the way a deck's on-screen menu does:
// the module's logo, then a solid bar with its name and where you are in it in
// the background colour. The logo is in the bar's colour, a fifth taller than
// the bar so it stands out of it above and below, with an art pixel of space
// either side of it.
Item {
    id: appBar

    // Custom Properties
    property url iconSource: "../../assets/images/logo.svg"
    property string title: "240-MP"
    property string subtitle: ""

    readonly property bool hasLogo: iconSource.toString() !== "" && logo.status === Image.Ready
    // A fifth taller than the bar, in whole art pixels.
    readonly property real logoHeight: Math.round(height * 1.2 / root.px) * root.px

    // Fits the standard screen gutter — 80px (root.sw * 0.125) on each side.
    // The subtitle elides when it would overflow this width.
    width: root.sw * 0.75 //480
    height: content.height + 2 * root.px

    // The logo's own ground, the background colour: through the gaps in its
    // drawing, a video playing behind the menus would show otherwise.
    Rectangle {
        visible: appBar.hasLogo
        x: logo.x
        y: logo.y
        width: logo.width
        height: logo.height
        color: root.surfaceColor
        antialiasing: false
    }

    Image {
        id: logo
        visible: appBar.hasLogo
        x: root.px
        y: Math.round((appBar.height - height) / 2)
        height: appBar.logoHeight
        width: implicitWidth
        sourceSize.height: appBar.logoHeight
        // Drawn by OsdIconProvider in the bar's colour, from the original at
        // this height. Resolved here, so a path relative to this file works as
        // it always has.
        source: appBar.iconSource.toString() !== "" && appBar.logoHeight > 0
                ? "image://osdicon/" + root.primaryColor.toString().replace("#", "")
                  + "/" + Qt.resolvedUrl(appBar.iconSource)
                : ""
    }

    Rectangle {
        id: bar
        x: appBar.hasLogo ? logo.x + logo.width + root.px : 0
        width: appBar.width - x
        height: appBar.height
        color: root.primaryColor
        antialiasing: false

        Row {
            id: content
            x: root.sw * 0.0125 //8
            width: bar.width - 2 * x
            // A line of title text, subtitle or not.
            height: Math.max(implicitHeight, root.sh * 0.05) //24
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.sw * 0.025 //16

            Text {
                text: appBar.title
                color: root.surfaceColor
                font.family: root.globalFont
                font.capitalization: Font.AllUppercase
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: root.sh * 0.05 //24
            }

            Rectangle {
                visible: appBar.subtitle !== ""
                color: root.surfaceColor
                anchors.verticalCenter: parent.verticalCenter
                width: root.px
                height: root.sh * 0.05 //24
                antialiasing: false
            }

            Text {
                text: appBar.subtitle
                color: root.surfaceColor
                font.family: root.globalFont
                font.capitalization: Font.AllUppercase
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: root.sh * 0.0333333 //16
                // x is this Text's Row position, i.e. everything before it
                // (title, separator, spacings) — cap to the bar's remaining space.
                elide: Text.ElideRight
                width: Math.max(0, Math.min(implicitWidth, content.width - x))
            }
        }
    }
}
