import QtQuick

// One line of a settings menu, laid out the way a camcorder's on-screen menu
// does it: the label, a run of dots, then the value, "DISPLAY······ON", with
// the value against the line's right end. Everything sits on the font's
// character grid, one dot per cell, so the dots meet the value exactly. The
// selected line is a solid bar with its text in the background colour. A line
// without a value (a submenu) is just its label, and a heading over a group of
// lines is its label with a rule on to the line's end.
Item {
    id: menuRow

    property string label: ""
    // "" for a line with no value.
    property string value: ""
    property bool selected: false
    // A group's heading rather than a line: "MODULES ─────".
    property bool heading: false
    property real fontSize: root.sh * 0.05 //24

    readonly property color ink: selected ? root.surfaceColor : root.primaryColor
    readonly property real pad: root.sw * 0.009375 //6
    // One character cell. TextMetrics rather than FontMetrics.advanceWidth(),
    // so this follows the font once it is set instead of keeping the default
    // font's width.
    readonly property real cell: Math.max(1, metrics.advanceWidth)
    // By the label's drawn width, so a letter from the fallback font, which is
    // not one cell wide, still leaves the dots on the grid and clear of it.
    readonly property int labelCells: Math.ceil(labelText.implicitWidth / cell - 0.01)
    // The value ends on the line's last whole cell. One too long for the line
    // starts two dots after the label instead, and is cut short there.
    readonly property int lineCells: Math.floor((width - 2 * pad) / cell)
    readonly property int valueCells: Math.ceil(valueText.implicitWidth / cell - 0.01)
    readonly property int valueCell: Math.max(labelCells + 2, lineCells - valueCells)
    // How far above the baseline the middle of a capital is: VCR OSD Mono's
    // capitals stand from 100 to 1500 of its 2048 units, and its hyphen sits
    // at their middle, 800.
    readonly property real capMiddle: fontSize * 800 / 2048

    TextMetrics {
        id: metrics
        font.family: root.globalFont
        font.pixelSize: menuRow.fontSize
        text: "M"
    }

    Rectangle {
        anchors.fill: parent
        visible: menuRow.selected
        color: root.primaryColor
        antialiasing: false
    }

    Text {
        id: labelText
        x: menuRow.pad
        anchors.verticalCenter: parent.verticalCenter
        text: menuRow.label
        color: menuRow.ink
        font.family: root.globalFont
        font.capitalization: Font.AllUppercase
        font.pixelSize: menuRow.fontSize
    }

    // The leader: one square dot in each cell between the label and the value,
    // level with the middle of the capitals. Drawn rather than typed, since the
    // font has no middle dot of its own.
    Repeater {
        model: menuRow.value !== "" ? Math.max(0, menuRow.valueCell - menuRow.labelCells) : 0
        Rectangle {
            x: Math.round(menuRow.pad + (menuRow.labelCells + index + 0.5) * menuRow.cell - width / 2)
            y: Math.round(labelText.y + labelText.baselineOffset - menuRow.capMiddle - height / 2)
            width: root.px
            height: root.px
            color: menuRow.ink
            antialiasing: false
        }
    }

    // A heading's rule, from a cell past the label to the line's end, at the
    // height the dots would be.
    Rectangle {
        visible: menuRow.heading
        x: Math.round(menuRow.pad + (menuRow.labelCells + 1) * menuRow.cell)
        y: Math.round(labelText.y + labelText.baselineOffset - menuRow.capMiddle - height / 2)
        width: Math.max(0, Math.round(menuRow.pad + menuRow.lineCells * menuRow.cell) - x)
        height: root.px
        color: menuRow.ink
        antialiasing: false
    }

    // The value: cut short with "…" when it is too long for the line, and
    // scrolled through instead while the line is selected.
    Item {
        id: valueClip
        visible: menuRow.value !== ""
        x: menuRow.pad + menuRow.valueCell * menuRow.cell
        width: Math.max(0, menuRow.lineCells - menuRow.valueCell) * menuRow.cell
        height: parent.height
        clip: true

        Text {
            id: valueText
            anchors.verticalCenter: parent.verticalCenter
            width: menuRow.selected ? implicitWidth : Math.min(implicitWidth, valueClip.width)
            text: menuRow.value
            color: menuRow.ink
            elide: Text.ElideRight
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: menuRow.fontSize
        }

        SequentialAnimation {
            running: menuRow.selected && valueText.implicitWidth > valueClip.width
            loops: Animation.Infinite
            onRunningChanged: if (!running) valueText.x = 0

            PauseAnimation { duration: 1500 }
            NumberAnimation {
                target: valueText
                property: "x"
                to: valueClip.width - valueText.implicitWidth
                duration: Math.abs(to) * 20
            }
            PauseAnimation { duration: 2000 }
            PropertyAction { target: valueText; property: "x"; value: 0 }
        }
    }
}
