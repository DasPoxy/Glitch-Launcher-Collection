import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io

// Globe-Launcher's file preview: a terminal pane beside the globe for the
// selected file. Pictures, videos (muted, looping) and PDFs' first pages go
// through the preview shader in the chosen look; text shows its first lines;
// archives what's in them; audio its tags; anything else what file(1) says.
Rectangle {
    id: pv

    property var file: null                 // the selected file node
    property bool active: false
    property string look: "grid"            // clean / grid / glyph / rain
    property real time: 0
    property color primary: "#3dff8a"
    property color glow: "#11c46a"
    property color bg: "#010603"
    property color fg: "#c9ffdc"
    property string mono: "monospace"

    // what preview.sh found
    property string path: ""
    property string kind: ""
    property string mime: ""
    property real size: 0
    property string modified: ""
    property string body: ""
    readonly property bool visual: kind === "image" || kind === "video" || (kind === "pdf" && body.trim() !== "")
                                   || (kind === "model" && frames.length > 0)
    readonly property string visualSource: !visual ? ""
        : fileUrl(kind === "pdf" ? body.trim() : kind === "model" ? frames[frame % frames.length] : path)
    function fileUrl(p) { return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F") }

    // a 3D model: render-model.py turns it on a turntable, frame by frame
    // (cached); it spins through them once they're all in
    readonly property string renderer: Qt.resolvedUrl("render-model.py").toString().replace(/^file:\/\//, "")
    readonly property string modelCache: Quickshell.env("HOME") + "/.cache/globe-launcher/models"
    readonly property int modelFrames: 24
    property var frames: []
    property int frame: 0
    property string modelInfo: ""
    Process {
        id: modelProc
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("tris ")) pv.modelInfo = Number(line.slice(5)).toLocaleString(Qt.locale(), "f", 0) + " triangles"
                else if (line.startsWith("error ")) pv.modelInfo = line.slice(6)
                else if (line) { pv.frames = pv.frames.concat([line]); pv.frame = pv.frames.length - 1 }
            }
        }
    }
    Timer {
        interval: 70; repeat: true
        running: pv.kind === "model" && pv.frames.length === pv.modelFrames && pv.active
        onTriggered: pv.frame = (pv.frame + 1) % pv.frames.length
    }
    readonly property real lookIndex: ["clean", "grid", "glyph", "rain"].indexOf(look)
    property real reveal: 1

    readonly property string helper: Qt.resolvedUrl("preview.sh").toString().replace(/^file:\/\//, "")
    readonly property string thumbs: Quickshell.env("HOME") + "/.cache/globe-launcher/thumbs"

    color: Qt.rgba(bg.r, bg.g, bg.b, 0.86)
    radius: 6
    border.width: 1
    border.color: Qt.rgba(primary.r, primary.g, primary.b, 0.7)
    clip: true

    // pops out when there's something to show
    opacity: file && active ? 1 : 0
    scale: file && active ? 1 : 0.96
    Behavior on opacity { NumberAnimation { duration: 180 } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // the globe turns through files quickly: settle on one before reading it
    onFileChanged: settle.restart()
    onActiveChanged: if (!active) { kind = ""; path = "" }
    Timer { id: settle; interval: 140; onTriggered: pv.load() }
    function load() {
        probe.running = false
        modelProc.running = false
        frames = []; frame = 0; modelInfo = ""
        if (!file || !active) { kind = ""; path = ""; return }
        probe.command = ["bash", helper, file.path, thumbs]
        probe.running = true
    }
    Process {
        id: probe
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n")
                const head = (nl < 0 ? text : text.slice(0, nl)).split("\t")
                // a probe that was cut short for a newer one: not ours any more
                if (!pv.file || head[0] !== pv.file.path) return
                pv.path = head[0]
                pv.kind = head[1] || "other"
                pv.mime = head[2] || ""
                pv.size = Number(head[3] || 0)
                pv.modified = head[4] || ""
                pv.body = nl < 0 ? "" : text.slice(nl + 1)
                if (pv.kind === "model") {
                    modelProc.command = ["python3", pv.renderer, pv.path, pv.modelCache]
                    modelProc.running = true
                }
                pv.reveal = 0
                revealAnim.restart()
            }
        }
    }
    NumberAnimation { id: revealAnim; target: pv; property: "reveal"; to: 1; duration: 650; easing.type: Easing.OutQuad }

    function human(n) {
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
        return (i ? n.toFixed(1) : n) + " " + u[i]
    }
    function seconds(s) {
        s = Math.round(Number(s) || 0)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    // the text shown for non-visual kinds
    readonly property string textBody: {
        if (kind === "text") {
            const lines = body.replace(/\t/g, "    ").split("\n")
            if (lines.length && lines[lines.length - 1] === "") lines.pop()
            const w = String(lines.length).length
            return lines.length ? lines.map((l, i) => String(i + 1).padStart(w, " ") + " │ " + l).join("\n") : "(empty)"
        }
        if (kind === "archive") {
            const n = body.split("\n").filter(l => l).length
            return "> " + n + (n >= 120 ? "+" : "") + " entries\n\n" + body
        }
        if (kind === "audio") {
            const tags = {}
            for (const l of body.split("\n")) { const i = l.indexOf("="); if (i > 0) tags[l.slice(0, i).toLowerCase()] = l.slice(i + 1) }
            return ["title", "artist", "album", "date", "genre"].filter(k => tags[k]).map(k => k.toUpperCase().padEnd(8) + tags[k]).join("\n")
                + (tags.duration ? "\nLENGTH  " + seconds(tags.duration) : "")
        }
        if (kind === "pdf") return "> no preview of this PDF"
        if (kind === "model") return modelInfo && !modelInfo.includes("triangles") ? "> " + modelInfo : "> rendering the model..."
        return body.trim() ? "> " + body.trim() : ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // header: what it is
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: "// PREVIEW :: " + (pv.file ? pv.file.name : "")
                color: pv.fg; font.family: pv.mono; font.pixelSize: 15; font.bold: true; font.letterSpacing: 1
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: !pv.kind ? "> reading..." : [pv.kind.toUpperCase(), pv.mime, pv.human(pv.size), pv.modelInfo, pv.modified].filter(s => s).join("  ·  ")
                color: pv.primary; opacity: 0.75; font.family: pv.mono; font.pixelSize: 11
            }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: 6; height: 1; color: Qt.rgba(pv.primary.r, pv.primary.g, pv.primary.b, 0.35) }
        }

        // the picture / video / page, through the shader
        Item {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: pv.visual

            Item {
                id: content
                anchors.fill: parent
                Image {
                    id: still
                    anchors.fill: parent
                    visible: pv.kind !== "video"
                    source: pv.kind !== "video" ? pv.visualSource : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: pv.kind !== "model"        // frames swap in without a blank between
                    cache: pv.kind === "model"
                    sourceSize: Qt.size(1400, 1400)
                    // materialise on a new picture, not on every turntable frame
                    property string shownFor: ""
                    onStatusChanged: if (status === Image.Ready && shownFor !== pv.path) { shownFor = pv.path; pv.reveal = 0; revealAnim.restart() }
                }
                VideoOutput {
                    id: videoOut
                    anchors.fill: parent
                    visible: pv.kind === "video"
                    fillMode: VideoOutput.PreserveAspectFit
                }
            }
            MediaPlayer {
                id: player
                videoOutput: videoOut
                loops: MediaPlayer.Infinite
                source: pv.kind === "video" && pv.active ? pv.visualSource : ""
                onSourceChanged: source.toString() ? play() : stop()
            }
            ShaderEffectSource {
                id: contentTex
                anchors.fill: parent
                sourceItem: content
                hideSource: true
                live: true
                visible: false
            }
            ShaderEffect {
                anchors.fill: parent
                property var source: contentTex
                property var glyphs: glyphTex
                property real time: pv.time
                property vector2d resolution: Qt.vector2d(width, height)
                property real look: Math.max(0, pv.lookIndex)
                property real reveal: pv.reveal
                property real glyphCount: glyphRow.count
                property color primary: pv.primary
                property color glow: pv.glow
                property color bg: pv.bg
                fragmentShader: Qt.resolvedUrl("shaders/preview.frag.qsb")
            }
            Text {
                anchors.centerIn: parent
                visible: pv.kind !== "video" && still.status === Image.Loading
                text: "> decoding..."
                color: pv.primary; font.family: pv.mono; font.pixelSize: 14
            }
        }

        // text, listings, tags: scrolled in line by line
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !pv.visual
            clip: true
            Text {
                id: bodyText
                width: parent.width
                height: Math.min(implicitHeight, parent.height * pv.reveal + 1)
                clip: true
                text: pv.textBody
                textFormat: Text.PlainText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                color: pv.fg
                font.family: pv.mono
                font.pixelSize: 12
                lineHeight: 1.1
            }
            // the cursor riding down as it scrolls in
            Rectangle {
                visible: pv.reveal < 1 && pv.textBody !== ""
                y: bodyText.height - 2
                width: parent.width; height: 2
                color: pv.primary
                opacity: 0.8
            }
        }

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: (pv.visual ? "[TAB] look: " + pv.look + "   " : "") + "[ENTER] open   [SHIFT+ENTER] its folder"
            color: pv.fg; opacity: 0.45; font.family: pv.mono; font.pixelSize: 11
        }
    }

    // a sweep of light down the pane each time something new appears
    Rectangle {
        width: parent.width
        height: 60
        y: -height + (parent.height + height) * pv.reveal
        visible: pv.reveal < 1
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(pv.primary.r, pv.primary.g, pv.primary.b, 0.25) }
        }
    }

    // the glyph atlas for the glyph / rain looks: white on black, in a row
    Item {
        id: glyphAtlas
        width: glyphRow.count * 16
        height: 26
        Rectangle { anchors.fill: parent; color: "black" }
        Row {
            Repeater {
                id: glyphRow
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
    ShaderEffectSource {
        id: glyphTex
        sourceItem: glyphAtlas
        hideSource: true
        visible: false
    }
}
