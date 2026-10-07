import QtQuick

// Pixel-art VHS cassette, the owner's drawing (the boot screen's), in two
// colours: the shell is solid `ink`, and its cut-outs are left clear so the
// background shows through. The cut-outs are the line under the top edge with
// its mark, the label with OSD/OS between two rules (the slash in its three
// colours), the window either side of it with the tape wound on a reel around
// an ink hub, and the two feet. As `progress` goes from 0 to 1 the tape winds
// off the left (supply) reel onto the right (take-up) one, so the left pack
// shrinks while the right one grows. Each reel turns at the speed its tape
// radius gives it, the full reel slowly and the nearly empty one fast, like a
// real deck.
//
// The art is a grid of cells (`art`, a character a cell: '#' ink, '.' clear,
// 'r', 'b' and 'g' the slash's colours), each drawn as a pixelSize × pixelSize
// block, so the picture stays crisp at any integer scale (and a single-pixel
// line never lands on one interlaced CRT field). The shell is painted once;
// only the two reel windows are repainted per tick.
Item {
    id: cassette

    // Screen pixels per art pixel. The host derives it from root.sh.
    property int pixelSize: 3
    // 0 = all of the tape on the left reel, 1 = all of it on the right.
    property real progress: 0
    property bool running: visible

    // The one colour drawn; everything else is the background. The host sets
    // it to the theme's text colour.
    property string ink: "#ffffff"
    readonly property var slashColours: ({ "r": "#ff3d3d", "b": "#2f6bff", "g": "#2fe063" })

    // The drawing, 102 × 47 cells (assets: the owner's osdos-vhs-acilis.png,
    // sampled a cell per 6 of its pixels). The windows' interiors are left
    // clear here: the reels are painted into them.
    readonly property var art: [
        "..##################################################################################################..",
        ".####################################################################################################.",
        "######################################################################################################",
        "######################################################################################################",
        "##################################################..##################################################",
        "#....................................................................................................#",
        "#..#############################################.......############################################..#",
        "#.##############################################...#...#############################################.#",
        "#.##############################################..###..#############################################.#",
        "#.##############################################.#####.#############################################.#",
        "######################################################################################################",
        "######################################################################################################",
        "######################################################################################################",
        "####..............................................................................................####",
        "###................................................................................................###",
        "###..#####################...############################################...#####################...##",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...####.....................................####..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#####....##....##...#####rbg#b...##....######..#....................#.###",
        "###.#....................#...####..##.##.##.##.##.b##rbg#b.##.##.#########..#....................#.###",
        "###.#....................#...####..##.##...###.##.b##rbg#b.##.##....######..#....................#.###",
        "###.#....................#...####..##.#####.##.##.b#rbg##b.##.#####..#####..#....................#.###",
        "###.#....................#...####..##.##.##.##.##.##rbg##b.##.##.##..#####..#....................#.###",
        "###.#....................#...#####...####..###...##rbg####b..####...######..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...####.....................................####..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###.#....................#...#############################################..#....................#.###",
        "###..#####################...############################################...#####################..###",
        "####.............................................................................................#####",
        "######################################################################################################",
        "######################################################################################################",
        "###...##########################################################################################...###",
        "###...##########################################################################################...###",
        ".####################################################################################################.",
        "..##################################################################################################.."
    ]
    readonly property int gridWidth: 102
    readonly property int gridHeight: 47

    width: gridWidth * pixelSize
    height: gridHeight * pixelSize

    // --- Geometry (grid cells, inclusive bounds) ---
    // The windows' interiors; their frames are in the art.
    readonly property int windowY0: 16
    readonly property int windowY1: 38
    readonly property int leftWindowX0: 5
    readonly property int rightWindowX0: 77
    readonly property int windowWidth: 20
    readonly property int windowHeight: windowY1 - windowY0 + 1
    // Reel centres sit on the frame between each window and the label, so
    // the frame and the label hide the inner half of each reel, as in the
    // drawing.
    readonly property real leftReelX: leftWindowX0 + windowWidth + 0.5
    readonly property real rightReelX: rightWindowX0 - 0.5
    readonly property real reelY: (windowY0 + windowY1 + 1) / 2
    // Radii that rest on screen are kept off half-integers: those leave a
    // one-cell nub on the circle's outer edge.
    readonly property real hubRadius: 9.4
    readonly property real toothRadius: 6.6
    readonly property real emptyRadius: 11.3  // a reel never shows bare hub
    readonly property real fullRadius: 20.4
    // Linear tape speed in grid cells per second; each reel's angular speed is
    // this over its current tape radius.
    readonly property real tapeSpeed: 20

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

    function inWindow(x, y) {
        return y >= windowY0 && y <= windowY1
            && ((x >= leftWindowX0 && x < leftWindowX0 + windowWidth)
                || (x >= rightWindowX0 && x < rightWindowX0 + windowWidth))
    }

    function shellColor(x, y) {
        // The reel windows, left to their own layer.
        if (inWindow(x, y))
            return ""
        var c = art[y].charAt(x)
        if (c === "#")
            return ink
        return slashColours[c] || ""
    }

    // Colours the reel window that starts at column x0, for a reel centred on
    // column cx: clear tape out to the reel's radius, then the ink hub with six
    // clear 2×2 teeth that turn with the reel and make the turning visible.
    function reelPainter(x0, cx, tapeRadius, angle) {
        var teeth = []
        for (var i = 0; i < 6; ++i) {
            var a = angle + i * Math.PI / 3
            teeth.push([Math.round(cx + toothRadius * Math.cos(a) - 1),
                        Math.round(reelY + toothRadius * Math.sin(a) - 1)])
        }
        return function(lx, ly) {
            var x = x0 + lx, y = windowY0 + ly
            var dx = x + 0.5 - cx, dy = y + 0.5 - reelY
            var r2 = dx * dx + dy * dy
            if (r2 > tapeRadius * tapeRadius)
                return ink
            if (r2 > hubRadius * hubRadius)
                return ""
            for (var t = 0; t < teeth.length; ++t) {
                if (x - teeth[t][0] >= 0 && x - teeth[t][0] <= 1
                        && y - teeth[t][1] >= 0 && y - teeth[t][1] <= 1)
                    return ""
            }
            return ink
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
        x: cassette.leftWindowX0 * cassette.pixelSize
        y: cassette.windowY0 * cassette.pixelSize
        width: cassette.windowWidth * cassette.pixelSize
        height: cassette.windowHeight * cassette.pixelSize
        antialiasing: false
        smooth: false
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            cassette.paintCells(ctx, cassette.windowWidth, cassette.windowHeight,
                                cassette.reelPainter(cassette.leftWindowX0, cassette.leftReelX,
                                                     cassette.leftRadius, cassette.leftAngle))
        }
    }

    Canvas {
        id: rightWindow
        x: cassette.rightWindowX0 * cassette.pixelSize
        y: cassette.windowY0 * cassette.pixelSize
        width: cassette.windowWidth * cassette.pixelSize
        height: cassette.windowHeight * cassette.pixelSize
        antialiasing: false
        smooth: false
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            cassette.paintCells(ctx, cassette.windowWidth, cassette.windowHeight,
                                cassette.reelPainter(cassette.rightWindowX0, cassette.rightReelX,
                                                     cassette.rightRadius, cassette.rightAngle))
        }
    }

    function repaintAll() {
        shellCanvas.requestPaint()
        leftWindow.requestPaint()
        rightWindow.requestPaint()
    }
    onPixelSizeChanged: repaintAll()
    onInkChanged: repaintAll()
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
