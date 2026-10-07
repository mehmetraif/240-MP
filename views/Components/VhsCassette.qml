import QtQuick

// Pixel-art VHS cassette, the owner's drawing (the boot screen's), in two
// colours: the shell is solid `ink`, and its cut-outs are left clear so the
// background shows through. The cut-outs are the line under the top edge with
// its mark, the label with OSD/OS between two rules (the slash in its three
// colours), the window either side of it with the tape wound on a reel around
// an ink hub, and the two feet. As `progress` goes from 0 to 1 the tape winds
// off the left (supply) reel onto the right (take-up) one, so the left pack
// shrinks while the right one grows.
//
// The art is a grid of cells (`art`, a character a cell: '#' ink, '.' clear,
// 'r', 'b' and 'g' the slash's colours), each drawn as a pixelSize × pixelSize
// block, so the picture stays crisp at any integer scale (and a single-pixel
// line never lands on one interlaced CRT field). The shell is painted once;
// the two reel windows are repainted as the tape moves.
Item {
    id: cassette

    // Screen pixels per art pixel. The host derives it from root.sh.
    property int pixelSize: 3
    // 0 = all of the tape on the left reel, 1 = all of it on the right.
    property real progress: 0

    // The one colour drawn; everything else is the background. The host sets
    // it to the theme's text colour.
    property string ink: "#ffffff"
    readonly property var slashColours: ({ "r": "#ff3d3d", "b": "#2f6bff", "g": "#2fe063" })

    // The drawing, 102 × 47 cells (the owner's osdos-vhs-acilis.png, sampled
    // a cell per 6 of its pixels), the reels full as drawn: the windows show
    // their tape wound off as the progress says.
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
        "###.######..............##...#############################################..##..............######.###",
        "###.#####...............##...#############################################..##...............#####.###",
        "###.####................##...#############################################..##................####.###",
        "###.###...............####...#############################################..####...............###.###",
        "###.###.............######...####.....................................####..######.............###.###",
        "###.##.............###..##...#############################################..##..###.............##.###",
        "###.##............########...#############################################..########............##.###",
        "###.#............##..#####...#############################################..######.##............#.###",
        "###.#............#########...#############################################..#########............#.###",
        "###.#...........#######.##...#####....##....##...#####rbg#b...##....######..##..######...........#.###",
        "###.#...........######..##...####..##.##.##.##.##.b##rbg#b.##.##.#########..##..######...........#.###",
        "###.#...........#..###..##...####..##.##...###.##.b##rbg#b.##.##....######..##..####.#...........#.###",
        "###.#...........##.###..##...####..##.#####.##.##.b#rbg##b.##.#####..#####..##..####.#...........#.###",
        "###.#...........######..##...####..##.##.##.##.##.##rbg##b.##.##.##..#####..##..######...........#.###",
        "###.#...........#######.##...#####...####..###...##rbg####b..####...######..##.#######...........#.###",
        "###.#............#########...#############################################..#########............#.###",
        "###.##...........##..#####...#############################################..#####..##...........##.###",
        "###.##............####.###...#############################################..########............##.###",
        "###.###............###..##...#############################################..###.###............###.###",
        "###.###.............######...####.....................................####..######.............###.###",
        "###.####................##...#############################################..##................####.###",
        "###.#####...............##...#############################################..##...............#####.###",
        "###.######..............##...#############################################..##..............######.###",
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
    // The windows' interiors, where the tape shows.
    readonly property int windowY0: 16
    readonly property int windowY1: 38
    readonly property int leftWindowX0: 5
    readonly property int rightWindowX0: 77
    readonly property int windowWidth: 20
    readonly property int windowHeight: windowY1 - windowY0 + 1
    // Reel centres sit on the frame between each window and the label, so
    // the frame and the label hide the inner half of each reel, as in the
    // drawing, whose hubs (with their holes) the art keeps.
    readonly property real leftReelX: leftWindowX0 + windowWidth + 0.5
    readonly property real rightReelX: rightWindowX0 - 0.5
    readonly property real reelY: (windowY0 + windowY1 + 1) / 2
    // The tape's radius: full as the drawing has it, and never bare hub.
    // Kept off half-integers, which leave a one-cell nub on the circle's edge.
    readonly property real emptyRadius: 11.3
    readonly property real fullRadius: 20.4

    // Tape radius on each reel for the current progress. The tape's area is
    // conserved, so the radii follow the square root, not a straight line.
    function reelRadius(share) {
        var e = emptyRadius * emptyRadius
        var f = fullRadius * fullRadius
        return Math.sqrt(e + Math.max(0, Math.min(1, share)) * (f - e))
    }
    readonly property real leftRadius:  reelRadius(1 - progress)
    readonly property real rightRadius: reelRadius(progress)

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
    // column cx: the drawing's own cells (the hub and its holes, the shell at
    // the corners), but the tape only out to the reel's radius; beyond it the
    // shell shows, as it does behind an empty reel.
    function reelPainter(x0, cx, tapeRadius) {
        return function(lx, ly) {
            var x = x0 + lx, y = windowY0 + ly
            if (art[y].charAt(x) === "#")
                return ink
            var dx = x + 0.5 - cx, dy = y + 0.5 - reelY
            return dx * dx + dy * dy > tapeRadius * tapeRadius ? ink : ""
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
                                                     cassette.leftRadius))
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
                                                     cassette.rightRadius))
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
}
