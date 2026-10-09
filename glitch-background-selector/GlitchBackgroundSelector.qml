import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// The overlay: Glitch-Background-Selector over the whole screen, taking the keyboard.
//   omarchy-shell shell toggle glitch-background-selector '{}'
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
            root.shell.hide((root.manifest && root.manifest.id) || "glitch-background-selector")     // -> close()
        else
            root.close()
    }
    function toggle() {
        if (root.opened) root.dismiss()
        else root.open("{}")
    }

    // ---------------------------------------------------- the live desktop look
    // options > desktop look: live - on every screen, a click-through layer
    // just above the wallpaper, drawing the wallpaper (the file actually set,
    // in its fit) through the preview shader in the monitor's look, in the
    // colours it was set with. Animated - about 30 fps for rain, slower for
    // the rest - and paused while a window on that monitor is fullscreen.
    readonly property bool liveOn: view.desktopLook === "live" && view.monitorLook !== "clean"
    property string liveSource: ""
    Process {
        id: liveLink
        command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
        stdout: StdioCollector { onStreamFinished: root.liveSource = text.trim() }
    }
    Timer {                                      // follow the wallpaper as it changes
        interval: 1500; repeat: true; triggeredOnStart: true
        running: root.liveOn
        onTriggered: if (!liveLink.running) liveLink.running = true
    }

    Variants {
        model: root.liveOn ? Quickshell.screens : []
        PanelWindow {
            id: live
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            WlrLayershell.namespace: "glitch-background-live"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}                      // clicks go through to the desktop
            readonly property var mon: Hyprland.monitorFor(modelData)
            readonly property bool paused: !!mon && !!mon.activeWorkspace && mon.activeWorkspace.hasFullscreen
            readonly property var cols: view.settings.desktopColors || ["#3dff8a", "#11c46a", "#010603"]
            property real time: 0
            Timer {
                interval: view.monitorLook === "rain" ? 33 : 90
                repeat: true
                running: !live.paused
                onTriggered: live.time += interval / 1000
            }

            Image {
                id: liveShot
                anchors.fill: parent
                source: root.liveSource ? "file://" + encodeURI(root.liveSource).replace(/#/g, "%23").replace(/\?/g, "%3F") : ""
                fillMode: Image.PreserveAspectCrop        // as the shell's own background does
                asynchronous: true
                visible: false
            }
            ShaderEffect {
                anchors.fill: parent
                visible: liveShot.status === Image.Ready
                property var source: liveShot
                property var glyphs: liveGlyphTex
                property real time: live.time
                property vector2d resolution: Qt.vector2d(width, height)
                property real look: Math.max(0, ["clean", "grid", "glyph", "rain"].indexOf(view.monitorLook))
                property real reveal: 1
                property real glyphCount: liveGlyphs.count
                property color primary: live.cols[0]
                property color glow: live.cols[1]
                property color bg: live.cols[2]
                fragmentShader: Qt.resolvedUrl("shaders/preview.frag.qsb")
            }
            Item {
                id: liveAtlas
                width: liveGlyphs.count * 16
                height: 26
                Rectangle { anchors.fill: parent; color: "black" }
                Row {
                    Repeater {
                        id: liveGlyphs
                        model: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎ0123456789:=+*<>Z".split("")
                        delegate: Text {
                            required property string modelData
                            width: 16; height: 26
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: "white"
                            font.family: "Noto Sans CJK JP"
                            font.pixelSize: 19
                        }
                    }
                }
            }
            ShaderEffectSource { id: liveGlyphTex; sourceItem: liveAtlas; hideSource: true; visible: false }
        }
    }

    PanelWindow {
        id: panel
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: root.capturing || view.closingFx ? "transparent" : "black"
        WlrLayershell.namespace: "glitch-background-selector"
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

        BackgroundView {
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
