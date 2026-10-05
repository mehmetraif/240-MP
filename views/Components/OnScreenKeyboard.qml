import QtQuick

// Typing with a remote, the way a deck's menu spells a title: a grid of
// letters and digits under a line showing what has been typed. The arrows move
// the box, select types what is in it (or SPACE, DEL, OK on the last row), and
// back cancels. A real keyboard types straight in, which moves the box to OK
// so Enter then finishes. It covers its parent below the title bar.
//     OnScreenKeyboard { anchors.fill: parent; onAccepted: (text) => … }
FocusScope {
    id: osk

    property string title: "Search"
    property string text: ""
    property int maxLength: 40

    signal accepted(string text)
    signal canceled()

    function open(initial) {
        text = initial || ""
        row = 0
        col = 0
        visible = true
        forceActiveFocus()
    }
    function close() { visible = false }

    readonly property var rows: [
        ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
        ["K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"],
        ["U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3"],
        ["4", "5", "6", "7", "8", "9", "-", "'", ".", "&"],
        ["SPACE", "DEL", "OK"]
    ]
    property int row: 0
    property int col: 0
    readonly property bool onOk: row === rows.length - 1 && col === 2

    visible: false

    function press(key) {
        if (key === "OK") {
            if (text.trim() === "") return
            close()
            accepted(text.trim())
        } else if (key === "DEL") {
            text = text.slice(0, -1)
        } else if (text.length < maxLength) {
            text += key === "SPACE" ? " " : key
        }
    }
    function moveTo(r, c) {
        row = (r + rows.length) % rows.length
        col = Math.max(0, Math.min(rows[row].length - 1, c))
    }

    Keys.onPressed: function(event) {
        event.accepted = true
        switch (event.key) {
        case Qt.Key_Up:    moveTo(row - 1, row === rows.length - 1 ? col * 4 : col); return
        case Qt.Key_Down:  moveTo(row + 1, row === rows.length - 2 ? Math.floor(col / 4) : col); return
        case Qt.Key_Left:  col = (col - 1 + rows[row].length) % rows[row].length; return
        case Qt.Key_Right: col = (col + 1) % rows[row].length; return
        case Qt.Key_Return:
        case Qt.Key_Enter: press(rows[row][col]); return
        case Qt.Key_Escape:
        case Qt.Key_Back:  close(); canceled(); return
        case Qt.Key_Backspace: press("DEL"); return
        }
        // Typed on a real keyboard: straight in, and the box goes to OK.
        var ch = event.text.toUpperCase()
        if (ch.length === 1 && ch >= " " && text.length < maxLength) {
            text += ch
            moveTo(rows.length - 1, 2)
        }
    }

    readonly property real cellW: Math.floor(root.sw * 0.75 / 10) //48
    readonly property real cellH: root.sh * 0.0666667 //32
    readonly property real fontSize: root.sh * 0.05 //24

    Rectangle {
        anchors.fill: parent
        color: root.surfaceColor
    }

    Column {
        x: root.sw * 0.125 //80
        y: root.sh * 0.2083333 //100
        spacing: root.sh * 0.025 //12

        Text {
            text: osk.title
            color: root.primaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: root.sh * 0.0375 //18
        }

        // What has been typed, with a block where the next letter goes.
        Rectangle {
            width: osk.cellW * 10
            height: osk.cellH + 2 * root.px
            color: "transparent"
            border.width: root.px
            border.color: root.primaryColor
            antialiasing: false
            clip: true
            Row {
                x: root.sw * 0.0125 //8
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    id: typed
                    text: osk.text
                    color: root.primaryColor
                    font.family: root.globalFont
                    font.capitalization: Font.AllUppercase
                    font.pixelSize: osk.fontSize
                }
                Rectangle {
                    width: Math.round(osk.fontSize * 0.55)
                    height: Math.round(osk.fontSize * 0.75)
                    anchors.verticalCenter: typed.verticalCenter
                    color: root.primaryColor
                    antialiasing: false
                    visible: blink.on
                }
            }
            Timer {
                id: blink
                property bool on: true
                interval: 500
                repeat: true
                running: osk.visible
                onTriggered: on = !on
            }
        }

        Column {
            Repeater {
                model: osk.rows.length
                Row {
                    id: keyRow
                    required property int index
                    readonly property var keys: osk.rows[index]
                    // The last row's three keys share the grid's width.
                    readonly property real keyW: keys.length === 10 ? osk.cellW : osk.cellW * 10 / keys.length
                    Repeater {
                        model: keyRow.keys
                        Item {
                            required property int index
                            required property string modelData
                            readonly property bool current: osk.row === keyRow.index && osk.col === index
                            width: keyRow.keyW
                            height: osk.cellH
                            Rectangle {
                                anchors.centerIn: parent
                                width: keyText.implicitWidth + 2 * root.sw * 0.009375
                                height: parent.height
                                visible: parent.current
                                color: root.primaryColor
                                antialiasing: false
                            }
                            Text {
                                id: keyText
                                anchors.centerIn: parent
                                text: modelData
                                color: parent.current ? root.surfaceColor : root.primaryColor
                                font.family: root.globalFont
                                font.pixelSize: osk.fontSize
                            }
                        }
                    }
                }
            }
        }
    }

    HintBar {
        text: root.hints.back + ":CANCEL " + root.hints.navigate + ":MOVE " + root.hints.select + ":TYPE"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }
}
