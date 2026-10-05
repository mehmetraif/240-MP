import QtQuick

// The deck's TRACKING slider: a double outline with one mark that sits in the
// middle at 0 and moves out to either end at -1 and 1.
Item {
    id: slider

    property real value: 0
    property color color: root.primaryColor
    property int pixel: root.px

    implicitHeight: 7 * pixel

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: slider.pixel
        border.color: slider.color
        antialiasing: false
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2 * slider.pixel
        color: "transparent"
        border.width: slider.pixel
        border.color: slider.color
        antialiasing: false
    }
    Rectangle {
        readonly property real travel: (slider.width - 8 * slider.pixel) / 2
        x: Math.round((slider.width / 2 + Math.max(-1, Math.min(1, slider.value)) * travel) / slider.pixel) * slider.pixel
        y: 2 * slider.pixel
        width: slider.pixel
        height: slider.height - 4 * slider.pixel
        color: slider.color
        antialiasing: false
    }
}
