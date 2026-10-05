import QtQuick
import Components

// Local Files browser: the media folder as a horizontal tree (see
// TreeBrowser). Select on a file plays it, and the whole tree is this one view:
// playing a file and coming back restores it from the listState handed to
// navigateTo.
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
            return localFilesBackend ? localFilesBackend.getItems(path) : []
        }
        labelOf: function(item) {
            if (item.isFolder || !itemsRoot.hideExtensions) return item.name
            var dot = item.name.lastIndexOf(".")
            return dot > 0 ? item.name.substring(0, dot) : item.name
        }
        onActivated: function(item) {
            itemsRoot.navigateTo("Player.qml", { filePath: item.path, title: item.name },
                                 { trail: tree.trailState() })
        }
        onLeaveRequested: itemsRoot.goBack()
    }

    // Footer
    HintBar {
        id: footer
        text: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
    }
}
