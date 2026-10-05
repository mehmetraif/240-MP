import QtQuick

// The deck's segment bar, "||||||------": a full-height tick for every filled
// step and a dash for every empty one, laid on whole art pixels.
Item {
    id: ticks

    // 0 to 1: how many of the steps are filled.
    property real value: 0
    property int segments: 24
    property color color: root.primaryColor
    property int pixel: root.px

    // Each step's share of the width, in whole art pixels.
    readonly property int pitch: Math.max(2, Math.floor(width / segments / pixel)) * pixel
    readonly property int filled: Math.round(Math.max(0, Math.min(1, value)) * segments)

    implicitHeight: 4 * pixel

    Repeater {
        model: ticks.segments
        Rectangle {
            readonly property bool on: index < ticks.filled
            x: index * ticks.pitch
            // A tick takes about a third of its step; a dash leaves a gap
            // wide enough to read as separate dashes.
            width: on ? Math.max(ticks.pixel, Math.floor(ticks.pitch * 0.4 / ticks.pixel) * ticks.pixel)
                      : Math.max(ticks.pixel, ticks.pitch - 2 * ticks.pixel)
            height: on ? ticks.height : ticks.pixel
            y: on ? 0 : Math.floor(ticks.height / 2 / ticks.pixel) * ticks.pixel
            color: ticks.color
            antialiasing: false
        }
    }
}
