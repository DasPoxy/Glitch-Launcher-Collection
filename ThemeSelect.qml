import Quickshell
import Quickshell.Wayland
import QtQuick

// The overlay: Matrix-Theme-Select over the whole screen, taking the keyboard.
//   omarchy-shell shell toggle matrix-theme-select '{}'
// It glitches in over the desktop (captured as it opens) and back out to it.
Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false

    // opening: the window maps see-through, the desktop is captured through
    // it, then the selector glitches in over that capture
    property bool capturing: false
    function open(payloadJson) {
        if (view.closingFx) view.playOpening()        // reopened mid-close: straight back in
        else if (!root.opened) {
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
        if (root.opened && !view.closingFx && !root.capturing) {
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
            root.shell.hide((root.manifest && root.manifest.id) || "matrix-theme-select")     // -> close()
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
        WlrLayershell.namespace: "matrix-theme-select"
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

        SelectorView {
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
