import QtQuick

// Pixel-art VHS cassette with two reels turning behind the window. As
// `progress` goes from 0 to 1 the tape winds off the left (supply) reel onto
// the right (take-up) one, and each reel turns at the speed its tape radius
// gives it: the full reel slowly, the nearly empty one fast, like a real deck.
//
// The art lives on a fixed gridWidth × gridHeight grid and every grid cell is
// drawn as a pixelSize × pixelSize block, so the picture stays crisp at any
// integer scale (and a single-pixel line never lands on one interlaced CRT
// field). The shell is painted once; only the window is repainted per tick.
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

    // --- Palette ---
    readonly property string shellBase:  "#1d1d22"
    readonly property string shellHi:    "#4b4b55"
    readonly property string shellLo:    "#0c0c0f"
    readonly property string shellRidge: "#2e2e36"
    readonly property string screw:      "#3a3a44"
    readonly property string recess:     "#131317"
    readonly property string label:      "#efe8d8"
    readonly property string labelShade: "#cfc5ad"
    readonly property string ink:        "#1d1d22"
    readonly property var    stripes:    ["#e8452c", "#f39c1f", "#f7d038"]
    readonly property string glass:      "#4a5160"
    readonly property string glassHi:    "#5f6778"
    readonly property string glare:      "rgba(255, 255, 255, 0.16)"
    readonly property string tape:       "#2b1e17"
    readonly property string tapeRing:   "#38281f"
    readonly property string tapeEdge:   "#4a3529"
    readonly property string tapeGlint:  "#7a5e4b"
    readonly property string hub:        "#ebe7de"
    readonly property string hubShade:   "#b9b3a6"
    readonly property string hubNotch:   "#3b3b42"
    readonly property string hubHole:    "#141418"

    // --- Geometry (grid cells) ---
    // Window interior, inclusive bounds.
    readonly property int winX0: 22
    readonly property int winY0: 24
    readonly property int winX1: 73
    readonly property int winY1: 48
    // Reel centres sit on cell centres so each reel is symmetric.
    readonly property real leftReelX:  35.5
    readonly property real rightReelX: 60.5
    readonly property real reelY:      36.5
    readonly property real hubRadius:  5.6
    readonly property real emptyRadius: 6.4   // a reel never shows bare plastic
    readonly property real fullRadius:  11.4
    // Linear tape speed in grid cells per second; each reel's angular speed is
    // this over its current tape radius.
    readonly property real tapeSpeed: 30

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

    // 3×5 / 5×5 glyphs for the label text.
    readonly property var glyphs: ({
        "2": ["111", "001", "111", "100", "111"],
        "4": ["101", "101", "111", "001", "001"],
        "0": ["111", "101", "101", "101", "111"],
        "-": ["000", "000", "111", "000", "000"],
        "M": ["10001", "11011", "10101", "10001", "10001"],
        "P": ["111", "101", "111", "100", "100"]
    })
    readonly property string labelText: "240-MP"

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

    // Cells of the label text, keyed "x,y", laid out once.
    readonly property var textCells: {
        var cells = {}
        var width = 0
        for (var i = 0; i < labelText.length; ++i)
            width += glyphs[labelText[i]][0].length + (i > 0 ? 1 : 0)
        var x = Math.floor((10 + 85 + 1 - width) / 2)
        for (var j = 0; j < labelText.length; ++j) {
            var g = glyphs[labelText[j]]
            for (var row = 0; row < g.length; ++row)
                for (var col = 0; col < g[row].length; ++col)
                    if (g[row][col] === "1")
                        cells[(x + col) + "," + (6 + row)] = true
            x += g[0].length + 1
        }
        return cells
    }

    function cornerCut(x, y, x0, y0, x1, y1) {
        return (x - x0) + (y - y0) < 2 || (x1 - x) + (y - y0) < 2
            || (x - x0) + (y1 - y) < 2 || (x1 - x) + (y1 - y) < 2
    }

    function shellColor(x, y) {
        var W = gridWidth, H = gridHeight
        if (cornerCut(x, y, 0, 0, W - 1, H - 1))
            return ""
        // Window interior: left to the animated layer, except its cut corners.
        if (x >= winX0 && x <= winX1 && y >= winY0 && y <= winY1)
            return cornerCut(x, y, winX0, winY0, winX1, winY1) ? recess : ""
        // Bevelled rim: lit from the top left.
        if (x === 0 || y === 0 || x + y === 2)
            return shellHi
        if (x === W - 1 || y === H - 1 || (W - 1 - x) + (H - 1 - y) === 2)
            return shellLo
        // Label with the brand stripes and the text.
        if (x >= 10 && x <= 85 && y >= 4 && y <= 20) {
            if (y === 20)
                return labelShade
            if (y >= 13 && y <= 18 && x >= 12 && x <= 83)
                return stripes[Math.floor((y - 13) / 2)]
            return textCells[x + "," + y] ? ink : label
        }
        // Sunken frame around the window: shadow on top/left, light bottom/right.
        if (x >= 20 && x <= 75 && y >= 22 && y <= 50) {
            if (y === 22 || x === 20)
                return shellLo
            if (y === 50 || x === 75)
                return shellRidge
            return recess
        }
        // Screws in the four corners.
        var screws = [[5, 5], [90, 5], [5, 50], [90, 50]]
        for (var i = 0; i < screws.length; ++i) {
            var dx = x - screws[i][0], dy = y - screws[i][1]
            if (Math.abs(dx) <= 1 && Math.abs(dy) <= 1) {
                if (dx === 0 && dy === 0)
                    return shellLo
                return (dx === 0 || dy === 0) ? screw : shellBase
            }
        }
        // Ribbed grips on both sides of the window.
        if ((x === 4 || x === 5 || x === 90 || x === 91) && y >= 16 && y <= 44 && y % 2 === 0)
            return shellRidge
        // Embossed seam above the tape door.
        if (y === 53 && x >= 8 && x <= 87)
            return shellLo
        if (y === 54 && x >= 8 && x <= 87)
            return shellRidge
        return shellBase
    }

    // One reel cell at offset (dx, dy) from the reel centre, or "" outside it.
    function reelColor(dx, dy, tapeRadius, angle) {
        var r = Math.sqrt(dx * dx + dy * dy)
        if (r > tapeRadius)
            return ""
        var theta = Math.atan2(dy, dx) - angle
        if (r <= 1.6)
            return hubHole
        if (r <= hubRadius) {
            // Six notches around the hub; they are what makes the turn visible.
            var sector = Math.PI / 3
            var a = ((theta % sector) + sector) % sector
            if (r >= 2.6 && r <= 4.7 && a < 0.36)
                return hubNotch
            return (r > 4.6 && dx + dy > 3) ? hubShade : hub
        }
        // A glint on the tape pack turns with the reel.
        var g = Math.atan2(Math.sin(theta), Math.cos(theta))
        if (Math.abs(g) < 0.22 && r >= tapeRadius - 2.2)
            return tapeGlint
        if (r > tapeRadius - 0.9)
            return tapeEdge
        return (Math.floor(r) % 3 === 0) ? tapeRing : tape
    }

    function windowColor(lx, ly) {
        var x = winX0 + lx, y = winY0 + ly
        if (cornerCut(x, y, winX0, winY0, winX1, winY1))
            return ""
        var px = x + 0.5, py = y + 0.5
        var c = reelColor(px - leftReelX, py - reelY, leftRadius, leftAngle)
        if (c)
            return c
        c = reelColor(px - rightReelX, py - reelY, rightRadius, rightAngle)
        if (c)
            return c
        return ly === 0 ? glassHi : glass
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
        id: windowCanvas
        x: cassette.winX0 * cassette.pixelSize
        y: cassette.winY0 * cassette.pixelSize
        width: (cassette.winX1 - cassette.winX0 + 1) * cassette.pixelSize
        height: (cassette.winY1 - cassette.winY0 + 1) * cassette.pixelSize
        antialiasing: false
        smooth: false
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = cassette.winX1 - cassette.winX0 + 1
            var h = cassette.winY1 - cassette.winY0 + 1
            cassette.paintCells(ctx, w, h, cassette.windowColor)
            // Two diagonal glare streaks across the glass, over the reels.
            var s = cassette.pixelSize
            ctx.fillStyle = cassette.glare
            for (var ly = 1; ly < h - 1; ++ly) {
                var streaks = [ly + 30, ly + 32, ly + 33]
                for (var i = 0; i < streaks.length; ++i) {
                    var lx = streaks[i]
                    if (lx > 1 && lx < w - 2)
                        ctx.fillRect(lx * s, ly * s, s, s)
                }
            }
        }
    }

    onPixelSizeChanged: { shellCanvas.requestPaint(); windowCanvas.requestPaint() }
    onLeftRadiusChanged: windowCanvas.requestPaint()

    // ~15 fps keeps the motion choppy in the way old OSD graphics were, and
    // costs next to nothing.
    Timer {
        interval: 66
        repeat: true
        running: cassette.running
        onTriggered: {
            var dt = interval / 1000
            var full = 2 * Math.PI
            cassette.leftAngle  = (cassette.leftAngle  + dt * cassette.tapeSpeed / cassette.leftRadius)  % full
            cassette.rightAngle = (cassette.rightAngle + dt * cassette.tapeSpeed / cassette.rightRadius) % full
            windowCanvas.requestPaint()
        }
    }
}
