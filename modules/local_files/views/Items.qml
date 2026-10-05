import QtQuick
import Components

// Local Files browser: the media folder as a horizontal tree (see
// TreeBrowser), led by RECENTLY WATCHED, FAVORITES and SEARCH (names under the
// whole folder, typed on the on-screen keyboard). Select on a file plays it,
// right on it offers its options (EntryOptions: its favourite), and the whole
// tree is this one view: playing a file and coming back restores it from the
// listState handed to navigateTo.
FocusScope {
    id: itemsRoot

    property var navParams: ({})
    property var navListState: navParams.navListState || ({})
    // Context properties read null while the module's Loader tears this view
    // down, hence the guards.
    readonly property string rootPath: navParams.folderPath || (localFilesBackend ? localFilesBackend.mediaRoot() : "")
    readonly property bool hideExtensions: {
        var v = appCore ? appCore.get_setting(moduleRoot.moduleId, "hide_extensions") : false
        return v === true || v === "ON"
    }

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    focus: true

    // The tree's own folders, ahead of the media folder's. Their paths aren't
    // file paths, which are absolute.
    readonly property var lead: [
        { name: "Recently Watched", path: "recent", isFolder: true },
        { name: "Favorites", path: "favorites", isFolder: true },
        { name: "Search", path: "search", isFolder: false, kind: "search" }
    ]

    AppBar {
        iconSource: moduleRoot.moduleIcon
        title: moduleRoot.moduleName
        subtitle: tree.folderName
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // Empty state
    Column {
        anchors.centerIn: parent
        spacing: root.sh * 0.0333333 //16
        visible: tree.rootEmpty
        Text {
            text: "No items found"
            color: root.secondaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: root.sh * 0.05 //24
        }
        Text {
            text: "Please add items in the local files media directory"
            color: root.tertiaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: root.sh * 0.0333333 //16
        }
    }

    TreeBrowser {
        id: tree
        anchors.fill: parent
        focus: true
        visible: !rootEmpty
        rootPath: itemsRoot.rootPath
        savedTrail: itemsRoot.navListState.trail || []
        fetch: function(path, preview) {
            if (!localFilesBackend || !appCore)
                return []
            if (path === "recent" || path === "favorites")
                return localFilesBackend.existing(appCore.get_list(moduleRoot.moduleId, path))
            if (path.indexOf("search/") === 0) {
                var found = localFilesBackend.search(path, path.substring(7))
                return found === undefined ? null : found
            }
            var items = localFilesBackend.getItems(path)
            // An empty media folder has nothing to search either.
            return path === itemsRoot.rootPath && items.length > 0 ? itemsRoot.lead.concat(items) : items
        }
        labelOf: function(item) {
            if (item.isFolder || item.kind || !itemsRoot.hideExtensions) return item.name
            var dot = item.name.lastIndexOf(".")
            return dot > 0 ? item.name.substring(0, dot) : item.name
        }
        onActivated: function(item) {
            if (item.kind === "search") {
                osk.open("")
                return
            }
            appCore.add_to_list(moduleRoot.moduleId, "recent",
                                { name: item.name, path: item.path, isFolder: false }, 30)
            itemsRoot.navigateTo("Player.qml", { filePath: item.path, title: item.name },
                                 { trail: tree.trailState() })
        }
        onOptionsRequested: function(item) {
            if (!item.kind)
                options.offer({ name: item.name, path: item.path, isFolder: false })
        }
        onLeaveRequested: itemsRoot.goBack()
    }

    Connections {
        target: localFilesBackend
        function onSearchReady(path) { tree.refresh(path) }
    }

    // Footer
    HintBar {
        id: footer
        visible: !osk.visible && !options.visible
        // Select opens a folder and plays a file, and right on a file offers
        // its options rather than moving.
        readonly property var entry: tree.currentEntry
        readonly property bool onFile: !!entry && !entry.isFolder && !entry.kind
        text: root.hints.back + ":BACK "
              + (onFile ? String(root.hints.navigate).replace("]", "◄]") + ":NAVIGATE "
                          + root.hints.browse + ":OPTIONS "
                        : root.hints.arrows + ":NAVIGATE ")
              + root.hints.select
              + (onFile ? ":PLAY" : entry && entry.kind === "search" ? ":SEARCH" : ":OPEN")
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }

    OnScreenKeyboard {
        id: osk
        anchors.fill: parent
        title: "Search " + moduleRoot.moduleName
        onAccepted: function(text) {
            tree.forceActiveFocus()
            // Afresh: the folder may have changed since the same words last ran.
            var path = "search/" + text
            localFilesBackend.search(path, text, true)
            tree.refresh(path)
            tree.openItem({ name: "Search: " + text, path: path })
        }
        onCanceled: tree.forceActiveFocus()
    }

    EntryOptions {
        id: options
        anchors.fill: parent
        moduleId: moduleRoot.moduleId
        onFavoritesEdited: tree.refresh("favorites")
        onClosed: tree.forceActiveFocus()
    }
}
