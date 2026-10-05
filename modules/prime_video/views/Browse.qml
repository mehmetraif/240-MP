import QtQuick
import Components

// Prime Video's catalogue in the tree, before its own player opens: see
// WebPlayerBrowse.
WebPlayerBrowse {
    backend: primeVideoBackend
    serviceName: "Prime Video"
}
