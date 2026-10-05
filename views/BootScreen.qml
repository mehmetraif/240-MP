import QtQuick
import Components

// Boot screen of the 240-MP OS image (os/README.md). The image puts the app on
// screen first and starts the services it held back afterwards, in the order
// it lists them; this shows them coming up while the cassette plays — the tape
// winds across in step with the progress bar. Any key closes it early; the
// services carry on in the background either way.
//
// Binds only to root.* (Main.qml mirrors bootProgress there), which stays
// valid while this Loader-hosted view is torn down.
FocusScope {
    id: bootRoot

    focus: true

    // Smoothed copy of the boot progress that drives both the bar and the tape.
    property real shownProgress: root.bootValue
    Behavior on shownProgress { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

    readonly property int unit: cassette.pixelSize

    // Cycles 0..3 for the "..." after whatever is starting.
    property int dots: 0
    Timer {
        interval: 400
        repeat: true
        running: bootRoot.visible
        onTriggered: bootRoot.dots = (bootRoot.dots + 1) % 4
    }

    function marker(state) {
        switch (state) {
        case "done":    return "[ OK ]"
        case "failed":  return "[FAIL]"
        case "skipped": return "[ -- ]"
        case "running": return "[" + [" .  ", " .. ", " ...", "    "][bootRoot.dots] + "]"
        default:        return "[    ]"
        }
    }

    function markerColor(state) {
        switch (state) {
        case "done":    return root.primaryColor
        case "running":
        case "failed":  return root.accentColor
        default:        return root.tertiaryColor
        }
    }

    Keys.onPressed: function(event) {
        event.accepted = true
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Q) {
            Qt.quit()
            return
        }
        root.skipBootScreen()
    }

    Rectangle {
        anchors.fill: parent
        color: root.surfaceColor
    }

    // The deck's own on-screen display while a tape plays, inside the same
    // overscan-safe gutter as every other view.
    Text {
        text: "PLAY ▶"
        color: root.primaryColor
        font.family: root.globalFont
        font.pixelSize: root.sh * 0.0416667 //20
        x: root.sw * 0.125 //80
        y: root.sh * 0.125 //60
    }

    VhsCassette {
        id: cassette
        // Roughly a third of the screen height, in whole art pixels.
        pixelSize: Math.max(1, Math.floor(root.sh * 0.36 / gridHeight))
        ink: root.primaryColor
        x: Math.round((root.sw - width) / 2)
        y: Math.round(root.sh * 0.16)
        progress: bootRoot.shownProgress
    }

    // Segmented bar in the cassette's own pixel grid: 24 blocks of 3 art
    // pixels with a 1-pixel gap span the cassette's 96-pixel width exactly.
    Item {
        id: bar
        readonly property int segments: 24
        x: cassette.x
        y: cassette.y + cassette.height + bootRoot.unit * 7
        width: cassette.width
        height: bootRoot.unit * 3

        Repeater {
            model: bar.segments
            Rectangle {
                x: index * bootRoot.unit * 4
                width: bootRoot.unit * 3
                height: bar.height
                antialiasing: false
                color: index < Math.round(bootRoot.shownProgress * bar.segments) ? root.accentColor : root.tertiaryColor
            }
        }
    }

    Text {
        id: status
        anchors.left: bar.left
        y: bar.y + bar.height + bootRoot.unit * 4
        text: root.bootLabel !== "" ? "LOADING " + root.bootLabel + "...".substr(0, bootRoot.dots) : "READY"
        color: root.primaryColor
        font.family: root.globalFont
        font.capitalization: Font.AllUppercase
        font.pixelSize: root.sh * 0.0333333 //16
    }

    Text {
        anchors.right: bar.right
        anchors.baseline: status.baseline
        text: Math.round(bootRoot.shownProgress * 100) + "%"
        color: root.accentColor
        font.family: root.globalFont
        font.pixelSize: root.sh * 0.0333333 //16
    }

    // One line per service, in the order the image starts them.
    Column {
        anchors.left: bar.left
        anchors.top: status.bottom
        anchors.topMargin: bootRoot.unit * 3
        spacing: root.sh * 0.004

        Repeater {
            model: root.bootSteps
            Text {
                text: bootRoot.marker(modelData.state) + " " + modelData.label
                color: bootRoot.markerColor(modelData.state)
                font.family: root.globalFont
                font.capitalization: Font.AllUppercase
                font.pixelSize: root.sh * 0.0291667 //14
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: root.sw * 0.125 //80
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.sh * 0.1041667 //50
        text: root.hints.select + ":SKIP"
        color: root.tertiaryColor
        font.family: root.globalFont
        font.pixelSize: root.sh * 0.0333333 //16
    }
}
