import QtQuick

// An entry's options, from right on it in a tree (or on its info screen): put
// it on the module's FAVORITES, or take it off. A host can offer its own as
// well (moreChoices, acted on in onActivated as with any ChoiceOverlay), and
// refreshes its FAVORITES folder on favoritesEdited. FAVORITES is one of the
// module's lists in AppCore (get_list(moduleId, "favorites")), keeping the
// entries as offer() was given them.
//
//     EntryOptions {
//         id: options
//         anchors.fill: parent
//         moduleId: moduleRoot.moduleId
//         onFavoritesEdited: tree.refresh("favorites")
//         onClosed: tree.forceActiveFocus()
//     }
//     … options.offer(item)
ChoiceOverlay {
    id: options

    property string moduleId: ""
    // The entry the options are for.
    property var entry: null
    property bool favorite: false
    // The host's own, after FAVORITES': [{ label, action }].
    property var moreChoices: []

    signal favoritesEdited()

    function offer(item) {
        entry = item
        favorite = appCore.list_contains(moduleId, "favorites", item.path)
        open()
    }

    promptText: "Options"
    subtitleText: entry ? (entry.title || entry.name || "") : ""
    choices: [{ label: favorite ? "Remove from Favorites" : "Add to Favorites", action: "favorite" }]
             .concat(moreChoices)

    onActivated: function(action) {
        if (action !== "favorite" || !entry)
            return
        if (favorite)
            appCore.remove_from_list(moduleId, "favorites", entry.path)
        else
            appCore.add_to_list(moduleId, "favorites", entry, 100)
        favoritesEdited()
    }
}
