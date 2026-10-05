import QtQuick

// A web player module's catalogue (Netflix, Prime Video), browsed in a
// TreeBrowser before the service's own player opens: SEARCH, MOVIES and SERIES
// by genre, and the service's home page. The entries come from the backend's
// TmdbCatalog. Choosing a title, or the home page, opens it in Launch.qml, and
// coming back reopens the same folders. A title's info screen (InfoPanel) is
// the tree's last layer: right on it, or the cursor resting on it as long as
// the app's INFO SCREEN setting says.
//
// A module's Browse.qml is just this, with its backend and name:
//     WebPlayerBrowse { backend: netflixBackend; serviceName: "Netflix" }
FocusScope {
    id: browse

    property var navParams: ({})
    property var navListState: navParams.navListState || ({})
    // The module's WebPlayerBackend.
    property var backend: null
    property string serviceName: ""
    readonly property var catalog: backend ? backend.catalog : null

    signal navigateTo(string path, var params, var listState)
    signal goBack()

    focus: true

    function open(params) {
        navigateTo("Launch.qml", params, { trail: tree.trailState() })
    }

    // The app's INFO SCREEN setting: "off", "key" (right only) or seconds.
    readonly property string infoSetting: (appCore ? appCore.get_setting("", "info_screen") : "") || "3"

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
        preview: browse.infoSetting !== "off"
        previewDelay: (parseInt(browse.infoSetting) || 0) * 1000
        savedTrail: browse.navListState.trail || []
        fetch: function(path, preview) {
            return browse.catalog ? browse.catalog.listing(path, preview) : []
        }
        onActivated: function(item) {
            switch (item.kind) {
            case "search":
                osk.open("")
                break
            case "more":
                browse.catalog.loadMore(item.path.replace("#more", ""))
                break
            case "home":
                browse.open({ name: browse.serviceName })
                break
            case "title":
                browse.open({ item: item, name: item.name })
                break
            }
        }
        onPreviewRequested: function(item) {
            if (item.kind !== "title" || !browse.catalog)
                return
            info.show(item)
            info.loading = true
            browse.catalog.loadDetails(item)
        }
        onLeaveRequested: browse.goBack()
    }

    Connections {
        target: browse.catalog
        function onListingReady(path) { tree.refresh(path) }
        function onDetailsReady(path, details) {
            if (!info.item || info.item.path !== path)
                return
            info.details = details
            info.loading = false
        }
    }

    // What stands in the way of browsing, when anything does: no TMDB key, or
    // no network.
    HelpLine {
        id: problemLine
        visible: !osk.visible && !info.visible && text !== ""
        text: browse.catalog ? browse.catalog.problem : ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1583333 //76
        anchors.leftMargin: root.sw * 0.125 //80
    }

    HintBar {
        visible: !osk.visible && !info.visible
        // What select does with the entry under the cursor: a title plays,
        // and right on it opens its info rather than moving.
        readonly property var entry: tree.currentEntry
        readonly property bool onTitle: !!entry && entry.kind === "title" && tree.preview
        text: root.hints.back + ":BACK "
              + (onTitle ? String(root.hints.navigate).replace("]", "\u25C4]") + ":NAVIGATE "
                           + root.hints.browse + ":INFO "
                         : root.hints.arrows + ":NAVIGATE ")
              + root.hints.select
              + (!entry || entry.isFolder ? ":OPEN"
                 : entry.kind === "title" ? ":PLAY"
                 : entry.kind === "search" ? ":SEARCH"
                 : entry.kind === "more" ? ":MORE" : ":OPEN")
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // A title's info: the tree's last layer.
    InfoPanel {
        id: info
        anchors.fill: parent
        onPlayRequested: function(item) { browse.open({ item: item, name: item.name }) }
        onMoveRequested: function(delta) { tree.move(delta) }
        onClosed: tree.forceActiveFocus()
    }

    OnScreenKeyboard {
        id: osk
        anchors.fill: parent
        title: "Search " + browse.serviceName
        onAccepted: function(text) {
            tree.forceActiveFocus()
            tree.openItem({ name: "Search: " + text, path: "search/" + text })
        }
        onCanceled: tree.forceActiveFocus()
    }
}
