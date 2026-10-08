import QtQuick

// The ground the OSD is drawn on, as Settings' OSD BACKGROUND has it
// (root.osdBackground):
//   FULL    the colour scheme's background all over (the default);
//   WINDOW  a window of it behind what a view shows (root.osdWindow), black
//           around it, framed as Settings' WINDOW FRAME has it
//           (root.osdFrame): ON a line in the scheme's colour, or the theme's
//           frame (Settings → Theme, root.theme.window); OFF none; SHADOW the
//           frame and a shadow below and to the right, like a DOS window's;
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
    readonly property bool framed: root.osdFrame !== "Off"
    // A DOS window's shadow, a few art pixels deep both ways, dithered: it
    // darkens the video it falls on, every other art pixel black; on the black
    // around the window, where there is nothing to darken, it is a half tone
    // of the window's colour instead.
    readonly property bool shadowed: windowed && root.osdFrame === "Shadow"
    readonly property real shadowDepth: 6 * root.px

    clip: windowed

    Rectangle {
        anchors.fill: parent
        visible: !ground.windowed || ground.surround
        color: ground.windowed ? "#000000" : root.surfaceColor
    }

    // The shadow's two arms, down the window's right side and along its foot
    // (only those: over a video the window lets the picture through), one
    // checkerboard across both.
    Repeater {
        model: ground.shadowed ? [
            Qt.rect(root.osdWindow.x + root.osdWindow.width, root.osdWindow.y + ground.shadowDepth,
                    ground.shadowDepth, root.osdWindow.height),
            Qt.rect(root.osdWindow.x + ground.shadowDepth, root.osdWindow.y + root.osdWindow.height,
                    root.osdWindow.width - ground.shadowDepth, ground.shadowDepth)
        ] : []
        Dither {
            required property rect modelData
            x: modelData.x - ground.x
            y: modelData.y - ground.y
            width: modelData.width
            height: modelData.height
            color: ground.surround ? root.surfaceColor : "#000000"
            phase: Math.round(modelData.x / root.px + modelData.y / root.px) % 2
        }
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
        border.width: ground.framed && !themedFrame.shown ? root.px : 0
        antialiasing: false

        ThemeImage {
            id: themedFrame
            anchors.fill: parent
            visible: ground.framed
            part: root.theme.window
        }
    }
}
