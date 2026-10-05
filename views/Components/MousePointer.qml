import QtQuick

// The mouse's pointer, drawn the way the OSD draws everything: in the
// picture's own pixels (root.px each), the theme's two colours, an arrow with
// its outline. Its top-left pixel is the point it points at, so the host sets
// x and y to the mouse's position. Main.qml shows and hides it.
Item {
    id: pointer

    // X outline, # fill.
    readonly property var art: [
        "X..........",
        "XX.........",
        "X#X........",
        "X##X.......",
        "X###X......",
        "X####X.....",
        "X#####X....",
        "X######X...",
        "X#######X..",
        "X########X.",
        "X#####XXXXX",
        "X##X##X....",
        "X#X.X##X...",
        "XX..X##X...",
        "X....X##X..",
        ".....X##X..",
        "......XX..."
    ]
    // The drawn pixels: { x, y, fill }.
    readonly property var cells: {
        var out = []
        for (var y = 0; y < art.length; y++)
            for (var x = 0; x < art[y].length; x++)
                if (art[y][x] !== ".")
                    out.push({ x: x, y: y, fill: art[y][x] === "#" })
        return out
    }

    width: art[0].length * root.px
    height: art.length * root.px

    Repeater {
        model: pointer.cells
        Rectangle {
            x: modelData.x * root.px
            y: modelData.y * root.px
            width: root.px
            height: root.px
            color: modelData.fill ? root.primaryColor : root.surfaceColor
            antialiasing: false
        }
    }
}
