import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

// The overlay: Globe-Launcher over the whole screen, taking the keyboard.
//   omarchy-shell shell toggle globe-launcher '{}'
Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false

    // Quickshell reads the installed apps in the background the first time
    // anything asks; asking now has the list ready before the first opening.
    readonly property int appCount: DesktopEntries.applications ? DesktopEntries.applications.values.length : 0

    function open(payloadJson) {
        root.opened = true
        Qt.callLater(function() { view.forceActiveFocus() })
    }

    function close() {
        root.opened = false
    }

    function dismiss() {
        root.opened = false
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide((root.manifest && root.manifest.id) || "globe-launcher")
    }

    function toggle() {
        if (root.opened) root.dismiss()
        else root.open("{}")
    }

    PanelWindow {
        id: panel
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "black"
        WlrLayershell.namespace: "globe-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        GlobeView {
            id: view
            anchors.fill: parent
            active: root.opened
            focus: true
            closeRequest: function() { root.dismiss() }
            onLaunched: root.dismiss()
        }
    }
}
