import QtQuick
import QtQuick.Effects

// The title bar every view starts with, the way a deck's on-screen menu does:
// the module's icon, its name and where you are in it, in the background colour
// on a solid bar.
Rectangle {
    id: appBar

    // Custom Properties
    property url iconSource: "../../assets/images/logo.svg"
    property string title: "240-MP"
    property string subtitle: ""

    // Fits the standard screen gutter — 80px (root.sw * 0.125) on each side.
    // The subtitle elides when it would overflow this width.
    width: root.sw * 0.75 //480
    height: content.height + 2 * root.px
    color: root.primaryColor
    antialiasing: false

    Row {
        id: content
        x: root.sw * 0.0125 //8
        width: appBar.width - 2 * x
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.sw * 0.025 //16

        Item {
            visible: appBar.iconSource !== ""
            width: iconImg.width
            anchors.verticalCenter: parent.verticalCenter
            height: root.sh * 0.05 //24
            Image {
                visible: false
                id: iconImg
                height: parent.height
                sourceSize.height: height
                source: appBar.iconSource
            }
            MultiEffect {
                anchors.fill: iconImg
                source: iconImg
                colorization: 1.0
                colorizationColor: root.surfaceColor
            }
        }

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
            // x is this Text's Row position, i.e. everything before it (icon,
            // title, separator, spacings) — cap to the bar's remaining space.
            elide: Text.ElideRight
            width: Math.max(0, Math.min(implicitWidth, content.width - x))
        }
    }
}
