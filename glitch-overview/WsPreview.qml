import QtQuick
import Quickshell
import Quickshell.Wayland

// One workspace, drawn small: its monitor as a dark screen, each window at
// its place and size as a live picture of itself (Screencopy), titled; the
// picked window outlined. live: false takes a single picture (the cards).
Item {
    id: ws

    property var workspace: null                // {id, monitor, windows: [hyprctl client...]}
    property var monitors: ({})
    property var toplevels: ({})                // "0xADDRESS" -> Toplevel
    property bool live: true
    property bool titles: true
    property string picked: ""                  // a window's address
    property color accent: "white"
    property color back: "black"
    property color text: "white"
    property string mono: "monospace"

    readonly property var mon: workspace && monitors[workspace.monitor] ? monitors[workspace.monitor] : { x: 0, y: 0, width: 2560, height: 1440 }
    readonly property real k: Math.min(width / mon.width, height / mon.height)
    readonly property real ox: (width - mon.width * k) / 2
    readonly property real oy: (height - mon.height * k) / 2

    Rectangle {
        x: ws.ox; y: ws.oy
        width: ws.mon.width * ws.k; height: ws.mon.height * ws.k
        color: Qt.darker(ws.back, 1.4)
        border.width: 1
        border.color: Qt.rgba(ws.accent.r, ws.accent.g, ws.accent.b, 0.25)
    }
    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: !!ws.workspace && ws.workspace.windows.length === 0
        text: "[ empty ]"
        color: ws.text; opacity: 0.35
        font.family: ws.mono; font.pixelSize: Math.max(9, ws.height * 0.06)
    }

    Repeater {
        model: ws.workspace ? ws.workspace.windows.slice().reverse() : []     // oldest at the back
        delegate: Item {
            id: win
            required property var modelData
            readonly property bool isPicked: modelData.address === ws.picked
            x: ws.ox + (modelData.at[0] - ws.mon.x) * ws.k
            y: ws.oy + (modelData.at[1] - ws.mon.y) * ws.k
            width: Math.max(4, modelData.size[0] * ws.k)
            height: Math.max(4, modelData.size[1] * ws.k)
            z: isPicked ? 100 : (modelData.floating ? 50 : 0)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(ws.back.r, ws.back.g, ws.back.b, 0.9)
                border.width: win.isPicked ? 2 : 1
                border.color: win.isPicked ? ws.accent : Qt.rgba(ws.accent.r, ws.accent.g, ws.accent.b, 0.45)
                clip: true
                ScreencopyView {
                    anchors.fill: parent
                    anchors.margins: 1
                    captureSource: ws.toplevels[win.modelData.address] || null
                    live: ws.live
                    paintCursor: false
                }
                // its name along the top
                Rectangle {
                    visible: ws.titles && win.height > 26
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    height: Math.min(22, win.height * 0.2)
                    color: Qt.rgba(0, 0, 0, 0.7)
                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        x: 6; width: parent.width - 12
                        elide: Text.ElideRight
                        text: (win.modelData.class || "") + (win.modelData.title ? "  ·  " + win.modelData.title : "")
                        color: win.isPicked ? ws.accent : ws.text
                        font.family: ws.mono; font.pixelSize: Math.max(8, parent.height * 0.55)
                    }
                }
            }
        }
    }
}
