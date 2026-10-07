import QtQuick
import Components

// A playlist's page: PLAY, its ORDER (in order, or shuffled), ADD VIDEOS,
// RENAME, DELETE PLAYLIST, then its videos, each with where it comes from or,
// on an offline list, how its download is going. Select on a video offers to
// play the list from it, move it, or take it off.
FocusScope {
    id: pageRoot

    property var navParams: ({})
    property var navListState: navParams.navListState || ({})
    readonly property string playlistId: navParams.playlistId || ""

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    property var playlist: ({})
    property var rows: []
    // Downloads under way: { key: percent }, kept apart from rows so a
    // percent changes a line without rebuilding the list.
    property var progress: ({})
    readonly property bool offline: playlist.kind === "offline"
    readonly property var currentRow: rows[list.currentIndex]

    readonly property var sourceNames: ({
        "com.240mp.local_files": "Local", "com.240mp.youtube": "YouTube",
        "com.240mp.jellyfin": "Jellyfin", "com.240mp.emby": "Emby" })

    function itemValue(item) {
        if (item.state === "missing")
            return "Missing"
        if (!offline)
            return sourceNames[item.module] || ""
        if (item.state === "ready") return "Ready"
        if (item.state === "downloading") return (progress[item.key] !== undefined ? progress[item.key] : item.percent) + "%"
        if (item.state === "failed") return item.reason === "not allowed" ? "Not Allowed" : "Failed"
        return "Queued"
    }

    function rowsFrom(p) {
        var items = p.items || []
        var ready = 0, failed = 0
        for (var i = 0; i < items.length; i++) {
            if (items[i].state === "ready") ready++
            if (items[i].state === "failed") failed++
        }
        var out = [{ type: "play", label: "Play",
                     value: p.kind === "offline" ? ready + " of " + items.length + " Ready" : items.length + " Videos" },
                   { type: "order", label: "Order", value: p.order === "shuffle" ? "Shuffle" : "In Order" },
                   { type: "add", label: "Add Videos" },
                   { type: "rename", label: "Rename" }]
        if (failed > 0)
            out.push({ type: "retry", label: "Retry Downloads" })
        out.push({ type: "delete", label: "Delete Playlist" })
        if (items.length > 0)
            out.push({ type: "section", label: "Videos" })
        for (var j = 0; j < items.length; j++)
            out.push({ type: "item", item: items[j], key: items[j].key, label: items[j].title })
        return out
    }

    function reload() {
        if (!playlistsBackend)
            return
        var current = list.currentIndex
        var y = list.contentY
        playlist = playlistsBackend.playlist(playlistId)
        if (!playlist.id) {
            // Deleted.
            pageRoot.goBack()
            return
        }
        progress = ({})
        rows = rowsFrom(playlist)
        list.currentIndex = Math.max(0, Math.min(current, rows.length - 1))
        list.contentY = y
        if (rows[list.currentIndex] && rows[list.currentIndex].type === "section")
            list.step(1)
    }

    function play(fromItemId) {
        pageRoot.navigateTo("Player.qml", { playlistId: playlistId, fromItemId: fromItemId || "" },
                            { currentIndex: list.currentIndex })
    }

    Component.onCompleted: {
        reload()
        if (navListState.currentIndex !== undefined)
            list.currentIndex = Math.min(navListState.currentIndex, rows.length - 1)
        // The list playing behind the menus: on to its player, back from
        // which lands here.
        else if (navParams.resumePlayer)
            Qt.callLater(function() {
                pageRoot.navigateTo("Player.qml", navParams.resumePlayer, { currentIndex: list.currentIndex })
            })
    }

    Connections {
        target: playlistsBackend
        function onPlaylistsChanged() { pageRoot.reload() }
        function onDownloadProgress(key, percent) {
            var p = Object.assign({}, pageRoot.progress)
            p[key] = percent
            pageRoot.progress = p
        }
    }

    AppBar {
        iconSource: moduleRoot.moduleIcon
        title: moduleRoot.moduleName
        subtitle: pageRoot.playlist.name || ""
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    ListView {
        id: list
        model: pageRoot.rows
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.25 //120
        anchors.leftMargin: root.sw * 0.115625 //74
        width: root.sw * 0.76875 //492
        // One row short of the space, so the ▼ fits above the help line.
        height: root.sh * 0.4666667 //224
        clip: true
        focus: true

        function step(delta) {
            if (count === 0)
                return
            var i = currentIndex
            do {
                i = (i + delta + count) % count
            } while (pageRoot.rows[i].type === "section")
            currentIndex = i
            positionViewAtIndex(i, ListView.Contain)
        }
        function toggleOrder() {
            playlistsBackend.setOrder(pageRoot.playlistId, pageRoot.playlist.order === "shuffle" ? "inorder" : "shuffle")
        }
        Keys.onUpPressed: step(-1)
        Keys.onDownPressed: step(1)
        Keys.onLeftPressed: { if (pageRoot.currentRow && pageRoot.currentRow.type === "order") toggleOrder() }
        Keys.onRightPressed: { if (pageRoot.currentRow && pageRoot.currentRow.type === "order") toggleOrder() }
        Keys.onReturnPressed: {
            var row = pageRoot.currentRow
            if (!row)
                return
            switch (row.type) {
            case "play":
                pageRoot.play("")
                break
            case "order":
                toggleOrder()
                break
            case "add":
                pageRoot.navigateTo("AddVideos.qml", { playlistId: pageRoot.playlistId,
                                                       playlistName: pageRoot.playlist.name,
                                                       kind: pageRoot.playlist.kind },
                                    { currentIndex: list.currentIndex })
                break
            case "rename":
                osk.open(pageRoot.playlist.name || "")
                break
            case "retry":
                playlistsBackend.retryDownloads(pageRoot.playlistId)
                break
            case "delete":
                confirm.choiceIndex = 0
                confirm.visible = true
                confirm.forceActiveFocus()
                break
            case "item":
                itemOptions.item = row.item
                itemOptions.open()
                break
            }
        }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                pageRoot.goBack()
                event.accepted = true
            }
        }

        delegate: MenuRow {
            width: list.width
            height: root.sh * 0.0583333 //28
            heading: modelData.type === "section"
            // A video's title gives way to where it is.
            keepValue: modelData.type === "item"
            label: modelData.label || ""
            value: modelData.type === "item" ? pageRoot.itemValue(modelData.item) : (modelData.value || "")
            selected: list.currentIndex === index
        }
    }

    // ▲ / ▼ while lines are hidden above or below.
    ScrollMarks {
        anchors.fill: list
        list: list
    }

    HelpLine {
        visible: !osk.visible && !itemOptions.visible && !confirm.visible
        readonly property var row: pageRoot.currentRow
        text: !row ? ""
            : row.type === "play" ? (pageRoot.offline
                ? "Plays the videos on the device; the others as their downloads finish"
                : "YouTube, Jellyfin and Emby videos need the network")
            : row.type === "order" ? "[IN ORDER] One after another, from where it stopped  [SHUFFLE] In a new order each time"
            : row.type === "add" ? (pageRoot.offline
                ? "From Local Files, YouTube, Jellyfin or Emby, each downloaded once"
                : "From Local Files, YouTube, Jellyfin or Emby")
            : row.type === "retry" ? "Downloads that failed, once more"
            : row.type === "delete" ? (pageRoot.offline ? "Its downloads go too, unless another offline playlist has them" : "")
            : row.type === "item" ? (row.item.state === "failed" && row.item.reason
                ? row.item.title + ": " + (row.item.reason === "not allowed" ? "the server doesn't let this user download it" : row.item.reason)
                : row.item.title)
            : ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1583333 //76
        anchors.leftMargin: root.sw * 0.125 //80
    }

    HintBar {
        visible: !osk.visible && !itemOptions.visible && !confirm.visible
        text: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE "
              + (pageRoot.currentRow && pageRoot.currentRow.type === "order" ? root.hints.change + ":CHANGE " : "")
              + root.hints.select + ":SELECT"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // A video's own choices.
    ChoiceOverlay {
        id: itemOptions
        anchors.fill: parent
        property var item: null
        promptText: "Video"
        subtitleText: item ? item.title : ""
        choices: [{ label: "Play from Here", action: "play" },
                  { label: "Move Up", action: "up" },
                  { label: "Move Down", action: "down" },
                  { label: "Remove from Playlist", action: "remove" }]
        onActivated: function(action) {
            if (!item)
                return
            if (action === "play")
                pageRoot.play(item.id)
            else if (action === "up")
                playlistsBackend.moveItem(pageRoot.playlistId, item.id, -1)
            else if (action === "down")
                playlistsBackend.moveItem(pageRoot.playlistId, item.id, 1)
            else if (action === "remove")
                playlistsBackend.removeItem(pageRoot.playlistId, item.id)
        }
        onClosed: list.forceActiveFocus()
    }

    // Deleting asks first, Cancel under the cursor.
    PromptScreen {
        id: confirm
        visible: false
        property int choiceIndex: 0
        title: "Delete playlist?"
        message: pageRoot.playlist.name || ""
        choices: ["Cancel", "Delete"]
        currentIndex: choiceIndex
        hint: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
        Keys.onUpPressed: choiceIndex = 0
        Keys.onDownPressed: choiceIndex = 1
        Keys.onReturnPressed: {
            visible = false
            list.forceActiveFocus()
            if (choiceIndex === 1)
                playlistsBackend.deletePlaylist(pageRoot.playlistId)
        }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                visible = false
                list.forceActiveFocus()
                event.accepted = true
            }
        }
    }

    OnScreenKeyboard {
        id: osk
        anchors.fill: parent
        title: "Playlist Name"
        onAccepted: function(text) {
            playlistsBackend.renamePlaylist(pageRoot.playlistId, text)
            list.forceActiveFocus()
        }
        onCanceled: list.forceActiveFocus()
    }
}
