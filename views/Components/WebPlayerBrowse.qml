import QtQuick

// A web player module's catalogue (Netflix, Prime Video), browsed in a
// TreeBrowser before the service's own player opens: SEARCH, MOVIES and SERIES
// by genre, and the service's home page. The entries come from the backend's
// TmdbCatalog. Choosing a title, or the home page, opens it in Launch.qml, and
// coming back reopens the same folders.
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
        onLeaveRequested: browse.goBack()
    }

    Connections {
        target: browse.catalog
        function onListingReady(path) { tree.refresh(path) }
    }

    // What stands in the way of browsing, when anything does: no TMDB key, or
    // no network.
    HelpLine {
        visible: !osk.visible && text !== ""
        text: browse.catalog ? browse.catalog.problem : ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1583333 //76
        anchors.leftMargin: root.sw * 0.125 //80
    }

    HintBar {
        visible: !osk.visible
        text: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
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
