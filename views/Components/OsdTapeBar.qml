import QtQuick

// The deck's tape position bar: a ▼ over where the tape is, a ruled bar filled
// from the start of the tape up to there, and BEGIN and END under its ends.
Item {
    id: tape

    // 0 to 1: how far into the tape.
    property real value: 0
    property color color: root.primaryColor
    property int pixel: root.px
    property real fontSize: root.sh * 0.0416667 //20
    property int rules: 8

    readonly property int barHeight: 7 * pixel
    readonly property real at: Math.max(0, Math.min(1, value))
    readonly property int fillWidth: Math.round((width - 2 * pixel) * at / pixel) * pixel

    implicitHeight: marker.height + pixel + barHeight + endLabel.implicitHeight

    PixelIcon {
        id: marker
        name: "down"
        color: tape.color
        pixel: tape.pixel
        x: Math.round((tape.pixel + tape.fillWidth - width / 2) / tape.pixel) * tape.pixel
    }

    Item {
        id: bar
        y: marker.height + tape.pixel
        width: tape.width
        height: tape.barHeight

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: tape.pixel
            border.color: tape.color
            antialiasing: false
        }
        Rectangle {
            x: tape.pixel
            y: tape.pixel
            width: tape.fillWidth
            height: bar.height - 2 * tape.pixel
            color: tape.color
            antialiasing: false
        }
        // Rules hang from the top edge at even steps along the tape.
        Repeater {
            model: tape.rules - 1
            Rectangle {
                x: Math.round(bar.width * (index + 1) / tape.rules / tape.pixel) * tape.pixel
                y: tape.pixel
                width: tape.pixel
                height: 2 * tape.pixel
                color: tape.color
                antialiasing: false
            }
        }
    }

    Text {
        anchors.top: bar.bottom
        anchors.left: bar.left
        text: "BEGIN"
        color: tape.color
        font.family: root.globalFont
        font.pixelSize: tape.fontSize
    }
    Text {
        id: endLabel
        anchors.top: bar.bottom
        anchors.right: bar.right
        text: "END"
        color: tape.color
        font.family: root.globalFont
        font.pixelSize: tape.fontSize
    }
}
