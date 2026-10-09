import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons

// Globe-Launcher's scene: a starfield (with traffic), the globe, your apps -
// or Omarchy's commands after ">", or files after "/" - projected out from it,
// and the terminal HUD, all through a glitch pass. Spin the globe (drag,
// arrow keys, or let it turn); whatever faces you is the selected app, which
// bulges out with its name. Enter / a click on it launches it. Type to filter.
FocusScope {
    id: view

    property bool active: false
    property var closeRequest: null
    signal launched()

    // ---------------------------------------------------------------- settings
    // ~/.config/globe-launcher/settings.json
    readonly property string settingsPath: Quickshell.env("HOME") + "/.config/globe-launcher/settings.json"
    property var settings: ({ theme: "matrix", style: "dots", glitch: "normal", autoSpin: true, traffic: true,
                              custom: { primary: "#3dff8a", glow: "#11c46a", background: "#010603", text: "#c9ffdc" } })
    function setSetting(key, value) {
        const s = Object.assign({}, settings)
        s[key] = value
        settings = s
        settingsFile.setText(JSON.stringify(settings, null, 2) + "\n")
    }
    FileView {
        id: settingsFile
        path: view.settingsPath
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const s = JSON.parse(text())
                view.settings = Object.assign({}, view.settings, s, { custom: Object.assign({}, view.settings.custom, s.custom || {}) })
            } catch (e) {}
        }
    }
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/globe-launcher"] }

    // ------------------------------------------------------------------ themes
    readonly property var themes: ({
        matrix: { name: "Matrix", primary: "#3dff8a", glow: "#11c46a", background: "#010603", text: "#c9ffdc" },
        cyber:  { name: "Cyber",  primary: "#ff3cac", glow: "#7c3cff", background: "#07020c", text: "#ffd6f0" },
        ice:    { name: "Ice",    primary: "#8fe9ff", glow: "#3a8cff", background: "#01050b", text: "#e2f6ff" },
        amber:  { name: "Amber",  primary: "#ffb000", glow: "#ff6a00", background: "#080400", text: "#ffe2a8" },
        mono:   { name: "Mono",   primary: "#e8e8e8", glow: "#8a8a8a", background: "#040404", text: "#f2f2f2" }
    })
    readonly property var pal: settings.theme === "omarchy"
        ? { primary: String(Color.accent), glow: String(Color.accent), background: String(Color.background), text: String(Color.foreground) }
        : settings.theme === "custom" ? settings.custom : (themes[settings.theme] || themes.matrix)
    readonly property color cPrimary: pal.primary
    readonly property color cGlow: pal.glow
    readonly property color cBg: pal.background
    readonly property color cText: pal.text
    readonly property string mono: Style.font.family || "monospace"

    // ------------------------------------------------------------------ nodes
    // What sits on the globe, by what's typed: your apps; after ">", Omarchy's
    // commands; after "/", files (fuzzy). Every node is {kind, name, sub,
    // detail, icon} plus what activating it needs.
    property string query: ""
    readonly property string mode: query.startsWith(">") ? "cmd" : query.startsWith("/") ? "file" : "app"
    readonly property string term: (mode === "app" ? query : query.slice(1)).trim().toLowerCase()

    readonly property var allApps: (DesktopEntries.applications ? DesktopEntries.applications.values : [])
        .filter(a => a && !a.noDisplay)
        .sort((a, b) => (a.name || "").localeCompare(b.name || ""))
        .map(a => ({ kind: "app", name: a.name || "", sub: a.genericName || "", detail: a.comment || a.genericName || "",
                     icon: a.icon || "", entry: a,
                     words: [a.name, a.genericName, (a.keywords || []).join(" "), (a.categories || []).join(" ")].join(" ").toLowerCase() }))

    // Omarchy's commands, read once from `omarchy commands`
    property var commands: []
    Process {
        id: cmdLister
        command: ["omarchy", "commands"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const m = line.match(/^\s+omarchy\s+(.+?)\s{2,}(\S.*)$/)
                    if (!m) continue
                    const full = m[1].trim(), i = full.search(/\s[<\[]/)
                    const base = i < 0 ? full : full.slice(0, i), args = i < 0 ? "" : full.slice(i + 1)
                    out.push({ kind: "cmd", name: base, sub: args, detail: m[2].trim(), icon: "utilities-terminal",
                               // only a <required> argument outside [optional ones] asks for typing
                               base: base, needsArg: /<[^>]+>/.test(args.replace(/\[[^\]]*\]/g, "")),
                               words: (base + " " + m[2]).toLowerCase(), baseLower: base.toLowerCase() })
                }
                view.commands = out
            }
        }
    }
    // after ">": the matching commands; once a whole command is typed and a
    // space after it, just that one, with what follows as its arguments
    readonly property var commandNodes: {
        const t = term
        let exact = null
        for (const c of commands) if (t.startsWith(c.base.toLowerCase() + " ") && (!exact || c.base.length > exact.base.length)) exact = c
        if (exact) return [Object.assign({}, exact, { typedArgs: query.slice(1).trim().slice(exact.base.length).trim() })]
        const words = t.split(/\s+/).filter(w => w)
        // best first: the name starts with what's typed, then has every word
        // in it, then the rest (words only in the description)
        const rank = c => c.baseLower.startsWith(t) ? 0 : words.every(w => c.baseLower.includes(w)) ? 1 : 2
        return commands.filter(c => words.every(w => c.words.includes(w)))
            .map(c => ({ c: c, r: rank(c) })).sort((a, b) => a.r - b.r || a.c.base.length - b.c.base.length)
            .map(x => x.c).slice(0, 160)
    }

    // files: an index of your home (fd) when "/" is typed, then fzf picks
    readonly property string fileIndex: Quickshell.env("HOME") + "/.cache/globe-launcher/files.txt"
    property var files: []
    Process {
        id: fileIndexer
        // your own files (not hidden ones: those are mostly toolchains and app
        // data), your configs (minus caches), and your scripts
        command: ["bash", "-c",
            "mkdir -p \"${1%/*}\"; { " +
            "fd --type f --exclude Games --exclude node_modules --exclude '*.pyc' . \"$HOME\"; " +
            "fd --type f --hidden --exclude '*[Cc]ache*' --exclude IndexedDB --exclude 'Local Storage' --exclude 'Service Worker' " +
            "--exclude blob_storage --exclude Crashpad --exclude .git . \"$HOME/.config\" \"$HOME/.local/bin\"; " +
            "} > \"$1.tmp\" 2>/dev/null; mv \"$1.tmp\" \"$1\"", "_", view.fileIndex]
        onExited: view.fileSearch()
    }
    Process {
        id: fileFinder
        stdout: StdioCollector {
            onStreamFinished: view.files = text.split("\n").filter(l => l).map(p => view.fileNode(p))
        }
    }
    Timer { id: fileDebounce; interval: 120; onTriggered: view.fileSearch() }
    function fileSearch() {
        if (fileIndexer.running) return
        if (!term) { files = []; return }
        fileFinder.running = false
        fileFinder.command = ["bash", "-c", "fzf --filter \"$1\" < \"$2\" | head -n 90", "_", term, fileIndex]
        fileFinder.running = true
    }
    function fileIcon(name) {
        const e = name.split(".").pop().toLowerCase()
        if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif"].includes(e)) return "image-x-generic"
        if (["mp4", "mkv", "webm", "mov", "avi", "m4v"].includes(e)) return "video-x-generic"
        if (["mp3", "flac", "ogg", "wav", "m4a", "opus"].includes(e)) return "audio-x-generic"
        if (e === "pdf") return "application-pdf"
        if (["zip", "tar", "gz", "xz", "7z", "rar", "zst", "bz2"].includes(e)) return "package-x-generic"
        if (["sh", "py", "js", "ts", "qml", "lua", "c", "cpp", "h", "rs", "go", "rb"].includes(e)) return "text-x-script"
        return "text-x-generic"
    }
    function fileNode(p) {
        const home = Quickshell.env("HOME"), cut = p.lastIndexOf("/")
        const dir = p.slice(0, cut), shown = dir.startsWith(home) ? "~" + dir.slice(home.length) : dir
        return { kind: "file", name: p.slice(cut + 1), sub: shown, detail: (shown + "/" + p.slice(cut + 1)), icon: fileIcon(p), path: p }
    }
    onModeChanged: {
        if (mode === "cmd" && commands.length === 0 && !cmdLister.running) cmdLister.running = true
        if (mode === "file" && !fileIndexer.running) fileIndexer.running = true      // fresh each time
    }
    onTermChanged: if (mode === "file") fileDebounce.restart()

    readonly property var nodes: mode === "cmd" ? commandNodes
        : mode === "file" ? files
        : (term ? allApps.filter(a => a.words.includes(term)) : allApps)
    // where each node sits on the globe: evenly spread (a Fibonacci sphere)
    readonly property var points: {
        const n = nodes.length, out = [], golden = Math.PI * (3 - Math.sqrt(5))
        for (let i = 0; i < n; i++) {
            const y = n === 1 ? 0 : 1 - 2 * (i + 0.5) / n, r = Math.sqrt(Math.max(0, 1 - y * y)), phi = i * golden
            out.push([Math.cos(phi) * r, y, Math.sin(phi) * r])
        }
        return out
    }
    onNodesChanged: aimAt(0)

    // --------------------------------------------------------- the globe's turn
    // rot: 3x3 rotation, row-major (model -> view). x right, y up, z toward you.
    property var rot: [1, 0, 0, 0, 1, 0, 0, 0, 1]
    function mul(A, B) {
        const C = []
        for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++)
            C.push(A[i * 3] * B[j] + A[i * 3 + 1] * B[3 + j] + A[i * 3 + 2] * B[6 + j])
        return C
    }
    function axisAngle(x, y, z, a) {
        const l = Math.hypot(x, y, z) || 1; x /= l; y /= l; z /= l
        const c = Math.cos(a), s = Math.sin(a), t = 1 - c
        return [t * x * x + c, t * x * y - s * z, t * x * z + s * y,
                t * x * y + s * z, t * y * y + c, t * y * z - s * x,
                t * x * z - s * y, t * y * z + s * x, t * z * z + c]
    }
    function turn(x, y, z, a) { rot = mul(axisAngle(x, y, z, a), rot) }
    function apply(p) {
        return [rot[0] * p[0] + rot[1] * p[1] + rot[2] * p[2], rot[3] * p[0] + rot[4] * p[1] + rot[5] * p[2], rot[6] * p[0] + rot[7] * p[1] + rot[8] * p[2]]
    }
    function orthonormalize() {
        let a = [rot[0], rot[1], rot[2]], b = [rot[3], rot[4], rot[5]]
        const la = Math.hypot(...a); a = a.map(v => v / la)
        const d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        b = [b[0] - d * a[0], b[1] - d * a[1], b[2] - d * a[2]]
        const lb = Math.hypot(...b); b = b.map(v => v / lb)
        const c = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        rot = a.concat(b, c)
    }
    readonly property var rotation4: Qt.matrix4x4(rot[0], rot[1], rot[2], 0, rot[3], rot[4], rot[5], 0, rot[6], rot[7], rot[8], 0, 0, 0, 0, 1)

    // spin: from a drag (velocity, decaying), turning to an app, or idling
    property real vx: 0          // rad/s about the screen's x axis
    property real vy: 0          // rad/s about the screen's y axis
    property bool dragging: false
    property int aim: -1         // the app being turned to the front
    property real idle: 0        // seconds since the last touch
    function aimAt(i) { aim = (i >= 0 && i < nodes.length) ? i : -1; idle = 0 }

    // ------------------------------------------------------------- projection
    property real zoom: 1.0
    readonly property real radius: Math.min(width, height) * 0.30 * zoom
    property real driftT: 0
    readonly property real cx: width / 2 + Math.sin(driftT * 0.21) * 6 + shakeX
    readonly property real cy: height * 0.47 + Math.cos(driftT * 0.17) * 5 + shakeY
    readonly property real lift: 1.24            // icons float this far out
    property var proj: []                        // per app: {x, y, sx, sy, z}
    property int selected: -1
    function project() {
        const out = [], n = nodes.length
        let best = -1, bestZ = -2
        for (let i = 0; i < n; i++) {
            const q = apply(points[i])
            out.push({ x: cx + q[0] * radius * lift, y: cy - q[1] * radius * lift,
                       sx: cx + q[0] * radius, sy: cy - q[1] * radius, z: q[2] })
            if (q[2] > bestZ) { bestZ = q[2]; best = i }
        }
        proj = out
        const sel = aim >= 0 ? aim : best
        if (sel !== selected) { selected = sel; selectPulse.restart() }
    }

    FrameAnimation {
        running: view.active && view.visible
        onTriggered: {
            const dt = Math.min(frameTime, 0.05)
            view.driftT += dt
            view.idle += dt
            if (view.aim >= 0 && !view.dragging) {
                // turn the aimed app to face you
                const q = view.apply(view.points[view.aim])
                const ang = Math.acos(Math.max(-1, Math.min(1, q[2])))
                if (ang < 0.003) view.aim = -1
                else view.turn(q[1], -q[0], 0, Math.min(ang, ang * dt * 7 + 0.002))
            } else if (!view.dragging) {
                if (Math.abs(view.vx) + Math.abs(view.vy) > 0.001) {
                    view.turn(1, 0, 0, view.vx * dt)
                    view.turn(0, 1, 0, view.vy * dt)
                    const decay = Math.pow(0.12, dt)
                    view.vx *= decay; view.vy *= decay
                } else if (view.settings.autoSpin && view.idle > 4) {
                    view.turn(0, 1, 0, 0.07 * dt * Math.min(1, (view.idle - 4) / 2))
                }
            }
            if (Math.floor(view.driftT * 2) % 20 === 0) view.orthonormalize()
            view.project()
        }
    }

    // ------------------------------------------------------- keyboard and mouse
    // Enter / a click on the selected node. alt (Shift+Enter): a file's
    // folder; a command in a terminal, to see its output.
    function activate(i, alt) {
        const n = nodes[i]
        if (!n) return
        if (n.kind === "app") { n.entry.execute(); launched(); return }
        if (n.kind === "file") {
            Quickshell.execDetached(["xdg-open", alt ? n.path.slice(0, n.path.lastIndexOf("/")) : n.path])
            launched()
            return
        }
        // a command that needs arguments: type them first
        const args = n.typedArgs || ""
        if (n.needsArg && !args) { query = "> " + n.base + " "; return }
        const line = "omarchy " + n.base + (args ? " " + args : "")
        Quickshell.execDetached(alt ? ["omarchy-launch-floating-terminal-with-presentation", line] : ["bash", "-lc", line])
        launched()
    }
    // arrow keys: the nearest app that way, on screen; none -> just turn
    function hop(dx, dy) {
        idle = 0
        const s = proj[selected]
        if (!s) return
        let best = -1, bestScore = 1e9
        for (let j = 0; j < proj.length; j++) {
            const p = proj[j]
            if (j === selected || p.z < 0.15) continue
            const vx = p.x - s.x, vy = p.y - s.y, len = Math.hypot(vx, vy)
            if (len < 1) continue
            const along = (vx * dx + vy * dy) / len
            if (along < 0.5) continue
            const score = len * (1 + 2.5 * (1 - along))
            if (score < bestScore) { bestScore = score; best = j }
        }
        if (best >= 0) aimAt(best)
        else turn(-dy, -dx, 0, 0.35)
    }
    Keys.onPressed: event => {
        const k = event.key
        if (settingsOpen) {
            if (k === Qt.Key_Escape) { settingsOpen = false; event.accepted = true }
            return
        }
        if (k === Qt.Key_Escape) { if (query) query = ""; else if (closeRequest) closeRequest() }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) activate(selected, !!(event.modifiers & Qt.ShiftModifier))
        else if (k === Qt.Key_Left) hop(-1, 0)
        else if (k === Qt.Key_Right) hop(1, 0)
        else if (k === Qt.Key_Up) hop(0, -1)
        else if (k === Qt.Key_Down) hop(0, 1)
        else if (k === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier)) settingsOpen = true
        else if (k === Qt.Key_Backspace) query = query.slice(0, -1)
        else if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) query += event.text
        else return
        event.accepted = true
    }
    // fresh each time it opens
    onActiveChanged: if (active) { query = ""; settingsOpen = false; zoom = 1; idle = 0; aimAt(-1); forceActiveFocus() }

    // ------------------------------------------------------------- the glitches
    property real glitch: 0          // 0..1, the glitch pass's intensity
    property real glitchSeed: 0
    property real shakeX: 0
    property real shakeY: 0
    property real shakeToX: 0        // where this burst jolts to
    property real shakeToY: 0
    readonly property bool glitchesOn: settings.glitch !== "off"
    Timer {
        id: glitchTimer
        running: view.active && view.glitchesOn
        interval: 4000
        onTriggered: {
            view.glitchSeed = Math.random() * 100
            view.shakeToX = (Math.random() - 0.5) * 14
            view.shakeToY = (Math.random() - 0.5) * 8
            burst.restart()
            if (Math.random() < 0.5) terminal.say()
            interval = (view.settings.glitch === "subtle" ? 14000 : 5000) + Math.random() * (view.settings.glitch === "subtle" ? 16000 : 9000)
            restart()
        }
    }
    SequentialAnimation {
        id: burst
        ParallelAnimation {
            NumberAnimation { target: view; property: "glitch"; from: 0; to: view.settings.glitch === "subtle" ? 0.45 : 1; duration: 60 }
            NumberAnimation { target: view; property: "shakeX"; to: view.shakeToX; duration: 60 }
            NumberAnimation { target: view; property: "shakeY"; to: view.shakeToY; duration: 60 }
        }
        PauseAnimation { duration: 180 }
        ScriptAction { script: view.glitchSeed = Math.random() * 100 }
        ParallelAnimation {
            NumberAnimation { target: view; property: "glitch"; to: 0; duration: 160 }
            NumberAnimation { target: view; property: "shakeX"; to: 0; duration: 220; easing.type: Easing.OutBack }
            NumberAnimation { target: view; property: "shakeY"; to: 0; duration: 220; easing.type: Easing.OutBack }
        }
    }
    // a small pulse through the globe when the selection changes
    property real pulse: 0
    SequentialAnimation {
        id: selectPulse
        NumberAnimation { target: view; property: "pulse"; from: 0; to: 1; duration: 80 }
        NumberAnimation { target: view; property: "pulse"; to: 0; duration: 420; easing.type: Easing.OutCubic }
    }

    // ------------------------------------------------------------------ scene
    Item {
        id: scene
        anchors.fill: parent

        Rectangle { anchors.fill: parent; color: view.cBg }

        ShaderEffect {
            anchors.fill: parent
            property real time: view.driftT
            property vector2d resolution: Qt.vector2d(width, height)
            property color tint: view.cGlow
            property color starColor: view.cPrimary
            fragmentShader: Qt.resolvedUrl("shaders/stars.frag.qsb")
        }

        // shooting stars, comets and spacecraft, behind the globe
        SpaceTraffic {
            anchors.fill: parent
            running: view.active && view.settings.traffic !== false
            visible: view.settings.traffic !== false
            primary: view.cPrimary
            dark: view.cBg
        }

        ShaderEffect {
            anchors.fill: parent
            property real time: view.driftT
            property vector2d resolution: Qt.vector2d(width, height)
            property vector2d center: Qt.vector2d(view.cx, view.cy)
            property real radius: view.radius
            property matrix4x4 rotation: view.rotation4
            property color dotColor: view.cPrimary
            property color glowColor: view.cGlow
            property real rings: 34
            property real wire: view.settings.style === "wire" ? 1 : 0
            property real pulse: view.pulse
            fragmentShader: Qt.resolvedUrl("shaders/globe.frag.qsb")
        }

        // the apps, projected out from the globe on beams
        Repeater {
            model: view.nodes
            delegate: Item {
                id: node
                required property var modelData
                required property int index
                readonly property var p: view.proj[index] || ({ x: 0, y: 0, sx: 0, sy: 0, z: -1 })
                readonly property bool sel: index === view.selected
                readonly property real depth: Math.max(0, Math.min(1, (p.z + 0.05) / 0.4))
                visible: p.z > -0.05
                opacity: depth
                z: 10 + p.z * 10 + (sel ? 50 : 0)

                // the beam, from the globe's surface out to the icon
                Rectangle {
                    readonly property real dx: node.p.x - node.p.sx
                    readonly property real dy: node.p.y - node.p.sy
                    x: node.p.sx
                    y: node.p.sy - height / 2
                    width: Math.hypot(dx, dy)
                    height: node.sel ? 2 : 1
                    transformOrigin: Item.Left
                    rotation: Math.atan2(dy, dx) * 180 / Math.PI
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(view.cGlow.r, view.cGlow.g, view.cGlow.b, 0.0) }
                        GradientStop { position: 1; color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, node.sel ? 0.9 : 0.45) }
                    }
                }

                Item {
                    id: tile
                    readonly property real size: 34 * (0.55 + 0.45 * Math.max(0, node.p.z))
                    x: node.p.x - width / 2
                    y: node.p.y - height / 2
                    width: size
                    height: size
                    // the bulge: the selected one swells out
                    scale: node.sel ? 1.9 : 1.0
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 10; height: width; radius: width / 2
                        color: Qt.rgba(view.cBg.r, view.cBg.g, view.cBg.b, 0.7)
                        border.width: node.sel ? 1.5 : 1
                        border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, node.sel ? 1 : 0.5)
                    }
                    IconImage {
                        anchors.fill: parent
                        source: Quickshell.iconPath(node.modelData.icon || "", "application-x-executable")
                        asynchronous: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: node.sel ? view.activate(node.index, false) : view.aimAt(node.index)
                    }
                }

                // its name, unfolding beside it once it's selected
                Rectangle {
                    id: plate
                    readonly property real full: plateRow.implicitWidth + 24
                    x: node.p.x + tile.width * 1.05 + 14
                    y: node.p.y - height / 2
                    height: 40
                    width: node.sel ? full : 0
                    clip: true
                    radius: 4
                    color: Qt.rgba(view.cBg.r, view.cBg.g, view.cBg.b, 0.85)
                    border.width: 1
                    border.color: view.cPrimary
                    visible: width > 1
                    Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Row {
                        id: plateRow
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Text { text: ">"; color: view.cPrimary; font.family: view.mono; font.pixelSize: 16; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: node.modelData.name || ""; color: view.cText; font.family: view.mono; font.pixelSize: 15; font.bold: true }
                            Text { visible: text !== ""; text: node.modelData.sub || ""; color: view.cPrimary; opacity: 0.75; font.family: view.mono; font.pixelSize: 11 }
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------- the HUD
        // top: what you're searching for
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 46
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "// GLOBE-LAUNCHER  ·  " + view.nodes.length + (view.mode === "cmd" ? " OMARCHY COMMANDS" : view.mode === "file" ? " FILES" : " APPS")
                      + (view.term ? "  ·  FILTER ACTIVE" : "")
                color: view.cPrimary; opacity: 0.7
                font.family: view.mono; font.pixelSize: 13; font.letterSpacing: 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (!view.query ? "> type to search   ·   > commands   ·   / files"
                       : view.mode === "app" ? "> " + view.query : view.query) + (cursorBlink.on ? "_" : " ")
                color: view.query ? view.cText : Qt.rgba(view.cText.r, view.cText.g, view.cText.b, 0.45)
                font.family: view.mono; font.pixelSize: 22
                Timer { id: cursorBlink; property bool on: true; interval: 530; repeat: true; running: view.active; onTriggered: on = !on }
            }
        }

        // bottom: the selected app, big
        Rectangle {
            id: card
            readonly property var app: view.nodes[view.selected] || null
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 54
            width: Math.min(720, parent.width - 80)
            height: 96
            radius: 6
            visible: !!app
            color: Qt.rgba(view.cBg.r, view.cBg.g, view.cBg.b, 0.75)
            border.width: 1
            border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.6)
            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 16
                IconImage {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    source: card.app ? Quickshell.iconPath(card.app.icon || "", "application-x-executable") : ""
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: !card.app ? "" : card.app.kind === "cmd" ? "omarchy " + card.app.base + " " + (card.app.typedArgs || card.app.sub) : (card.app.name || "").toUpperCase()
                        color: view.cText; font.family: view.mono; font.pixelSize: 20; font.bold: true; font.letterSpacing: 1.5
                    }
                    Text { Layout.fillWidth: true; elide: Text.ElideMiddle; visible: text !== ""; text: card.app ? (card.app.detail || "") : ""; color: view.cPrimary; opacity: 0.85; font.family: view.mono; font.pixelSize: 13 }
                    Text {
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: !card.app ? ""
                            : card.app.kind === "file" ? "[ENTER] open   [SHIFT+ENTER] open its folder   [← → ↑ ↓] hop   [ESC] back"
                            : card.app.kind === "cmd" ? (card.app.needsArg && !card.app.typedArgs ? "[ENTER] type its arguments: " + card.app.sub + "   [ESC] back"
                                                         : "[ENTER] run   [SHIFT+ENTER] run in a terminal   [← → ↑ ↓] hop   [ESC] back")
                            : "[ENTER] launch   [← → ↑ ↓] hop   [drag] spin   [type] search   [>] commands   [/] files   [CTRL+,] options   [ESC] exit"
                        color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 11
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: view.nodes.length === 0
            text: view.mode === "cmd" ? (view.commands.length === 0 ? "> reading omarchy commands..." : "> no command matches \"" + view.term + "\"")
                : view.mode === "file" ? (fileIndexer.running ? "> indexing your files..." : !view.term ? "> type a file name" : "> no file matches \"" + view.term + "\"")
                : view.allApps.length === 0 ? "> scanning apps..." : "> no app matches \"" + view.term + "\""
            color: view.cText; font.family: view.mono; font.pixelSize: 18
        }

        // a terminal in the corner that talks now and then
        Column {
            id: terminal
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 40
            spacing: 2
            property var lines: []
            readonly property var phrases: [
                "> handshake ok :: node %h", "> tracing route //apps/%n", "> sync shard 0x%h ... ok",
                "> signal drift detected, recalibrating", "> uplink %n%% :: carrier stable", "> decrypting index 0x%h",
                "> wake up, operator", "> follow the white rabbit", "> mapping %n nodes to the sphere", "> packet loss 0.%n%"]
            function say() {
                let s = phrases[Math.floor(Math.random() * phrases.length)]
                s = s.replace("%h", Math.floor(Math.random() * 0xffff).toString(16).padStart(4, "0")).replace("%n", Math.floor(Math.random() * 99))
                lines = lines.concat([s]).slice(-5)
            }
            Repeater {
                model: terminal.lines
                delegate: Text {
                    required property string modelData
                    required property int index
                    property int shown: 0
                    text: modelData.slice(0, shown) + (shown < modelData.length ? "▌" : "")
                    color: view.cPrimary
                    opacity: 0.25 + 0.5 * (index + 1) / terminal.lines.length
                    font.family: view.mono; font.pixelSize: 12
                    Timer { interval: 24; repeat: true; running: parent.shown < parent.modelData.length; onTriggered: parent.shown++ }
                }
            }
        }

        // options button
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 30
            width: gearText.implicitWidth + 24; height: 32; radius: 4
            color: gearHover.hovered ? Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.15) : "transparent"
            border.width: 1
            border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.5)
            Text { id: gearText; anchors.centerIn: parent; text: "[ options ]"; color: view.cPrimary; font.family: view.mono; font.pixelSize: 13 }
            HoverHandler { id: gearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: view.settingsOpen = !view.settingsOpen }
        }
    }

    // drag to spin, scroll to zoom (behind the icons, which take their own clicks)
    MouseArea {
        anchors.fill: parent
        z: -1
        property real lx: 0
        property real ly: 0
        property real lt: 0
        onPressed: mouse => { lx = mouse.x; ly = mouse.y; lt = Date.now(); view.dragging = true; view.aim = -1; view.vx = 0; view.vy = 0; view.idle = 0 }
        onPositionChanged: mouse => {
            if (!pressed) return
            const dx = mouse.x - lx, dy = mouse.y - ly, now = Date.now(), dt = Math.max(1, now - lt) / 1000
            view.turn(0, 1, 0, dx / view.radius)
            view.turn(1, 0, 0, dy / view.radius)
            view.vy = view.vy * 0.5 + 0.5 * (dx / view.radius) / dt
            view.vx = view.vx * 0.5 + 0.5 * (dy / view.radius) / dt
            lx = mouse.x; ly = mouse.y; lt = now
        }
        onReleased: { view.dragging = false; if (Date.now() - lt > 80) { view.vx = 0; view.vy = 0 } }
        onWheel: wheel => { view.zoom = Math.max(0.6, Math.min(1.5, view.zoom * (wheel.angleDelta.y > 0 ? 1.08 : 1 / 1.08))); view.idle = 0 }
    }

    // ------------------------------------------------------- the glitch pass
    ShaderEffectSource {
        id: sceneTex
        anchors.fill: parent
        sourceItem: scene
        hideSource: true
        live: true
        visible: false
    }
    ShaderEffect {
        anchors.fill: parent
        property var source: sceneTex
        property real time: view.driftT
        property vector2d resolution: Qt.vector2d(width, height)
        property real intensity: view.glitch
        property real seed: view.glitchSeed
        property real scanlines: view.glitchesOn ? 1 : 0.3
        property color tint: view.cPrimary
        fragmentShader: Qt.resolvedUrl("shaders/glitch.frag.qsb")
    }

    // --------------------------------------------------------------- options
    property bool settingsOpen: false
    Rectangle {
        id: options
        visible: view.settingsOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 72
        anchors.rightMargin: 30
        width: 360
        height: optCol.implicitHeight + 32
        radius: 6
        color: Qt.rgba(view.cBg.r, view.cBg.g, view.cBg.b, 0.94)
        border.width: 1
        border.color: view.cPrimary
        MouseArea { anchors.fill: parent }        // keep clicks off the globe

        component Chip: Rectangle {
            id: chip
            property string label: ""
            property bool on: false
            signal clicked()
            width: chipText.implicitWidth + 18; height: 26; radius: 3
            color: on ? Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.2) : (chipHover.hovered ? Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.08) : "transparent")
            border.width: 1
            border.color: on ? view.cPrimary : Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.35)
            Text { id: chipText; anchors.centerIn: parent; text: chip.label; color: chip.on ? view.cPrimary : view.cText; font.family: view.mono; font.pixelSize: 12 }
            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: chip.clicked() }
        }
        component Heading: Text { color: view.cPrimary; opacity: 0.8; font.family: view.mono; font.pixelSize: 11; font.letterSpacing: 2 }
        component HexField: RowLayout {
            id: hf
            property string label: ""
            property string key: ""
            spacing: 8
            Text { text: hf.label; color: view.cText; font.family: view.mono; font.pixelSize: 12; Layout.preferredWidth: 90 }
            Rectangle { width: 18; height: 18; radius: 3; color: view.settings.custom[hf.key] || "black"; border.width: 1; border.color: view.cText }
            Rectangle {
                Layout.fillWidth: true; height: 26; radius: 3
                color: "transparent"; border.width: 1
                border.color: hexIn.activeFocus ? view.cPrimary : Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.35)
                TextInput {
                    id: hexIn
                    anchors.fill: parent; anchors.leftMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    text: view.settings.custom[hf.key] || ""
                    color: view.cText; font.family: view.mono; font.pixelSize: 12
                    selectByMouse: true
                    onEditingFinished: {
                        if (/^#[0-9a-fA-F]{6}$/.test(text)) {
                            const c = Object.assign({}, view.settings.custom); c[hf.key] = text
                            view.setSetting("custom", c)
                        }
                    }
                    Keys.onEscapePressed: view.forceActiveFocus()
                }
            }
        }

        ColumnLayout {
            id: optCol
            x: 16; y: 16
            width: parent.width - 32
            spacing: 10
            Text { text: "> OPTIONS"; color: view.cText; font.family: view.mono; font.pixelSize: 16; font.bold: true }

            Heading { text: "COLOURS" }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Chip { label: "Omarchy theme"; on: view.settings.theme === "omarchy"; onClicked: view.setSetting("theme", "omarchy") }
                Repeater {
                    model: ["matrix", "cyber", "ice", "amber", "mono"]
                    delegate: Chip {
                        required property string modelData
                        label: view.themes[modelData].name
                        on: view.settings.theme === modelData
                        onClicked: view.setSetting("theme", modelData)
                    }
                }
                Chip { label: "Custom"; on: view.settings.theme === "custom"; onClicked: view.setSetting("theme", "custom") }
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: view.settings.theme === "custom"
                spacing: 6
                HexField { Layout.fillWidth: true; label: "dots"; key: "primary" }
                HexField { Layout.fillWidth: true; label: "glow"; key: "glow" }
                HexField { Layout.fillWidth: true; label: "space"; key: "background" }
                HexField { Layout.fillWidth: true; label: "text"; key: "text" }
            }

            Heading { text: "GLOBE" }
            Row {
                spacing: 6
                Chip { label: "Dots"; on: view.settings.style !== "wire"; onClicked: view.setSetting("style", "dots") }
                Chip { label: "Wireframe"; on: view.settings.style === "wire"; onClicked: view.setSetting("style", "wire") }
                Chip { label: "Auto-spin"; on: view.settings.autoSpin; onClicked: view.setSetting("autoSpin", !view.settings.autoSpin) }
                Chip { label: "Space traffic"; on: view.settings.traffic !== false; onClicked: view.setSetting("traffic", view.settings.traffic === false) }
            }

            Heading { text: "GLITCHES" }
            Row {
                spacing: 6
                Chip { label: "Normal"; on: view.settings.glitch === "normal"; onClicked: view.setSetting("glitch", "normal") }
                Chip { label: "Subtle"; on: view.settings.glitch === "subtle"; onClicked: view.setSetting("glitch", "subtle") }
                Chip { label: "Off"; on: view.settings.glitch === "off"; onClicked: view.setSetting("glitch", "off") }
            }
            Text { text: "[ESC] close options"; color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 11 }
        }
    }
}
