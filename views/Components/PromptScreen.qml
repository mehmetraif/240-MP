import QtQuick

// A question or a notice, full screen, in the window every view has: the
// question in the title bar behind a ? (a notice, an error say, behind a !),
// the hint line at the foot, where every view keeps it, and between them, in
// the middle of the space they leave both ways, what it is about and the
// answers. However few lines it has, the bars stay where they are.
//
// It only draws: the host keeps its keys and the cursor (currentIndex), and
// shows it (visible). Items declared inside it go under the message, above the
// answers (BluetoothPrompt's code); they centre themselves across its width.
//
//     PromptScreen {
//         visible: overlayVisible
//         title: "Resume playback?"
//         message: itemTitle
//         choices: ["Resume from 0:23", "Start from the beginning"]
//         currentIndex: choiceIndex
//         hint: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
//     }
Rectangle {
    id: prompt

    // The question, or for a notice what happened: in the title bar.
    property string title: ""
    // "question" (a ? in the bar) or "notice" (a !).
    property string kind: "question"
    // Under the bar: what it is about (a title, a device), or a notice's
    // details. It wraps.
    property string message: ""
    // The answers: labels, or maps with a label ({ label, action }).
    property var choices: []
    property int currentIndex: 0
    // The hint line.
    property string hint: ""

    default property alias content: extra.data

    anchors.fill: parent
    color: root.surfaceColor

    AppBar {
        id: titleBar
        iconSource: prompt.kind === "notice" ? "../../assets/images/notice.svg"
                                             : "../../assets/images/question.svg"
        title: prompt.title
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // The space between the bars.
    Item {
        id: middle
        anchors.top: titleBar.bottom
        anchors.bottom: hintBar.top
        anchors.left: parent.left
        anchors.right: parent.right
    }

    Column {
        anchors.centerIn: middle
        width: root.sw * 0.76875 //492
        spacing: root.sh * 0.05 //24

        Text {
            visible: prompt.message !== ""
            width: parent.width
            text: prompt.message
            color: root.primaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: root.sh * 0.0416667 //20
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Item {
            id: extra
            visible: children.length > 0
            width: parent.width
            height: childrenRect.height
        }

        Column {
            visible: prompt.choices.length > 0
            width: parent.width

            Repeater {
                model: prompt.choices
                delegate: Item {
                    width: parent.width
                    height: root.sh * 0.0583333 //28

                    Rectangle {
                        anchors.fill: label
                        color: root.accentColor
                        visible: index === prompt.currentIndex
                    }

                    Text {
                        id: label
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width)
                        text: typeof modelData === "string" ? modelData : (modelData.label || "")
                        color: index === prompt.currentIndex ? root.surfaceColor : root.primaryColor
                        font.family: root.globalFont
                        font.capitalization: Font.AllUppercase
                        font.pixelSize: root.sh * 0.05 //24
                        elide: Text.ElideRight
                        topPadding: root.sh * 0.0041667 //2
                        leftPadding: root.sw * 0.009375 //6
                        rightPadding: root.sw * 0.009375 //6
                        bottomPadding: root.sh * 0.00625 //3
                    }
                }
            }
        }
    }

    HintBar {
        id: hintBar
        text: prompt.hint
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }
}
