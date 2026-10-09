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

    // a payload can ask for a glitch right away, to see one:
    //   omarchy-shell shell summon globe-launcher '{"glitch":"vhs"}'
    // or for a traffic level: '{"net":0.8}'
    function open(payloadJson) {
        root.opened = true
        Qt.callLater(function() { view.forceActiveFocus() })
        let p = {}
        try { p = typeof payloadJson === "string" ? JSON.parse(payloadJson || "{}") : (payloadJson || {}) } catch (e) {}
        if (p.glitch) { glitchSoon.kind = String(p.glitch); glitchSoon.restart() }
        // ...or a level of network traffic (0..1) to draw, whatever the real one
        view.netTest = Number(p.net) || 0
    }
    Timer { id: glitchSoon; property string kind: ""; interval: 700; onTriggered: view.fireGlitch(kind) }

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
