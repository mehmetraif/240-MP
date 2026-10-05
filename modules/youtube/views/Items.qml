import QtQuick
import Components

// YouTube in the tree, browsed like Local Files: SEARCH (on the on-screen
// keyboard), the subscriptions feed, each channel and playlist, Watch Later and
// History, from youtubeBackend.listing(). A video plays in Player.qml, and
// coming back reopens the same folders. Right on a video saves it to Watch
// Later, or takes it off.
FocusScope {
    id: itemsRoot

    property var navParams: ({})
    property var navListState: navParams.navListState || ({})

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    focus: true

    // Shorts are left out when the "Display Shorts" setting is off.
    // Unset/true/"ON" => show shorts (default); explicit false => hide.
    readonly property bool showShorts: {
        var raw = appCore ? appCore.get_setting(moduleRoot.moduleId, "display_shorts") : undefined
        return raw === undefined || raw === null || raw === true || raw === "ON"
    }

    AppBar {
        iconSource: moduleRoot.moduleIcon
        title: moduleRoot.moduleName
        subtitle: tree.folderName
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    TreeBrowser {
        id: tree
        anchors.fill: parent
        focus: true
        rootPath: "home"
        reservedBottom: problemLine.visible ? treeBottom - problemLine.y : 0
        savedTrail: itemsRoot.navListState.trail || []
        fetch: function(path, preview) {
            var entries = youtubeBackend.listing(path, preview)
            if (entries === undefined)
                return null
            return itemsRoot.showShorts ? entries : entries.filter(function(e) { return !e.isShort })
        }
        onActivated: function(item) {
            switch (item.kind) {
            case "search":
                osk.open("")
                break
            case "more":
                youtubeBackend.loadMore(item.path.replace("#more", ""))
                break
            case "video":
                itemsRoot.navigateTo("Player.qml", { item: item }, { trail: tree.trailState() })
                break
            }
        }
        onOptionsRequested: function(item) {
            if (item.kind === "video")
                watchLater.offer(item)
        }
        onLeaveRequested: itemsRoot.goBack()
    }

    Connections {
        target: youtubeBackend
        function onListingReady(path) { tree.refresh(path) }
    }

    // What stands in the way of browsing, when anything does: no network, or
    // no yt-dlp.
    HelpLine {
        id: problemLine
        visible: !osk.visible && !watchLater.visible && text !== ""
        text: youtubeBackend ? youtubeBackend.problem : ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1583333 //76
        anchors.leftMargin: root.sw * 0.125 //80
    }

    HintBar {
        visible: !osk.visible && !watchLater.visible
        text: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE "
              + root.hints.browse + ":SAVE " + root.hints.select + ":SELECT"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }

    OnScreenKeyboard {
        id: osk
        anchors.fill: parent
        title: "Search YouTube"
        onAccepted: function(text) {
            tree.forceActiveFocus()
            tree.openItem({ name: "Search: " + text, path: "search/" + text })
        }
        onCanceled: tree.forceActiveFocus()
    }

    // Save to Watch Later, or take off it what is already there.
    ChoiceOverlay {
        id: watchLater
        property var video: null
        property bool saved: false

        function offer(item) {
            video = item
            saved = youtubeBackend.isInWatchLater(item.videoId)
            open()
        }

        anchors.fill: parent
        promptText: saved ? "Remove from Watch Later?" : "Save to Watch Later?"
        subtitleText: video ? video.title : ""
        choices: [{ label: "Yes", action: "yes" }, { label: "No", action: "no" }]
        onClosed: tree.forceActiveFocus()
        onActivated: function(action) {
            if (action !== "yes" || !video)
                return
            if (saved)
                youtubeBackend.removeFromWatchLater(video.videoId)
            else
                youtubeBackend.addToWatchLater(video.videoId, video.title || "", video.channelName || "")
            // WATCH LATER comes and goes with what is on it.
            tree.refresh("watchlater")
            tree.refresh("home")
        }
    }
}
