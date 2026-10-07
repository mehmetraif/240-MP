import QtQuick

// Putting a video on one of the app's playlists (the Playlists module's), in
// the standard window: from a module's OPTIONS (EntryOptions' ADD TO
// PLAYLIST), or wherever else a module offers it (Jellyfin's and Emby's item
// pages, right on PLAY). It lists every playlist that takes the module's
// videos, then NEW ONLINE PLAYLIST and NEW OFFLINE PLAYLIST, named on the
// on-screen keyboard; what became of the video then shows in the same
// window, until back or select closes it.
//
//     PlaylistAdder {
//         id: adder
//         anchors.fill: parent
//         onClosed: list.forceActiveFocus()
//     }
//     … if (adder.available(moduleRoot.moduleId)) adder.offer(moduleRoot.moduleId, entry)
//
// The entry is the video as its module has it (a tree's entry, a server's
// item): see PlaylistsBackend::addEntry.
FocusScope {
    id: adder

    property string moduleId: ""
    property var entry: null

    signal closed()

    visible: false
    // Hidden, it lets go of the keys.
    enabled: visible
    focus: visible

    // The choices: { label, action: "add" | "new", id, name, kind }.
    property var rows: []
    property int choiceIndex: 0
    // What became of the video, once a playlist is chosen: { title, message }.
    property var outcome: null

    // Whether a module's videos can go on a playlist: the Playlists module
    // there and on, and taking them.
    function available(forModule) {
        return typeof playlistsBackend !== "undefined" && !!playlistsBackend && !!appCore
               && appCore.is_module_enabled("com.240mp.playlists") && playlistsBackend.supports(forModule)
    }

    function offer(forModule, item) {
        moduleId = forModule
        entry = item
        outcome = null
        var out = []
        var lists = playlistsBackend.playlists()
        for (var i = 0; i < lists.length; i++) {
            if (!playlistsBackend.supports(forModule, lists[i].kind))
                continue
            out.push({ label: lists[i].name + (lists[i].kind === "offline" ? " (Offline)" : ""),
                       action: "add", id: lists[i].id, name: lists[i].name, kind: lists[i].kind })
        }
        out.push({ label: "New Online Playlist", action: "new", kind: "online" })
        out.push({ label: "New Offline Playlist", action: "new", kind: "offline" })
        rows = out
        choiceIndex = 0
        visible = true
        forceActiveFocus()
    }

    function close() {
        osk.close()
        visible = false
        closed()
    }

    function addTo(playlistId, name, kind) {
        var result = playlistsBackend.addEntry(playlistId, moduleId, entry)
        var title = result.title || (entry ? (entry.title || entry.name || "") : "")
        if (result.ok)
            outcome = { title: "Added to " + name,
                        message: title + (kind === "offline" && moduleId !== "com.240mp.local_files"
                                          ? "\nIt downloads in the background, once" : "") }
        else if (result.reason === "duplicate")
            outcome = { title: "Already on " + name, message: title }
        else
            outcome = { title: "Can't go on a playlist", message: title }
    }

    Keys.onPressed: function(event) {
        var back = event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back
        var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        if (outcome) {
            if (back || enter)
                close()
        } else if (back) {
            close()
        } else if (event.key === Qt.Key_Up) {
            choiceIndex = (choiceIndex - 1 + rows.length) % rows.length
        } else if (event.key === Qt.Key_Down) {
            choiceIndex = (choiceIndex + 1) % rows.length
        } else if (enter) {
            var row = rows[choiceIndex]
            if (row.action === "add") {
                addTo(row.id, row.name, row.kind)
            } else {
                osk.kind = row.kind
                osk.title = row.kind === "offline" ? "Offline Playlist Name" : "Online Playlist Name"
                osk.open("")
            }
        }
        // A window over the host's view: its keys stop here (the host may
        // have uses for ◄ ►), but for a chord like Ctrl+Q.
        if (!(event.modifiers & Qt.ControlModifier))
            event.accepted = true
    }

    PromptScreen {
        kind: adder.outcome ? "notice" : "question"
        title: adder.outcome ? adder.outcome.title : osk.visible ? "New playlist" : "Add to playlist?"
        message: adder.outcome ? adder.outcome.message
                               : adder.entry ? (adder.entry.title || adder.entry.name || "") : ""
        choices: adder.outcome ? [] : adder.rows
        currentIndex: adder.choiceIndex
        hint: adder.outcome ? root.hints.back + ":BACK " + root.hints.select + ":OK"
                            : root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
    }

    OnScreenKeyboard {
        id: osk
        anchors.fill: parent
        property string kind: "online"
        // Closed, it gives the keys back: still this scope's focus, it would
        // take them again as the window does.
        onAccepted: function(text) {
            osk.focus = false
            adder.forceActiveFocus()
            var id = playlistsBackend.createPlaylist(text, kind)
            adder.addTo(id, playlistsBackend.playlist(id).name || text, kind)
        }
        onCanceled: {
            osk.focus = false
            adder.forceActiveFocus()
        }
    }
}
