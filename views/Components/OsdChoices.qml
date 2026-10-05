import QtQuick

// A row of settings the way a deck lists them, "SP EP SLP", with the one in
// force shown inverted.
Row {
    id: choices

    property var options: []
    property int current: 0
    property real fontSize: root.sh * 0.05 //24

    spacing: root.sw * 0.01875 //12

    Repeater {
        model: choices.options
        Item {
            width: label.implicitWidth
            height: label.implicitHeight
            Rectangle {
                anchors.fill: parent
                visible: index === choices.current
                color: root.primaryColor
                antialiasing: false
            }
            Text {
                id: label
                text: modelData
                color: index === choices.current ? root.surfaceColor : root.primaryColor
                font.family: root.globalFont
                font.capitalization: Font.AllUppercase
                font.pixelSize: choices.fontSize
                leftPadding: root.px
                rightPadding: root.px
            }
        }
    }
}
