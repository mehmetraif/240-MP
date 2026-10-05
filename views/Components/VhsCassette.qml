import QtQuick

// Pixel-art VHS cassette, drawn after the flat two-tone cassette icon: a dark
// shell with a light line under its top edge, a label with three lines in the
// middle and, either side of it, the tape wound on a reel around a dark hub.
// As `progress` goes from 0 to 1 the tape winds off the left (supply) reel onto
// the right (take-up) one, so the left pack shrinks while the right one grows.
// Each reel turns at the speed its tape radius gives it, the full reel slowly
// and the nearly empty one fast, like a real deck.
//
// The art lives on a fixed gridWidth × gridHeight grid and every grid cell is
// drawn as a pixelSize × pixelSize block, so the picture stays crisp at any
// integer scale (and a single-pixel line never lands on one interlaced CRT
// field). The shell and label are painted once; only the two reel windows are
// repainted per tick.
Item {
    id: cassette

    // Screen pixels per art pixel. The host derives it from root.sh.
    property int pixelSize: 3
    // 0 = all of the tape on the left reel, 1 = all of it on the right.
    property real progress: 0
    property bool running: visible

    readonly property int gridWidth: 96
    readonly property int gridHeight: 56

    width: gridWidth * pixelSize
    height: gridHeight * pixelSize

    // --- Palette: the icon's two tones ---
    readonly property string shell: "#232327"
    readonly property string paper: "#f1eee6"

    // --- Geometry (grid cells, inclusive bounds) ---
    // The light line that splits the top edge off the rest of the shell.
    readonly property int lineY0: 8
    readonly property int lineY1: 10
    // The label, and the rows and span of its three lines.
    readonly property int labelX0: 28
    readonly property int labelX1: 67
    readonly property int labelY0: 23
    readonly property int labelY1: 47
    readonly property var labelLines: [29, 35, 41]
    readonly property int labelLineX0: 32
    readonly property int labelLineX1: 63
    // The tape shows level with the label, beyond a 2-cell gap on either side
    // of it: columns 0..25 and 70..95. Only these two windows are repainted.
    readonly property int windowWidth: labelX0 - 2
    readonly property int windowHeight: labelY1 - labelY0 + 1
    // Reel centres sit on the label's edges, so the gap and the label hide
    // the inner half of each reel, as on the icon.
    readonly property real leftReelX: 27
    readonly property real rightReelX: gridWidth - leftReelX
    readonly property real reelY: (labelY0 + labelY1 + 1) / 2
    // Radii that rest on screen are kept off half-integers: those leave a
    // one-cell nub on the circle's outer edge.
    readonly property real hubRadius: 8.3
    readonly property real toothRadius: 5.5
    readonly property real emptyRadius: 10   // a reel never shows bare hub
    readonly property real fullRadius: 23.4
    // Linear tape speed in grid cells per second; each reel's angular speed is
    // this over its current tape radius.
    readonly property real tapeSpeed: 24

    // Tape radius on each reel for the current progress. The tape's area is
    // conserved, so the radii follow the square root, not a straight line.
    function reelRadius(share) {
        var e = emptyRadius * emptyRadius
        var f = fullRadius * fullRadius
        return Math.sqrt(e + Math.max(0, Math.min(1, share)) * (f - e))
    }
    readonly property real leftRadius:  reelRadius(1 - progress)
    readonly property real rightRadius: reelRadius(progress)

    property real leftAngle: 0
    property real rightAngle: 0

    // Paints `w` × `h` cells through colorAt(x, y), merging horizontal runs of
    // one colour into a single fillRect; "" leaves a cell transparent.
    function paintCells(ctx, w, h, colorAt) {
        var s = pixelSize
        for (var y = 0; y < h; ++y) {
            var start = 0
            var current = colorAt(0, y)
            for (var x = 1; x <= w; ++x) {
                var c = x < w ? colorAt(x, y) : null
                if (c === current)
                    continue
                if (current) {
                    ctx.fillStyle = current
                    ctx.fillRect(start * s, y * s, (x - start) * s, s)
                }
                start = x
                current = c
            }
        }
    }

    // True for the cells a corner of `size` cells cuts off the given box.
    function cornerCut(x, y, x0, y0, x1, y1, size) {
        return (x - x0) + (y - y0) < size || (x1 - x) + (y - y0) < size
            || (x - x0) + (y1 - y) < size || (x1 - x) + (y1 - y) < size
    }

    function shellColor(x, y) {
        if (cornerCut(x, y, 0, 0, gridWidth - 1, gridHeight - 1, 2))
            return ""
        if (y >= lineY0 && y <= lineY1)
            return paper
        if (y >= labelY0 && y <= labelY1) {
            // The reel windows, left to their own layer.
            if (x < windowWidth || x >= gridWidth - windowWidth)
                return ""
            if (x >= labelX0 && x <= labelX1) {
                if (cornerCut(x, y, labelX0, labelY0, labelX1, labelY1, 1))
                    return shell
                if (labelLines.indexOf(y) >= 0 && x >= labelLineX0 && x <= labelLineX1)
                    return shell
                return paper
            }
        }
        return shell
    }

    // Colours the reel window that starts at column x0, for a reel centred on
    // column cx: tape out to the reel's radius, then the dark hub with six
    // light 2×2 teeth that turn with the reel and make the turning visible.
    function reelPainter(x0, cx, tapeRadius, angle) {
        var teeth = []
        for (var i = 0; i < 6; ++i) {
            var a = angle + i * Math.PI / 3
            teeth.push([Math.round(cx + toothRadius * Math.cos(a) - 1),
                        Math.round(reelY + toothRadius * Math.sin(a) - 1)])
        }
        return function(lx, ly) {
            var x = x0 + lx, y = labelY0 + ly
            var dx = x + 0.5 - cx, dy = y + 0.5 - reelY
            var r2 = dx * dx + dy * dy
            if (r2 > tapeRadius * tapeRadius)
                return shell
            if (r2 > hubRadius * hubRadius)
                return paper
            for (var t = 0; t < teeth.length; ++t) {
                if (x - teeth[t][0] >= 0 && x - teeth[t][0] <= 1
                        && y - teeth[t][1] >= 0 && y - teeth[t][1] <= 1)
                    return paper
            }
            return shell
        }
    }

    Canvas {
        id: shellCanvas
        anchors.fill: parent
        antialiasing: false
        smooth: false
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            cassette.paintCells(ctx, cassette.gridWidth, cassette.gridHeight, cassette.shellColor)
        }
    }

    Canvas {
        id: leftWindow
        y: cassette.labelY0 * cassette.pixelSize
        width: cassette.windowWidth * cassette.pixelSize
        height: cassette.windowHeight * cassette.pixelSize
        antialiasing: false
        smooth: false
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            cassette.paintCells(ctx, cassette.windowWidth, cassette.windowHeight,
                                cassette.reelPainter(0, cassette.leftReelX, cassette.leftRadius, cassette.leftAngle))
        }
    }

    Canvas {
        id: rightWindow
        x: (cassette.gridWidth - cassette.windowWidth) * cassette.pixelSize
        y: cassette.labelY0 * cassette.pixelSize
        width: cassette.windowWidth * cassette.pixelSize
        height: cassette.windowHeight * cassette.pixelSize
        antialiasing: false
        smooth: false
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            cassette.paintCells(ctx, cassette.windowWidth, cassette.windowHeight,
                                cassette.reelPainter(cassette.gridWidth - cassette.windowWidth, cassette.rightReelX,
                                                     cassette.rightRadius, cassette.rightAngle))
        }
    }

    onPixelSizeChanged: {
        shellCanvas.requestPaint()
        leftWindow.requestPaint()
        rightWindow.requestPaint()
    }
    onLeftRadiusChanged: leftWindow.requestPaint()
    onRightRadiusChanged: rightWindow.requestPaint()

    // ~15 fps keeps the motion choppy in the way old OSD graphics were, and
    // costs next to nothing. Both reels turn anticlockwise, as they do while a
    // deck plays: the tape leaves the left reel and arrives on the right one
    // along the front edge.
    Timer {
        interval: 66
        repeat: true
        running: cassette.running
        onTriggered: {
            var dt = interval / 1000
            var full = 2 * Math.PI
            cassette.leftAngle  = (cassette.leftAngle  - dt * cassette.tapeSpeed / cassette.leftRadius)  % full
            cassette.rightAngle = (cassette.rightAngle - dt * cassette.tapeSpeed / cassette.rightRadius) % full
            leftWindow.requestPaint()
            rightWindow.requestPaint()
        }
    }
}
