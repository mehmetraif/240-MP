import QtQuick

// A full-screen keyboard-driven chooser: a prompt, the thing being acted on, and
// a short list of options. Factored out of NfcCardWriter.qml's chooser so every
// prompt in the app reads the same way, in the standard window (PromptScreen):
// the prompt in the title bar, the thing under it.
//
// The host binds `choices` to a list of { label, action } maps and acts on the
// action in onActivated — the action is what drives behavior, never the label
// text, which is free to change with state.
FocusScope {
    id: overlayRoot

    property string promptText:   ""
    property string subtitleText: ""
    property var    choices:      []

    property int choiceIndex: 0

    signal activated(string action)
    signal closed()

    visible: false
    focus: visible

    function open() {
        choiceIndex = 0
        visible = true
        forceActiveFocus()
    }

    function close() {
        visible = false
        closed()
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
            close()
            event.accepted = true
            return
        }
        if (choices.length === 0) return

        if (event.key === Qt.Key_Up) {
            choiceIndex = (choiceIndex - 1 + choices.length) % choices.length
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            choiceIndex = (choiceIndex + 1) % choices.length
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var choice = choices[choiceIndex]
            // Close first, so the host's onClosed focus restore lands before any
            // navigation the action triggers.
            close()
            if (choice) activated(choice.action)
            event.accepted = true
        }
    }

    PromptScreen {
        title: overlayRoot.promptText
        message: overlayRoot.subtitleText
        choices: overlayRoot.choices
        currentIndex: overlayRoot.choiceIndex
        hint: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
    }
}
