import QtQuick

// The footer every view carries: its hint line in the background colour on a
// solid bar across the screen's safe width, the way a deck's menu ends with
// "SELECT WITH (▲▼) AND (OK)". It is a Text, so a view sets its text, font and
// anchors exactly as on one.
Text {
    // The safe width, or more for a hint line longer than that, which runs on
    // into the gutter as the plain footers did.
    width: Math.max(root.sw * 0.75, implicitWidth) //480
    color: root.surfaceColor
    leftPadding: root.sw * 0.0125 //8
    rightPadding: root.sw * 0.0125 //8
    topPadding: root.px
    bottomPadding: root.px

    Rectangle {
        z: -1
        anchors.fill: parent
        color: root.primaryColor
        antialiasing: false
    }
}
