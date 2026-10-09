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
    // opening with a glitch: the window maps see-through, the desktop is
    // captured through it, then the launcher glitches in over that capture
    property bool capturing: false
    function open(payloadJson) {
        if (view.closingFx) view.playOpening()        // reopened mid-close: straight back in
        else if (view.openingWanted && !root.opened) {
            root.capturing = true
            view.opening = 0
            deskShot.captureFrame()
            captureWait.tries = 0
            captureWait.restart()
        }
        root.opened = true
        Qt.callLater(function() { view.forceActiveFocus() })
        let p = {}
        try { p = typeof payloadJson === "string" ? JSON.parse(payloadJson || "{}") : (payloadJson || {}) } catch (e) {}
        if (p.glitch) { glitchSoon.kind = String(p.glitch); glitchSoon.restart() }
        // ...or a level of network traffic (0..1) to draw, whatever the real one
        view.netTest = Number(p.net) || 0
    }
    Timer { id: glitchSoon; property string kind: ""; interval: 700; onTriggered: view.fireGlitch(kind) }

    Timer {
        id: captureWait
        property int tries: 0
        interval: 40; repeat: true
        onTriggered: {
            tries++
            // a frame in (or give up after ~0.3 s and glitch in from black)
            if ((deskShot.hasContent && tries >= 2) || tries > 7) {
                stop()
                root.capturing = false
                view.playOpening()
            }
        }
    }

    // closing - from the shell (its toggle / hide, e.g. the key again) or
    // ourselves (Esc, a launch): glitch out first, then go
    function close() {
        if (root.opened && view.openingWanted && !view.closingFx && !root.capturing) {
            view.playClosing(function() { root.finish() })
            return
        }
        if (view.closingFx) return                  // already on its way out
        root.finish()
    }
    function finish() {
        captureWait.stop()
        root.capturing = false
        view.closingFx = false
        view.opening = 1
        root.opened = false
    }

    function dismiss() {
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide((root.manifest && root.manifest.id) || "globe-launcher")     // -> close()
        else
            root.close()
    }

    function toggle() {
        if (root.opened) root.dismiss()
        else root.open("{}")
    }

    PanelWindow {
        id: panel
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: root.capturing || view.closingFx ? "transparent" : "black"
        WlrLayershell.namespace: "globe-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        ScreencopyView {
            id: deskShot
            anchors.fill: parent
            captureSource: panel.screen
            live: false
            paintCursor: false
        }

        GlobeView {
            id: view
            anchors.fill: parent
            visible: !root.capturing
            deskItem: deskShot
            active: root.opened
            focus: true
            closeRequest: function() { root.dismiss() }
            onLaunched: root.dismiss()
        }
    }
}
