import QtQuick

// One of the theme's pictures (Settings → Theme, root.theme) over a part of the
// window: its frame, a selected line, the title bar, the hint bar. The theme
// gives the shape, the colour scheme the colours: the picture is drawn in the
// scheme's two (image://osdskin), light in the scheme's colour, dark in its
// background, clear left clear. Nine slices, its corners and edges as the
// theme's border has them, drawn on art pixels and scaled up by root.px, so
// the pixel art stays crisp at any screen size. shown is false while the theme
// has no picture for it (or it can't be read): the caller draws its own then,
// as it does without a theme.
//
//     ThemeImage { id: themed; anchors.fill: parent; part: root.theme.selection }
//     Rectangle { anchors.fill: parent; visible: !themed.shown; color: root.primaryColor }
Item {
    id: themeImage

    // { source, border: [left, top, right, bottom], tile } (AppCore::theme()),
    // or nothing.
    property var part
    readonly property bool shown: !!(part && part.source) && image.status === Image.Ready
    readonly property int tileMode: !part ? BorderImage.Stretch
                                  : part.tile === "repeat" ? BorderImage.Repeat
                                  : part.tile === "round" ? BorderImage.Round
                                  : BorderImage.Stretch

    BorderImage {
        id: image
        visible: themeImage.shown
        width: themeImage.width / root.px
        height: themeImage.height / root.px
        scale: root.px
        transformOrigin: Item.TopLeft
        source: themeImage.part && themeImage.part.source
                ? "image://osdskin/" + String(root.primaryColor).replace("#", "") + "/"
                  + String(root.surfaceColor).replace("#", "") + "/" + themeImage.part.source
                : ""
        border.left: themeImage.side(0)
        border.top: themeImage.side(1)
        border.right: themeImage.side(2)
        border.bottom: themeImage.side(3)
        horizontalTileMode: themeImage.tileMode
        verticalTileMode: themeImage.tileMode
        smooth: false
    }

    function side(i) {
        var b = part && part.border
        return b && b.length === 4 ? b[i] : 0
    }
}
