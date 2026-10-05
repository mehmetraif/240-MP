import QtQuick
import Components

// Local Files browser, laid out as a horizontal tree. The folders on the way to
// the current one run left to right along a line through the middle of the
// screen (the spine). Each folder's contents are stacked above and below the
// item that leads on. Every folder in the current one branches off to the
// right, on a dotted line to a few of its own entries, and the folder under
// the cursor branches once more, from each folder in it.
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
    readonly property real treeTop: root.sh * 0.2083333 //100
    readonly property real treeBottom: root.sh * 0.8333333 //400
    // The spine, in tree-area coordinates.
    readonly property real spine: Math.round((treeBottom - treeTop) / 2)
    // Branches: the gap before each level leaves room for the lanes their
    // lines turn in, one a line's width apart from the next.
    readonly property real branchGap: root.sw * 0.0625 //40
    readonly property real laneStep: 2 * lineWidth
    readonly property real blockGap: Math.round(rowHeight / 2)
    // Entries a branch shows: a window around the remembered row for the folder
    // under the cursor, the first few for the others.
    readonly property int anchorRows: 5
    readonly property int branchRows: 3

    // --- Tree state ---
    // The open folders, root first; the last one holds the cursor.
    // Roles: path, sel (the row the spine runs through).
    ListModel { id: trail }
    readonly property int active: trail.count - 1
    // Each folder is listed once per visit of this view.
    property var listings: ({})
    // Last cursor row per folder, so reopening one lands where it was left.
    property var remembered: ({})
    // Left edge of each open folder's column.
    property var columnX: []
    // The branches off the current folder, in strip coordinates with y from the
    // spine: blocks of entries { x, top, width, rows: [{ label }] }, the dotted
    // lines to them { x0, y0, x1, y1, lane }, and how far right they reach.
    property var blocks: []
    property var wires: []
    property real branchLeft: 0
    property real branchRight: 0
    property bool branched: false
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

    // Places the columns side by side.
    function placeColumns() {
        var xs = []
        var x = 0
        for (var i = 0; i < trail.count; ++i) {
            xs.push(x)
            x += listing(trail.get(i).path).width + gap
        }
        columnX = xs
    }

    // Slides the strip so the parent folder starts at the left edge, unless
    // that would push the branches off the right; then the strip slides left,
    // but never so far that the column with the cursor leaves the screen. The
    // branches come before the parent, which the spine still runs in from.
    // Only opening and closing folders move it.
    function placeStrip() {
        var activeLeft = columnX[active]
        var right = Math.max(activeLeft + listing(trail.get(active).path).width, branchRight)
        var want = leftEdge - (active > 0 ? columnX[active - 1] : 0)
        var stripX = Math.max(leftEdge - activeLeft, Math.min(want, rightEdge - right))
        strip.x = stripX
        // Only the parent stays named, and only while it is wholly on screen.
        firstShown = Math.max(0, active - 1)
        if (active > 0 && columnX[active - 1] + stripX < 0)
            firstShown = active
        folderName = active > 0 ? baseName(trail.get(active).path) : ""
    }

    // A block of a folder's entries for a branch: a window of anchorRows
    // around entry `around`, or with around < 0 its first few, the last of
    // them "…" when there are more. null for an empty folder off the spine.
    function blockFor(path, around) {
        var items = listing(path).items
        var rows = []
        var offset = 0
        if (items.length === 0) {
            if (around < 0) return null
            rows.push({ label: "(empty)" })
        } else if (around >= 0) {
            var r = Math.min(around, items.length - 1)
            var first = Math.max(0, Math.min(r - Math.floor(anchorRows / 2), items.length - anchorRows))
            for (var i = first; i < Math.min(items.length, first + anchorRows); ++i)
                rows.push({ label: displayName(items[i]), item: items[i] })
            offset = r - first
        } else {
            var shown = items.length > branchRows ? branchRows - 1 : items.length
            for (var j = 0; j < shown; ++j)
                rows.push({ label: displayName(items[j]), item: items[j] })
            if (items.length > branchRows)
                rows.push({ label: "\u2026" })
        }
        var w = 0
        for (var k = 0; k < rows.length; ++k)
            w = Math.max(w, textWidth(rows[k].label))
        return { path: path, rows: rows, offset: offset, width: Math.min(maxColumnWidth, w) }
    }

    // One level of branches. parents: the folders it branches from, top to
    // bottom, { path, y, end } with y the middle of the folder's row and end
    // where a line can leave it. The one on the spine keeps its remembered
    // entry on the spine; every other block grows away from the spine from
    // its folder's row, as near to it as the block before it allows. A line
    // that has to turn does it in a lane of its own, the farther from the
    // spine the further left, so no two lines cross.
    function branchLevel(parents, laneLeft, x) {
        var level = { blocks: [], wires: [], width: 0, anchor: null }
        var top = -rowHeight / 2
        var bottom = rowHeight / 2
        var above = []
        var below = []
        for (var i = 0; i < parents.length; ++i) {
            var p = parents[i]
            if (Math.abs(p.y) < 1) {
                var a = blockFor(p.path, remembered[p.path] || 0)
                a.top = -(a.offset + 0.5) * rowHeight
                top = a.top
                bottom = a.top + a.rows.length * rowHeight
                level.anchor = a
                level.blocks.push(a)
                level.wires.push({ x0: p.end, y0: 0, x1: x - pad, y1: 0, lane: -1 })
            } else if (p.y < 0) {
                above.unshift(p)
            } else {
                below.push(p)
            }
        }
        var sides = [{ list: above, up: true }, { list: below, up: false }]
        for (var s = 0; s < sides.length; ++s) {
            var limit = sides[s].up ? top - blockGap : bottom + blockGap
            var turning = []
            for (var j = 0; j < sides[s].list.length; ++j) {
                var q = sides[s].list[j]
                var b = blockFor(q.path, -1)
                if (!b) continue
                var h = b.rows.length * rowHeight
                var target
                if (sides[s].up) {
                    b.top = Math.min(q.y + rowHeight / 2, limit) - h
                    target = b.top + h - rowHeight / 2
                } else {
                    b.top = Math.max(q.y - rowHeight / 2, limit)
                    target = b.top + rowHeight / 2
                }
                // A line ending on another entry's row would read as that
                // entry's, so such a block moves half a row further out.
                var phase = ((target % rowHeight) + rowHeight) % rowHeight
                if (Math.abs(target - q.y) >= 1 && (phase < 1 || phase > rowHeight - 1)) {
                    var shift = sides[s].up ? -rowHeight / 2 : rowHeight / 2
                    b.top += shift
                    target += shift
                }
                limit = sides[s].up ? b.top - blockGap : b.top + h + blockGap
                level.blocks.push(b)
                var wire = { x0: q.end, y0: q.y, x1: x - pad, y1: target, lane: -1 }
                level.wires.push(wire)
                if (Math.abs(target - q.y) >= 1)
                    turning.push(wire)
            }
            // Nearest first in `turning`, so the farthest gets lane 0. The
            // lanes stop a step short of the blocks; past that they share one.
            var lastLane = Math.max(0, Math.floor((x - laneLeft - 2 * pad) / laneStep) - 1)
            for (var t = 0; t < turning.length; ++t)
                turning[t].lane = laneLeft + pad + Math.min(turning.length - 1 - t, lastLane) * laneStep
        }
        for (var m = 0; m < level.blocks.length; ++m) {
            level.blocks[m].x = x
            level.width = Math.max(level.width, level.blocks[m].width)
        }
        return level
    }

    // Lays out the branches off the folder with the cursor: one level from
    // every folder in it that is near enough to show, and a second from each
    // folder in the block under the cursor.
    function layoutBranches() {
        var col = trail.get(active)
        var items = listing(col.path).items
        var colX = columnX[active]
        var colW = listing(col.path).width
        var reach = Math.ceil(spine / rowHeight) + 1
        var parents = []
        for (var i = Math.max(0, col.sel - reach); i < Math.min(items.length, col.sel + reach + 1); ++i) {
            if (!items[i].isFolder) continue
            var name = Math.min(colW, textWidth(displayName(items[i])))
            parents.push({
                path: items[i].path,
                y: (i - col.sel) * rowHeight,
                // The cursor's box reaches a pad further than a name does.
                end: colX + name + (i === col.sel ? 2 : 1) * pad
            })
        }
        var x1 = colX + colW + branchGap
        var first = branchLevel(parents, colX + colW, x1)
        var all = first.blocks.slice()
        var lines = first.wires.slice()
        var right = first.blocks.length > 0 ? x1 + first.width : 0
        var a = first.anchor
        if (a) {
            var x2 = x1 + first.width + branchGap
            var next = []
            for (var k = 0; k < a.rows.length; ++k) {
                var entry = a.rows[k].item
                if (!entry || !entry.isFolder) continue
                next.push({
                    path: entry.path,
                    y: a.top + (k + 0.5) * rowHeight,
                    end: x1 + Math.min(a.width, textWidth(a.rows[k].label)) + pad
                })
            }
            var second = branchLevel(next, x1 + first.width, x2)
            all = all.concat(second.blocks)
            lines = lines.concat(second.wires)
            if (second.blocks.length > 0)
                right = x2 + second.width
        }
        branchLeft = colX
        branchRight = right
        blocks = all
        wires = lines
        branched = true
    }

    function clearBranches() {
        branched = false
        blocks = []
        wires = []
    }

    function move(delta) {
        var col = trail.get(active)
        var n = listing(col.path).items.length
        if (n === 0) return
        var sel = (col.sel + delta + n) % n
        trail.setProperty(active, "sel", sel)
        remembered[col.path] = sel
        // The branches are wrong now; new ones grow once the cursor rests.
        clearBranches()
        branchTimer.restart()
    }

    // After opening or closing a folder: the columns, its branches, and the
    // strip slid to show them.
    function relayout() {
        branchTimer.stop()
        placeColumns()
        layoutBranches()
        placeStrip()
    }

    function openFolder() {
        var item = selectedItem()
        if (!item || !item.isFolder) return false
        trail.append({ path: item.path, sel: remembered[item.path] || 0 })
        relayout()
        return true
    }

    function closeFolder() {
        if (active <= 0) return false
        trail.remove(active)
        relayout()
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
        id: branchTimer
        interval: 180
        onTriggered: itemsRoot.layoutBranches()
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
        // "path" (an open folder left of the cursor) or "active".
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
            // One row at a time slides; a wrap-around just jumps.
            slide = Math.abs(delta) === 1 ? delta : 0
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

                visible: entry !== undefined
                width: col.width
                height: itemsRoot.rowHeight
                y: itemsRoot.spine - height / 2 + (index - col.reach + col.slide) * height

                // The cursor: the row in a solid box, its name in the
                // background colour, as a deck's menu marks what is selected.
                Rectangle {
                    visible: row.cursor
                    x: -itemsRoot.pad
                    width: Math.min(labelText.implicitWidth, row.width) + 2 * itemsRoot.pad
                    height: row.height
                    color: root.primaryColor
                    antialiasing: false
                }

                Item {
                    width: row.width
                    height: row.height
                    clip: row.cursor

                    Item {
                        id: slider
                        height: parent.height
                        Text {
                            id: labelText
                            anchors.verticalCenter: parent.verticalCenter
                            width: row.cursor ? implicitWidth : row.width
                            text: row.label
                            elide: row.cursor ? Text.ElideNone : Text.ElideRight
                            color: row.cursor ? root.surfaceColor : root.primaryColor
                            font.family: root.globalFont
                            font.capitalization: Font.AllUppercase
                            font.pixelSize: itemsRoot.fontSize
                        }
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
            color: root.primaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: itemsRoot.fontSize
        }

        // The spine on from the cursor row to the next open folder.
        Rectangle {
            readonly property real start: col.collapsed ? 0
                : Math.min(col.width, itemsRoot.textWidth(col.cursorLabel)) + itemsRoot.pad
            visible: col.leadsOn && col.items.length > 0
            x: start
            y: itemsRoot.spine - height / 2
            width: Math.max(0, col.width + itemsRoot.gap - (col.joinsNext ? 0 : itemsRoot.pad) - start)
            height: itemsRoot.lineWidth
            color: root.primaryColor
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
                    leadsOn: index < itemsRoot.active
                    collapsed: index < itemsRoot.firstShown
                    joinsNext: index + 1 < itemsRoot.firstShown
                }
            }

            // The branches off the current folder, grown in once the cursor rests.
            Item {
                id: branches
                width: parent.width
                height: parent.height
                opacity: itemsRoot.branched ? 1 : 0
                Behavior on opacity {
                    enabled: itemsRoot.branched
                    NumberAnimation { duration: 120 }
                }

                // Dotted lines, on a checkerboard of the line's width so every
                // segment and corner falls on the same dots.
                Canvas {
                    id: wiresCanvas
                    readonly property real cell: itemsRoot.lineWidth
                    x: Math.floor(itemsRoot.branchLeft / cell) * cell
                    width: Math.max(1, itemsRoot.branchRight - x)
                    height: parent.height
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = root.primaryColor
                        var c = cell
                        var ox = x
                        // Cell row 0 is the spine's own line.
                        var oy = itemsRoot.spine - c / 2
                        function dots(gx0, gx1, gy0, gy1) {
                            for (var gx = Math.min(gx0, gx1); gx <= Math.max(gx0, gx1); ++gx)
                                for (var gy = Math.min(gy0, gy1); gy <= Math.max(gy0, gy1); ++gy)
                                    if ((gx + gy) % 2 === 0)
                                        ctx.fillRect(gx * c - ox, gy * c + oy, c, c)
                        }
                        var ws = itemsRoot.wires
                        for (var i = 0; i < ws.length; ++i) {
                            var w = ws[i]
                            var gy0 = Math.round(w.y0 / c)
                            var gy1 = Math.round(w.y1 / c)
                            var gx0 = Math.ceil(w.x0 / c)
                            var gx1 = Math.floor(w.x1 / c) - 1
                            if (w.lane < 0) {
                                dots(gx0, gx1, gy0, gy0)
                            } else {
                                // On a dot where it leaves the folder's row.
                                var gl = Math.round(w.lane / c)
                                if ((gl + gy0) % 2 !== 0) gl += 1
                                dots(gx0, gl, gy0, gy0)
                                dots(gl, gl, gy0, gy1)
                                dots(gl, gx1, gy1, gy1)
                            }
                        }
                    }
                    Connections {
                        target: itemsRoot
                        function onWiresChanged() { wiresCanvas.requestPaint() }
                    }
                }

                Repeater {
                    model: itemsRoot.blocks
                    Column {
                        required property var modelData
                        x: modelData.x
                        y: itemsRoot.spine + modelData.top
                        Repeater {
                            model: parent.modelData.rows
                            Text {
                                required property var modelData
                                width: Math.min(implicitWidth, itemsRoot.maxColumnWidth)
                                height: itemsRoot.rowHeight
                                verticalAlignment: Text.AlignVCenter
                                text: modelData.label
                                elide: Text.ElideRight
                                color: root.primaryColor
                                font.family: root.globalFont
                                font.capitalization: Font.AllUppercase
                                font.pixelSize: itemsRoot.fontSize
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        restore(navListState.trail || [])
        rootEmpty = listing(rootPath).items.length === 0
        relayout()
        ready = true
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
