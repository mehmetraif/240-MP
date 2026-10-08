import QtQuick

// The two-colour way to fade something out: every other art pixel of the area
// is covered in the background colour, a checkerboard that reads as a half
// tone on a CRT while the screen keeps to two colours. Lay it over whatever
// would otherwise get a lower opacity.
Canvas {
    id: dither

    property color color: root.surfaceColor
    property int pixel: root.px
    // 1 starts the checkerboard a pixel along: two pieces of one pattern that
    // meet (the arms of a window's shadow) give theirs by where they lie.
    property int phase: 0

    antialiasing: false
    smooth: false

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = dither.color
        var cols = Math.ceil(width / pixel)
        var rows = Math.ceil(height / pixel)
        for (var y = 0; y < rows; ++y)
            for (var x = (y + phase) % 2; x < cols; x += 2)
                ctx.fillRect(x * pixel, y * pixel, pixel, pixel)
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onColorChanged: requestPaint()
    onPixelChanged: requestPaint()
    onPhaseChanged: requestPaint()
}
