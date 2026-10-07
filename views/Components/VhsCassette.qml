import QtQuick

// The VHS cassette on the boot screen, the owner's drawing itself, made with
// ChatGPT (assets/images/cassette.png: white where the drawing is ink, with its
// own edges) in the theme's text colour, the slash on its label in its three
// colours. It is the logo, so it is drawn as it is, the tape in both windows
// as the drawing has it: the boot's progress shows in the bar under it.
//
// The host sizes it (width and height), and the drawing is stretched to that,
// so on a screen whose pixels are not square (720×480 on a 4:3 tube) it
// keeps its shape on the glass.
Item {
    id: cassette

    // The one colour drawn; the host sets it to the theme's text colour.
    property color ink: "#ffffff"

    // The drawing's frame, in its pixels.
    readonly property real artWidth: 612
    readonly property real artHeight: 284
    // The slash on the label: three stripes `stripe` wide, from `slashX` on
    // its top row, a pixel to the left for every two rows down.
    readonly property real slashTop: 148
    readonly property real slashBottom: 188
    readonly property real slashX: 327
    readonly property real stripe: 5
    readonly property var slashColours: ["#ff3d3d", "#2f6bff", "#2fe063"]

    implicitWidth: artWidth
    implicitHeight: artHeight

    Image {
        anchors.fill: parent
        sourceSize.width: width
        sourceSize.height: height
        source: width > 0 && height > 0
                ? "image://osdicon/" + cassette.ink.toString().replace("#", "")
                  + "/" + Qt.resolvedUrl("../../assets/images/cassette.png")
                : ""
    }

    // The slash, over the drawing, in its own pixels.
    Canvas {
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.scale(width / cassette.artWidth, height / cassette.artHeight)
            var drop = (cassette.slashBottom - cassette.slashTop) / 2
            for (var i = 0; i < 3; ++i) {
                var x = cassette.slashX + i * cassette.stripe
                ctx.fillStyle = cassette.slashColours[i]
                ctx.beginPath()
                ctx.moveTo(x, cassette.slashTop)
                ctx.lineTo(x + cassette.stripe, cassette.slashTop)
                ctx.lineTo(x + cassette.stripe - drop, cassette.slashBottom)
                ctx.lineTo(x - drop, cassette.slashBottom)
                ctx.closePath()
                ctx.fill()
            }
        }
    }
}
