import QtQuick
import Components

// Adding videos to a playlist from inside the module: the sources as one
// tree, each browsed the way its own module browses it. LOCAL FILES (its
// RECENTLY WATCHED, FAVORITES and folders), YOUTUBE (its RECENTLY WATCHED,
// FAVORITES, SEARCH and the rest of its home), JELLYFIN and EMBY (CONTINUE
// WATCHING, NEXT UP and the libraries, down to their shows' seasons), each
// where its module is on (a server, signed in to). Select on a video adds it
// and stays, so several go on in a row; the line above the hints says what
// became of the last one.
FocusScope {
    id: addRoot

    property var navParams: ({})
    readonly property string playlistId: navParams.playlistId || ""
    readonly property string playlistName: navParams.playlistName || ""
    readonly property bool offline: navParams.kind === "offline"

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    // What became of the last video selected.
    property string outcome: ""

    readonly property string kLocal: "com.240mp.local_files"
    readonly property string kYouTube: "com.240mp.youtube"
    readonly property string kJellyfin: "com.240mp.jellyfin"
    readonly property string kEmby: "com.240mp.emby"
    // A server's paths: its module, by the prefix they start with.
    readonly property var servers: ({ "jf": "com.240mp.jellyfin", "em": "com.240mp.emby" })

    // As the YouTube module shows them: Shorts only with DISPLAY SHORTS on.
    readonly property bool showShorts: {
        var raw = appCore ? appCore.get_setting(kYouTube, "display_shorts") : undefined
        return raw === undefined || raw === null || raw === true || raw === "ON"
    }

    function sources() {
        var out = []
        if (appCore.is_module_enabled(kLocal) && typeof localFilesBackend !== "undefined" && localFilesBackend)
            out.push({ name: "Local Files", path: "local", isFolder: true })
        if (appCore.is_module_enabled(kYouTube) && typeof youtubeBackend !== "undefined" && youtubeBackend)
            out.push({ name: "YouTube", path: "yt", isFolder: true })
        if (appCore.is_module_enabled(kJellyfin) && typeof jellyfinBackend !== "undefined" && jellyfinBackend
                && jellyfinBackend.has_auth())
            out.push({ name: "Jellyfin", path: "jf", isFolder: true })
        if (appCore.is_module_enabled(kEmby) && typeof embyBackend !== "undefined" && embyBackend
                && embyBackend.has_auth())
            out.push({ name: "Emby", path: "em", isFolder: true })
        return out
    }

    // A module's entries as this tree has them: folders under its own paths,
    // videos with their module and the entry as the module gave it.
    function localEntries(entries) {
        return entries.map(function(e) {
            return e.isFolder ? { name: e.name, path: "local:dir:" + e.path, isFolder: true }
                              : { name: e.name, path: "local:file:" + e.path, isFolder: false,
                                  kind: "video", module: kLocal, entry: e }
        })
    }
    function youtubeEntries(entries) {
        if (!showShorts)
            entries = entries.filter(function(e) { return !e.isShort })
        return entries.map(function(e) {
            if (e.isFolder)
                return { name: e.name, path: "yt:" + e.path, isFolder: true }
            if (e.kind === "video")
                return { name: e.name, path: "yt:video:" + e.path, isFolder: false,
                         kind: "video", module: kYouTube, entry: e }
            // SEARCH and MORE, acted on as the YouTube module's tree does.
            return { name: e.name, path: "yt:" + e.path, isFolder: false, kind: e.kind, entry: e }
        })
    }
    function serverEntries(prefix, items) {
        var moduleId = servers[prefix]
        return items.map(function(e) {
            if (e.isFolder)
                return { name: e.name, path: prefix + ":" + e.itemId, isFolder: true }
            // An episode out of its season (CONTINUE WATCHING, NEXT UP): with its show.
            var shown = e.seriesName && e.name === e.title ? e.seriesName + " - " + e.name : e.name
            return { name: shown, path: prefix + ":item:" + e.itemId, isFolder: false,
                     kind: "video", module: moduleId, entry: e }
        })
    }

    function fetch(path, preview) {
        if (!appCore || !playlistsBackend)
            return []
        if (path === "sources")
            return sources()

        // Local Files
        if (path === "local")
            return [{ name: "Recently Watched", path: "local:recent", isFolder: true },
                    { name: "Favorites", path: "local:favorites", isFolder: true }]
                   .concat(localEntries(localFilesBackend.getItems(localFilesBackend.mediaRoot())))
        if (path === "local:recent" || path === "local:favorites")
            return localEntries(localFilesBackend.existing(appCore.get_list(kLocal, path.substring(6))))
        if (path.indexOf("local:dir:") === 0)
            return localEntries(localFilesBackend.getItems(path.substring(10)))

        // YouTube
        if (path === "yt") {
            var home = youtubeBackend.listing("home", preview)
            if (home === undefined)
                return null
            return [{ name: "Recently Watched", path: "yt:history", isFolder: true },
                    { name: "Favorites", path: "yt:favorites", isFolder: true }].concat(youtubeEntries(home))
        }
        if (path === "yt:favorites")
            return youtubeEntries(appCore.get_list(kYouTube, "favorites"))
        if (path.indexOf("yt:") === 0) {
            var listing = youtubeBackend.listing(path.substring(3), preview)
            return listing === undefined ? null : youtubeEntries(listing)
        }

        // Jellyfin and Emby
        var prefix = path.substring(0, 2)
        if (servers[prefix] !== undefined) {
            var parentId = path.length > 3 ? path.substring(3) : ""
            var items = playlistsBackend.serverListing(servers[prefix], parentId, preview)
            if (items === undefined)
                return null
            var entries = serverEntries(prefix, items)
            if (parentId === "")
                entries = [{ name: "Continue Watching", path: prefix + ":resume", isFolder: true },
                           { name: "Next Up", path: prefix + ":nextup", isFolder: true }].concat(entries)
            return entries
        }
        return []
    }

    function add(item) {
        var result = playlistsBackend.addEntry(playlistId, item.module, item.entry)
        outcome = result.ok ? (offline && item.module !== kLocal ? "Added, to download: " : "Added: ") + result.title
                : result.reason === "duplicate" ? "Already on " + playlistName + ": " + result.title
                : "This one can't go on a playlist"
    }

    // The servers' folders as they are now, not as they were last time.
    Component.onCompleted: {
        if (playlistsBackend)
            playlistsBackend.forgetListings()
    }

    AppBar {
        iconSource: moduleRoot.moduleIcon
        title: moduleRoot.moduleName
        subtitle: "Add to " + addRoot.playlistName
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    TreeBrowser {
        id: tree
        anchors.fill: parent
        focus: !osk.visible
        rootPath: "sources"
        reservedBottom: treeBottom - helpLine.y
        fetch: function(path, preview) { return addRoot.fetch(path, preview) }
        onActivated: function(item) {
            if (item.kind === "video")
                addRoot.add(item)
            else if (item.kind === "search")
                osk.open("")
            else if (item.kind === "more")
                youtubeBackend.loadMore(item.entry.path.replace("#more", ""))
        }
        onCurrentEntryChanged: addRoot.outcome = ""
        onLeaveRequested: addRoot.goBack()
    }

    Connections {
        target: typeof youtubeBackend !== "undefined" ? youtubeBackend : null
        ignoreUnknownSignals: true
        function onListingReady(path) {
            tree.refresh("yt:" + path)
            if (path === "home")
                tree.refresh("yt")
        }
    }
    Connections {
        target: playlistsBackend
        function onServerListingReady(moduleId, parentId) {
            var prefix = moduleId === addRoot.kJellyfin ? "jf" : "em"
            tree.refresh(parentId === "" ? prefix : prefix + ":" + parentId)
        }
    }

    HelpLine {
        id: helpLine
        visible: !osk.visible
        text: addRoot.outcome !== "" ? addRoot.outcome
              : tree.currentEntry && tree.currentEntry.kind === "video"
                ? (addRoot.offline && tree.currentEntry.module !== addRoot.kLocal
                   ? "Select adds it to " + addRoot.playlistName + ", to download once"
                   : "Select adds it to " + addRoot.playlistName)
              : "Choose the videos to add"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1583333 //76
        anchors.leftMargin: root.sw * 0.125 //80
    }

    HintBar {
        visible: !osk.visible
        readonly property var entry: tree.currentEntry
        text: root.hints.back + ":BACK " + root.hints.arrows + ":NAVIGATE " + root.hints.select
              + (!entry || entry.isFolder ? ":OPEN"
                 : entry.kind === "video" ? ":ADD"
                 : entry.kind === "search" ? ":SEARCH" : ":MORE")
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
            tree.openItem({ name: "Search: " + text, path: "yt:search/" + text })
        }
        onCanceled: tree.forceActiveFocus()
    }
}
