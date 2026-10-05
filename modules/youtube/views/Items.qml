import QtQuick
import Components

// YouTube in the tree, browsed like Local Files: SEARCH (on the on-screen
// keyboard), the subscriptions feed, each channel and playlist, Watch Later and
// History, from youtubeBackend.listing(). A video plays in Player.qml, and
// coming back reopens the same folders. Right on a video opens its info screen
// (InfoPanel), the tree's last layer, as the cursor resting on it does after
// the app's INFO SCREEN setting's seconds; right there saves it to Watch Later,
// or takes it off. With the info screen off, right on the video does that.
FocusScope {
    id: itemsRoot

    property var navParams: ({})
    property var navListState: navParams.navListState || ({})

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    focus: true

    // The app's INFO SCREEN setting: "off", "key" (right only) or seconds.
    readonly property string infoSetting: (appCore ? appCore.get_setting("", "info_screen") : "") || "3"

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
        preview: itemsRoot.infoSetting !== "off"
        previewDelay: (parseInt(itemsRoot.infoSetting) || 0) * 1000
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
        onPreviewRequested: function(item) {
            if (item.kind !== "video")
                return
            info.show(item)
            info.loading = true
            youtubeBackend.loadDetails(item)
        }
        onLeaveRequested: itemsRoot.goBack()
    }

    Connections {
        target: youtubeBackend
        function onListingReady(path) { tree.refresh(path) }
        function onDetailsReady(path, details) {
            if (!info.item || info.item.path !== path)
                return
            info.details = details
            info.loading = !details.complete
        }
    }

    // What stands in the way of browsing, when anything does: no network, or
    // no yt-dlp.
    HelpLine {
        id: problemLine
        visible: !osk.visible && !watchLater.visible && !info.visible && text !== ""
        text: youtubeBackend ? youtubeBackend.problem : ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1583333 //76
        anchors.leftMargin: root.sw * 0.125 //80
    }

    HintBar {
        visible: !osk.visible && !watchLater.visible && !info.visible
        // What select does with the entry under the cursor: a video plays,
        // and right opens its info (or saves it, with the info screen off)
        // rather than moving.
        readonly property var entry: tree.currentEntry
        readonly property bool onVideo: !!entry && entry.kind === "video"
        text: root.hints.back + ":BACK "
              + (onVideo ? String(root.hints.navigate).replace("]", "\u25C4]") + ":NAVIGATE "
                           + root.hints.browse + (tree.preview ? ":INFO " : ":SAVE ")
                         : root.hints.arrows + ":NAVIGATE ")
              + root.hints.select
              + (onVideo ? ":PLAY"
                 : !entry || entry.isFolder ? ":OPEN"
                 : entry.kind === "search" ? ":SEARCH"
                 : entry.kind === "more" ? ":MORE" : ":OPEN")
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

    // A video's info: the tree's last layer. Right there saves it.
    InfoPanel {
        id: info
        anchors.fill: parent
        saveHint: root.hints.browse + ":SAVE"
        onPlayRequested: function(item) {
            itemsRoot.navigateTo("Player.qml", { item: item }, { trail: tree.trailState() })
        }
        onSaveRequested: function(item) { watchLater.offer(item) }
        onMoveRequested: function(delta) { tree.move(delta) }
        onClosed: tree.forceActiveFocus()
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
        // Back to the info screen when it was opened from there.
        onClosed: info.visible ? info.forceActiveFocus() : tree.forceActiveFocus()
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
