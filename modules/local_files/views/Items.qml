import QtQuick
import Components

// Local Files browser, laid out as a horizontal tree. The folders on the way to
// the current one run left to right along a line through the middle of the
// screen (the spine). Each folder's contents are stacked above and below the
// item that leads on, and the folder under the cursor is previewed, dimmed, to
// the right of it before it is opened.
//
// Up/down move within the current folder, right (or select) opens a folder,
// left (or back) returns to its parent, and select on a file plays it. The
// whole tree is this one view: playing a file and coming back restores it from
// the listState handed to navigateTo.
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

    // --- Layout ---
    readonly property real fontSize: root.sh * 0.0375 //18
    readonly property real rowHeight: root.sh * 0.05 //24
    // Never a single line: on an interlaced CRT that sits on one field and flickers.
    readonly property int lineWidth: Math.max(2, Math.round(root.sh * 0.0041667)) //2
    readonly property real gap: root.sw * 0.046875 //30
    readonly property real pad: root.sw * 0.009375 //6
    readonly property real maxColumnWidth: root.sw * 0.34375 //220
    readonly property real leftEdge: root.sw * 0.125 //80
    readonly property real rightEdge: root.sw * 0.875 //560
    // How much of the preview stays on screen when the columns run out of room.
    readonly property real previewPeek: root.sw * 0.15 //96
    readonly property real treeTop: root.sh * 0.2083333 //100
    readonly property real treeBottom: root.sh * 0.8333333 //400
    // The spine, in tree-area coordinates.
    readonly property real spine: Math.round((treeBottom - treeTop) / 2)

    // --- Tree state ---
    // The open folders, root first; the last one holds the cursor.
    // Roles: path, sel (the row the spine runs through).
    ListModel { id: trail }
    readonly property int active: trail.count - 1
    // The folder under the cursor, previewed after the open ones ("" for none).
    property string previewPath: ""
    // Each folder is listed once per visit of this view.
    property var listings: ({})
    // Last cursor row per folder, so reopening one lands where it was left.
    property var remembered: ({})
    // Left edge of each open folder's column, and of the preview after them.
    property var columnX: []
    property real previewX: 0
    // Open folders left of this one are off to the left: their names are
    // hidden and the spine runs on through them from the screen's edge.
    property int firstShown: 0
    property string folderName: ""
    property bool rootEmpty: false
    property bool ready: false

    FontMetrics {
        id: metrics
        font.family: root.globalFont
        font.pixelSize: itemsRoot.fontSize
    }

    function displayName(item) {
        if (item.isFolder || !hideExtensions) return item.name
        var dot = item.name.lastIndexOf(".")
        return dot > 0 ? item.name.substring(0, dot) : item.name
    }

    // Rows are drawn upper-case, so they are measured that way.
    function textWidth(text) {
        return Math.ceil(metrics.advanceWidth(text.toUpperCase()))
    }

    function listing(path) {
        if (!path) return { items: [], width: 0 }
        var l = listings[path]
        if (!l) {
            var items = localFilesBackend.getItems(path)
            var w = items.length > 0 ? 0 : textWidth("(empty)")
            for (var i = 0; i < items.length; ++i)
                w = Math.max(w, textWidth(displayName(items[i])))
            l = { items: items, width: Math.min(maxColumnWidth, w) }
            listings[path] = l
        }
        return l
    }

    function selectedItem() {
        if (active < 0) return null
        var col = trail.get(active)
        return listing(col.path).items[col.sel] || null
    }

    function baseName(path) {
        var parts = path.split("/")
        return parts[parts.length - 1] || path
    }

    // Places the columns side by side and slides the strip so the parent
    // folder starts at the left edge, unless that would push the preview off
    // the right; then the strip slides left, but never so far that the column
    // with the cursor leaves the screen.
    function relayout() {
        var xs = []
        var x = 0
        for (var i = 0; i < trail.count; ++i) {
            xs.push(x)
            x += listing(trail.get(i).path).width + gap
        }
        columnX = xs
        previewX = x
        var activeLeft = xs[active]
        var activeRight = activeLeft + listing(trail.get(active).path).width
        var want = leftEdge - (active > 0 ? xs[active - 1] : 0)
        var room = rightEdge - (previewPath !== "" ? gap + previewPeek : 0) - activeRight
        var stripX = Math.max(leftEdge - activeLeft, Math.min(want, room))
        strip.x = stripX
        // Only the parent stays named, and only while it is wholly on screen.
        firstShown = Math.max(0, active - 1)
        if (active > 0 && xs[active - 1] + stripX < 0)
            firstShown = active
        folderName = active > 0 ? baseName(trail.get(active).path) : ""
    }

    function updatePreview() {
        var item = selectedItem()
        previewPath = item && item.isFolder ? item.path : ""
        relayout()
    }

    function move(delta) {
        var col = trail.get(active)
        var n = listing(col.path).items.length
        if (n === 0) return
        var sel = (col.sel + delta + n) % n
        trail.setProperty(active, "sel", sel)
        remembered[col.path] = sel
        // The old preview is wrong now; the new one follows once the cursor rests.
        previewPath = ""
        relayout()
        previewTimer.restart()
    }

    function openFolder() {
        var item = selectedItem()
        if (!item || !item.isFolder) return false
        previewTimer.stop()
        trail.append({ path: item.path, sel: remembered[item.path] || 0 })
        updatePreview()
        return true
    }

    function closeFolder() {
        if (active <= 0) return false
        previewTimer.stop()
        trail.remove(active)
        // The folder just left is under the cursor again, so it is the preview.
        updatePreview()
        return true
    }

    function play() {
        var item = selectedItem()
        if (!item || item.isFolder) return
        var saved = []
        for (var i = 0; i < trail.count; ++i)
            saved.push({ path: trail.get(i).path, sel: trail.get(i).sel })
        navigateTo("Player.qml", { filePath: item.path, title: item.name }, { trail: saved })
    }

    // Reopens the folders from before playback, as far as they still exist.
    function restore(saved) {
        trail.append({ path: rootPath, sel: 0 })
        for (var i = 0; i < saved.length; ++i) {
            if (saved[i].path !== trail.get(i).path) break
            var items = listing(trail.get(i).path).items
            var sel = Math.max(0, Math.min(saved[i].sel, items.length - 1))
            trail.setProperty(i, "sel", sel)
            remembered[trail.get(i).path] = sel
            var next = saved[i + 1]
            if (!next || !items[sel] || !items[sel].isFolder || items[sel].path !== next.path) break
            trail.append({ path: next.path, sel: 0 })
        }
    }

    Timer {
        id: previewTimer
        interval: 180
        onTriggered: itemsRoot.updatePreview()
    }

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Up:
            move(-1)
            break
        case Qt.Key_Down:
            move(1)
            break
        case Qt.Key_Right:
            openFolder()
            break
        case Qt.Key_Left:
            closeFolder()
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (!openFolder()) play()
            break
        case Qt.Key_Escape:
        case Qt.Key_Backspace:
        case Qt.Key_Back:
            if (!closeFolder()) goBack()
            break
        default:
            return
        }
        event.accepted = true
    }

    // One folder's column. Only the rows that fit on screen exist; they show
    // whichever entries sit around the cursor, and slide a row when it moves.
    component TreeColumn: Item {
        id: col

        property string folderPath: ""
        property int cursorIndex: 0
        // "path" (an open folder left of the cursor), "active" or "preview".
        property string role: "path"
        // Whether a line runs on from the cursor row to the next column.
        property bool leadsOn: false
        // An open folder off to the left: no names, just the spine through it.
        property bool collapsed: false
        // The next column is collapsed too, so the line runs into it unbroken.
        property bool joinsNext: false

        readonly property var entries: itemsRoot.listing(folderPath)
        readonly property var items: entries.items
        readonly property string cursorLabel: items[cursorIndex] ? itemsRoot.displayName(items[cursorIndex]) : ""
        readonly property int reach: Math.ceil(itemsRoot.spine / itemsRoot.rowHeight) + 1
        property real slide: 0
        property int lastIndex: 0

        width: entries.width
        height: parent ? parent.height : 0

        onCursorIndexChanged: {
            var delta = cursorIndex - lastIndex
            lastIndex = cursorIndex
            slideAnim.stop()
            // One row at a time slides; a wrap-around just jumps, and so does a
            // preview, whose cursor only moves when it shows another folder.
            slide = Math.abs(delta) === 1 && role !== "preview" ? delta : 0
            if (slide !== 0) slideAnim.start()
        }
        onFolderPathChanged: {
            slideAnim.stop()
            slide = 0
            lastIndex = cursorIndex
        }
        Component.onCompleted: lastIndex = cursorIndex

        NumberAnimation {
            id: slideAnim
            target: col
            property: "slide"
            to: 0
            duration: 140
            easing.type: Easing.OutCubic
        }

        Repeater {
            model: col.reach * 2 + 1

            Item {
                id: row
                required property int index
                opacity: col.collapsed ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 120 } }
                readonly property int entryIndex: col.cursorIndex + index - col.reach
                readonly property var entry: col.items[entryIndex]
                readonly property bool current: index === col.reach
                readonly property bool cursor: current && col.role === "active"
                readonly property string label: entry ? itemsRoot.displayName(entry) : ""
                readonly property color textColor: {
                    if (col.role === "preview") return root.tertiaryColor
                    if (col.role === "path") return current ? root.primaryColor : root.tertiaryColor
                    return current || (entry && entry.isFolder) ? root.primaryColor : root.secondaryColor
                }

                visible: entry !== undefined
                width: col.width
                height: itemsRoot.rowHeight
                y: itemsRoot.spine - height / 2 + (index - col.reach + col.slide) * height
                clip: cursor

                Item {
                    id: slider
                    height: parent.height

                    // The cursor: a block behind the first letter, which turns
                    // to the background colour on it.
                    Rectangle {
                        visible: row.cursor
                        anchors.verticalCenter: parent.verticalCenter
                        width: itemsRoot.textWidth(row.label.charAt(0))
                        height: itemsRoot.fontSize * 1.1
                        color: root.accentColor
                    }
                    Text {
                        id: labelText
                        anchors.verticalCenter: parent.verticalCenter
                        width: row.cursor ? implicitWidth : row.width
                        text: row.label
                        elide: row.cursor ? Text.ElideNone : Text.ElideRight
                        color: row.textColor
                        font.family: root.globalFont
                        font.capitalization: Font.AllUppercase
                        font.pixelSize: itemsRoot.fontSize
                    }
                    Text {
                        visible: row.cursor
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.label.charAt(0)
                        color: root.surfaceColor
                        font.family: root.globalFont
                        font.capitalization: Font.AllUppercase
                        font.pixelSize: itemsRoot.fontSize
                    }
                }

                // A cursor row too long for its column scrolls through.
                SequentialAnimation {
                    running: row.cursor && labelText.implicitWidth > row.width
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) slider.x = 0
                    PauseAnimation { duration: 1500 }
                    NumberAnimation {
                        target: slider
                        property: "x"
                        to: row.width - labelText.implicitWidth
                        duration: Math.abs(to) * 20
                    }
                    PauseAnimation { duration: 2000 }
                    PropertyAction { target: slider; property: "x"; value: 0 }
                }
            }
        }

        Text {
            visible: col.folderPath !== "" && col.items.length === 0
            y: itemsRoot.spine - height / 2
            text: "(empty)"
            color: root.tertiaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: itemsRoot.fontSize
        }

        // The line on from the cursor row: bright along the open folders, dim
        // into the preview.
        Rectangle {
            readonly property real start: col.collapsed ? 0
                : Math.min(col.width, itemsRoot.textWidth(col.cursorLabel)) + itemsRoot.pad
            visible: col.leadsOn && col.items.length > 0
            x: start
            y: itemsRoot.spine - height / 2
            width: Math.max(0, col.width + itemsRoot.gap - (col.joinsNext ? 0 : itemsRoot.pad) - start)
            height: itemsRoot.lineWidth
            color: col.role === "path" ? root.accentColor : root.tertiaryColor
        }
    }

    // ---
    // UI
    // ---

    // Header
    AppBar {
        iconSource: moduleRoot.moduleIcon
        title: moduleRoot.moduleName
        subtitle: itemsRoot.folderName
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125 //60
        anchors.leftMargin: root.sw * 0.125 //80
    }

    // Empty state
    Column {
        anchors.centerIn: parent
        spacing: root.sh * 0.0333333 //16
        visible: itemsRoot.rootEmpty
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

    // The tree
    Item {
        y: itemsRoot.treeTop
        width: parent.width
        height: itemsRoot.treeBottom - itemsRoot.treeTop
        clip: true
        visible: !itemsRoot.rootEmpty

        Item {
            id: strip
            height: parent.height
            Behavior on x {
                enabled: itemsRoot.ready
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Repeater {
                model: trail
                TreeColumn {
                    required property int index
                    required property string path
                    required property int sel
                    x: itemsRoot.columnX[index] !== undefined ? itemsRoot.columnX[index] : 0
                    folderPath: path
                    cursorIndex: sel
                    role: index === itemsRoot.active ? "active" : "path"
                    leadsOn: index < itemsRoot.active || itemsRoot.previewPath !== ""
                    collapsed: index < itemsRoot.firstShown
                    joinsNext: index + 1 < itemsRoot.firstShown
                }
            }

            TreeColumn {
                visible: itemsRoot.previewPath !== ""
                x: itemsRoot.previewX
                folderPath: itemsRoot.previewPath
                cursorIndex: itemsRoot.remembered[itemsRoot.previewPath] || 0
                role: "preview"
            }
        }
    }

    Component.onCompleted: {
        restore(navListState.trail || [])
        rootEmpty = listing(rootPath).items.length === 0
        updatePreview()
        ready = true
    }

    // Footer
    HintBar {
        id: footer
        text: root.hints.back + ":BACK " + root.hints.navigate + ":NAVIGATE " + root.hints.select + ":SELECT"
        font.family: root.globalFont
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667 //50
        anchors.leftMargin: root.sw * 0.125 //80
        font.pixelSize: root.sh * 0.0333333 //16
    }
}
