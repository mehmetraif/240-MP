import QtQuick

// The ground the OSD is drawn on, as Settings' OSD BACKGROUND has it
// (root.osdBackground):
//   FULL    the colour scheme's background all over (the default);
//   WINDOW  a window of it behind what a view shows (root.osdWindow), framed
//           in the scheme's colour, black around it;
//   OFF     none: black, the menus in the scheme's lighter colour on it, as a
//           deck's OSD with nothing playing (root.surfaceColor is then black).
//
// Main.qml lays one under every view. A full-screen layer that hides the view
// under it (PromptScreen, the on-screen keyboard, an info screen) lays its own,
// so the window goes on under it just as it was. It is laid out in screen
// coordinates, in a layer that fills the screen: anchors.fill its area, or a
// strip of it (the keyboard's, below the title bar), and the window shows
// through that strip as it lies on the screen.
//
//     OsdGround { anchors.fill: parent }
Item {
    id: ground

    // Black around the window. Main.qml turns it off over a video playing
    // behind the menus, which then shows there whole.
    property bool surround: true

    readonly property bool windowed: root.osdBackground === "Window"
    clip: windowed

    Rectangle {
        anchors.fill: parent
        visible: !ground.windowed || ground.surround
        color: ground.windowed ? "#000000" : root.surfaceColor
    }

    // The window, framed: placed where it lies on the screen, whatever part of
    // the screen this ground covers.
    Rectangle {
        visible: ground.windowed
        x: root.osdWindow.x - ground.x
        y: root.osdWindow.y - ground.y
        width: root.osdWindow.width
        height: root.osdWindow.height
        color: root.surfaceColor
        border.color: root.primaryColor
        border.width: root.px
        antialiasing: false
    }
}
