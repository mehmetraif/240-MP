import QtQuick

// The deck's VOLUME bar: an outline with a solid fill one art pixel inside it.
Item {
    id: bar

    // 0 to 1: how much of the bar is filled.
    property real value: 0
    property color color: root.primaryColor
    property int pixel: root.px

    implicitHeight: 7 * pixel

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: bar.pixel
        border.color: bar.color
        antialiasing: false
    }
    Rectangle {
        x: 2 * bar.pixel
        y: 2 * bar.pixel
        height: bar.height - 4 * bar.pixel
        width: Math.round((bar.width - 4 * bar.pixel) * Math.max(0, Math.min(1, bar.value)) / bar.pixel) * bar.pixel
        color: bar.color
        antialiasing: false
    }
}
