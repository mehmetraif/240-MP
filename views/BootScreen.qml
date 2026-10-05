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

    // The text runs as wide as the cassette: the longest service line sets its
    // size, kept within what a CRT reads comfortably.
    FontMetrics {
        id: probe
        font.family: root.globalFont
        font.pixelSize: 100
    }
    readonly property string longestLine: {
        var line = "[ OK ] READY"
        for (var i = 0; i < root.bootSteps.length; ++i) {
            var candidate = "[ OK ] " + root.bootSteps[i].label
            if (candidate.length > line.length)
                line = candidate
        }
        return line.toUpperCase()
    }
    readonly property real textSize: Math.max(root.sh * 0.0375, Math.min(root.sh * 0.0583333,
        Math.floor(100 * cassette.width / probe.advanceWidth(longestLine))))

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
    Row {
        x: root.sw * 0.125 //80
        y: root.sh * 0.125 //60
        spacing: root.sw * 0.0125 //8
        Text {
            id: playLabel
            text: "PLAY"
            color: root.primaryColor
            font.family: root.globalFont
            font.pixelSize: root.sh * 0.0416667 //20
        }
        PixelIcon {
            name: "play"
            color: root.primaryColor
            anchors.verticalCenter: playLabel.verticalCenter
        }
    }

    VhsCassette {
        id: cassette
        // Under a third of the screen height, in whole art pixels.
        pixelSize: Math.max(1, Math.floor(root.sh * 0.3 / gridHeight))
        ink: root.primaryColor
        x: Math.round((root.sw - width) / 2)
        y: Math.round(root.sh * 0.14)
        progress: bootRoot.shownProgress
    }

    // The deck's segment bar in the cassette's own pixel grid: 20 steps of 4
    // art pixels span the cassette's 80-pixel width exactly.
    OsdTicks {
        id: bar
        x: cassette.x
        y: cassette.y + cassette.height + bootRoot.unit * 5
        width: cassette.width
        height: bootRoot.unit * 4
        pixel: bootRoot.unit
        segments: 20
        value: bootRoot.shownProgress
    }

    Text {
        id: status
        anchors.left: bar.left
        y: bar.y + bar.height + bootRoot.unit * 3
        text: root.bootLabel !== "" ? "LOADING" + "...".substr(0, bootRoot.dots) : "READY"
        color: root.primaryColor
        font.family: root.globalFont
        font.pixelSize: bootRoot.textSize
    }

    Text {
        anchors.right: bar.right
        anchors.baseline: status.baseline
        text: Math.round(bootRoot.shownProgress * 100) + "%"
        color: root.primaryColor
        font.family: root.globalFont
        font.pixelSize: bootRoot.textSize
    }

    // One line per service, in the order the image starts them; the one
    // starting now is inverted, like a deck's menu marks what is selected.
    Column {
        anchors.left: bar.left
        anchors.top: status.bottom
        anchors.topMargin: bootRoot.unit * 2

        Repeater {
            model: root.bootSteps
            Item {
                readonly property bool starting: modelData.state === "running"
                width: line.implicitWidth
                height: line.implicitHeight
                Rectangle {
                    anchors.fill: parent
                    visible: parent.starting
                    color: root.primaryColor
                    antialiasing: false
                }
                Text {
                    id: line
                    text: bootRoot.marker(modelData.state) + " " + modelData.label
                    color: parent.starting ? root.surfaceColor : root.primaryColor
                    font.family: root.globalFont
                    font.capitalization: Font.AllUppercase
                    font.pixelSize: bootRoot.textSize
                }
            }
        }
    }

    HintBar {
        anchors.left: parent.left
        anchors.leftMargin: root.sw * 0.125 //80
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.sh * 0.1041667 //50
        text: root.hints.select + ":SKIP"
    }
}
