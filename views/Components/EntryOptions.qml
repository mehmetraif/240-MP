import QtQuick

// An entry's options, from right on it in a tree (or on its info screen): put
// it on the module's FAVORITES, or take it off, and make it the favourite the
// app plays straight after the boot screen (PLAY AT STARTUP). A host can offer
// its own as well (moreChoices, acted on in onActivated as with any
// ChoiceOverlay), and refreshes its FAVORITES folder on favoritesEdited.
// FAVORITES is one of the module's lists in AppCore (get_list(moduleId,
// "favorites")), keeping the entries as offer() was given them; the startup
// favourite is the app setting "startup_favorite": { module, path, name }.
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
    // Whether it is the startup favourite.
    property bool atStartup: false
    // The host's own, after FAVORITES': [{ label, action }].
    property var moreChoices: []

    signal favoritesEdited()

    function offer(item) {
        entry = item
        favorite = appCore.list_contains(moduleId, "favorites", item.path)
        var startup = appCore.get_setting("", "startup_favorite")
        atStartup = !!startup && startup.module === moduleId && startup.path === item.path
        open()
    }

    promptText: "Options"
    subtitleText: entry ? (entry.title || entry.name || "") : ""
    choices: [{ label: favorite ? "Remove from Favorites" : "Add to Favorites", action: "favorite" },
              { label: atStartup ? "Don't Play at Startup" : "Play at Startup", action: "startup" }]
             .concat(moreChoices)

    onActivated: function(action) {
        if (!entry)
            return
        if (action === "favorite") {
            if (favorite) {
                appCore.remove_from_list(moduleId, "favorites", entry.path)
                // The startup favourite is one of the favourites.
                if (atStartup)
                    appCore.save_setting("", "startup_favorite", "")
            } else {
                appCore.add_to_list(moduleId, "favorites", entry, 100)
            }
            favoritesEdited()
        } else if (action === "startup") {
            if (atStartup) {
                appCore.save_setting("", "startup_favorite", "")
                return
            }
            // Played at startup from FAVORITES, so it goes there too.
            if (!favorite) {
                appCore.add_to_list(moduleId, "favorites", entry, 100)
                favoritesEdited()
            }
            appCore.save_setting("", "startup_favorite",
                                 { module: moduleId, path: entry.path, name: entry.title || entry.name || "" })
        }
    }
}
