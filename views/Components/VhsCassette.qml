import QtQuick

// The VHS cassette on the boot screen, the owner's drawing itself, made with
// ChatGPT (assets/images/cassette.png: white where the drawing is ink, with its own
// edges) in the theme's text colour, the slash on its label in its three
// colours. As `progress` goes from 0 to 1 the tape winds off the left
// (supply) reel onto the right (take-up) one: each window shows its reel's
// tape as a disc of the radius the progress gives, around the drawing's own
// hub, the shell showing where the tape has gone.
//
// The host sizes it (width and height), and the drawing is stretched to that,
// so on a screen whose pixels are not square (720×480 on a 4:3 tube) it
// keeps its shape on the glass.
Item {
    id: cassette

    // 0 = all of the tape on the left reel, 1 = all of it on the right.
    property real progress: 0
    // The one colour drawn; the host sets it to the theme's text colour.
    property color ink: "#ffffff"

    // The drawing's frame, and what the view needs of it, in its pixels.
    readonly property real artWidth: 612
    readonly property real artHeight: 284
    readonly property real reelY: 168
    readonly property real leftReelX: 149
    readonly property real rightReelX: 463.5
    // The tape's radius: full as drawn, and never down to the hub (51.5).
    readonly property real fullRadius: 121
    readonly property real emptyRadius: 57
    // Each window's tape, a little beyond it where the drawing is shell:
    // [x0, y0, x1, y1]. With a disc a little larger than the full reel,
    // it bounds what a reel's lost tape is covered in, short of the frame.
    readonly property var leftPack: [28, 94, 149, 236]
    readonly property var rightPack: [463, 94, 584, 236]
    readonly property real packRadius: fullRadius + 2.5
    // The slash on the label: three stripes `stripe` wide, from `slashX` on
    // its top row, a pixel to the left for every two rows down.
    readonly property real slashTop: 148
    readonly property real slashBottom: 188
    readonly property real slashX: 327
    readonly property real stripe: 5
    readonly property var slashColours: ["#ff3d3d", "#2f6bff", "#2fe063"]

    implicitWidth: artWidth
    implicitHeight: artHeight

    // Tape radius on a reel holding `share` of the tape. The tape's area is
    // conserved, so the radius follows the square root, not a straight line.
    function reelRadius(share) {
        var e = emptyRadius * emptyRadius
        var f = fullRadius * fullRadius
        return Math.sqrt(e + Math.max(0, Math.min(1, share)) * (f - e))
    }
    readonly property real leftRadius: reelRadius(1 - progress)
    readonly property real rightRadius: reelRadius(progress)

    // The shell over the tape a reel no longer holds: within its window, the
    // ring between the full reel and the disc its tape still fills.
    function coverTape(ctx, pack, cx, r) {
        if (r >= fullRadius)
            return
        ctx.save()
        ctx.beginPath()
        ctx.rect(pack[0], pack[1], pack[2] - pack[0], pack[3] - pack[1])
        ctx.clip()
        ctx.beginPath()
        ctx.arc(cx, reelY, packRadius, 0, 2 * Math.PI, false)
        ctx.moveTo(cx + r, reelY)
        ctx.arc(cx, reelY, r, 0, 2 * Math.PI, true)
        ctx.fill()
        ctx.restore()
    }

    Image {
        anchors.fill: parent
        sourceSize.width: width
        sourceSize.height: height
        source: width > 0 && height > 0
                ? "image://osdicon/" + cassette.ink.toString().replace("#", "")
                  + "/" + Qt.resolvedUrl("../../assets/images/cassette.png")
                : ""
    }

    // The tape and the slash, over the drawing, in its own pixels.
    Canvas {
        id: overlay
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.scale(width / cassette.artWidth, height / cassette.artHeight)
            ctx.fillRule = Qt.OddEvenFill
            ctx.fillStyle = cassette.ink
            cassette.coverTape(ctx, cassette.leftPack, cassette.leftReelX, cassette.leftRadius)
            cassette.coverTape(ctx, cassette.rightPack, cassette.rightReelX, cassette.rightRadius)
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
    onLeftRadiusChanged: overlay.requestPaint()
    onRightRadiusChanged: overlay.requestPaint()
    onInkChanged: overlay.requestPaint()
}
