import Quickshell
import Quickshell.Wayland
import QtQuick

// The overlay: Glitch-Overview over the whole screen, taking the keyboard.
//   omarchy-shell shell toggle glitch-overview '{}'
// It glitches in over the desktop (captured as it opens) and back out to it.
Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false

    // opening: the window maps see-through, the desktop is captured through
    // it, then the selector glitches in over that capture
    property bool capturing: false
    // Alt+Tab summons it with {"alt": true, "step": 1} (Alt+Shift+Tab: -1):
    // the first time it opens on the workspace before this one; while it's
    // up, each further summon steps through them, and letting go of Alt goes
    function open(payloadJson) {
        let p = {}
        try { p = typeof payloadJson === "string" ? JSON.parse(payloadJson || "{}") : (payloadJson || {}) } catch (e) {}
        const step = Number(p.step) || 0
        if (root.opened && !view.closingFx) {
            // toggle mode: the key again goes to the one selected
            if (view.toggleMode) { if (!view.landing) view.go(); return }
            if (step) { if (view.landing) view.pendingSteps += step; else view.step(step) }
            if (p.alt) view.altHeld = true
            return
        }
        view.altHeld = !!p.alt
        view.pendingSteps = step < 0 ? step : 0         // Alt+Shift+Tab opens one further back
        if (view.closingFx) view.playOpening()        // reopened mid-close: straight back in
        else if (!root.opened && view.openingWanted) {
            root.capturing = true
            view.opening = 0
            deskShot.captureFrame()
            captureWait.tries = 0
            captureWait.restart()
        }
        root.opened = true
        Qt.callLater(function() { view.forceActiveFocus() })
    }
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
    // ourselves (Esc): glitch out first, then go
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
            root.shell.hide((root.manifest && root.manifest.id) || "glitch-overview")     // -> close()
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
        WlrLayershell.namespace: "glitch-overview"
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

        OverviewView {
            id: view
            anchors.fill: parent
            visible: !root.capturing
            deskItem: deskShot
            active: root.opened
            focus: true
            closeRequest: function() { root.dismiss() }
        }
    }
}
