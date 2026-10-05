import QtQuick
import Components

// Netflix's catalogue in the tree, before its own player opens: see
// WebPlayerBrowse.
WebPlayerBrowse {
    backend: netflixBackend
    serviceName: "Netflix"
}
