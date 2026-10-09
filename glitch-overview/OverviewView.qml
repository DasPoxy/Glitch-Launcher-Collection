import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "eggs.js" as Eggs

// Glitch-Overview's scene: your workspaces on a carousel under an old CRT
// monitor showing the selected one live - every window at its place, titled
// - and a readout scrawling what each window is costing (CPU, memory, with
// the processes it started). Alt+Tab-style: it opens on the workspace you
// were on before; Tab / arrows move, Up / Down pick a window in it, Enter
// (or letting go of Alt, if Alt+Tab opened it) goes there, 1-9 jump, Esc
// cancels. Glitches in and out, and now and then while it's up.
FocusScope {
    id: view

    property bool active: false
    property var closeRequest: null
    property var deskItem: null                // the desktop, captured as it opened
    property bool altHeld: false               // opened by Alt+Tab: letting go of Alt goes

    // ---------------------------------------------------------------- settings
    // ~/.config/glitch-overview/settings.json
    readonly property string settingsPath: Quickshell.env("HOME") + "/.config/glitch-overview/settings.json"
    property var settings: ({ crt: true, carousel: "line", glitch: "normal", openGlitch: true, mode: "hold" })
    // "hold": letting go of Alt goes; "toggle": it stays up - Alt+Tab again,
    // Enter or a click goes, Esc stays where you are
    readonly property bool toggleMode: settings.mode === "toggle"
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
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { view.settings = Object.assign({}, view.settings, JSON.parse(text())) } catch (e) {} }
    }
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/glitch-overview"] }

    // the colours: the running Omarchy theme's
    readonly property color cPrimary: Color.accent
    readonly property color cGlow: Qt.darker(Color.accent, 1.5)
    readonly property color cBg: Color.background
    readonly property color cText: Color.foreground
    readonly property color skyA: cPrimary
    readonly property color skyB: cGlow
    readonly property string mono: Style.font.family || "monospace"
    readonly property real glitchLevel: settings.glitch === "off" ? 0 : settings.glitch === "subtle" ? 0.5 : 1

    // -------------------------------------------------------------- workspaces
    // hyprctl's view of things, read on opening and every second while up:
    // the workspaces (normal ones, by number), their windows, the monitors
    property var workspaces: []                 // [{id, name, monitor, windows: [client...]}]
    property var monitors: ({})                 // name -> {x, y, width, height, scale}
    property int focusedWs: 1
    Process {
        id: reader
        command: ["bash", "-c", "printf '%s\\n%s\\n%s\\n' \"$(hyprctl workspaces -j)\" \"$(hyprctl clients -j)\" \"$(hyprctl monitors -j)\" | tr -d '\\n' | sed 's/\\]\\[/]\\x1e[/g'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\x1e")
                let ws = [], cl = [], mons = []
                try { ws = JSON.parse(parts[0]); cl = JSON.parse(parts[1]); mons = JSON.parse(parts[2]) } catch (e) { return }
                const m = {}
                for (const x of mons) {
                    m[x.name] = { x: x.x, y: x.y, width: x.width / (x.scale || 1), height: x.height / (x.scale || 1) }
                    if (x.focused) view.focusedWs = x.activeWorkspace.id
                }
                view.monitors = m
                const list = ws.filter(w => w.id > 0).sort((a, b) => a.id - b.id).map(w => ({
                    id: w.id, name: w.name, monitor: w.monitor,
                    windows: cl.filter(c => c.workspace && c.workspace.id === w.id && c.mapped !== false)
                               .sort((a, b) => (a.focusHistoryID || 0) - (b.focusHistoryID || 0))
                }))
                const keepId = view.cur ? view.cur.id : -1
                view.workspaces = list
                if (view.landing) {
                    view.landing = false
                    // open on the workspace before this one (most recent first)
                    // (no history yet - say, just after the shell started: the next one)
                    const prev = view.mru.find(id => id !== view.focusedWs && list.some(w => w.id === id))
                    const here = list.findIndex(w => w.id === view.focusedWs)
                    const i = prev !== undefined ? list.findIndex(w => w.id === prev) : (here + 1) % Math.max(1, list.length)
                    view.sel = Math.max(0, i)
                    view.pos = view.sel
                    view.winSel = -1
                    if (view.pendingSteps) { view.step(view.pendingSteps); view.pendingSteps = 0 }
                } else {
                    const i = list.findIndex(w => w.id === keepId)
                    if (i >= 0) view.sel = i
                }
            }
        }
    }
    Timer { interval: 1000; repeat: true; running: view.active; onTriggered: if (!reader.running) reader.running = true }
    property bool landing: true
    property int pendingSteps: 0                // Alt+Tab pressed again before the first read

    // the order you've visited workspaces in, most recent first (kept while
    // the shell runs, so the overview knows "the one before")
    property var mru: []
    Component.onCompleted: if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0) mru = [Hyprland.focusedWorkspace.id]
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            const w = Hyprland.focusedWorkspace
            if (!w || w.id <= 0) return
            view.mru = [w.id].concat(view.mru.filter(id => id !== w.id)).slice(0, 20)
        }
    }

    // every window's live picture comes from its Wayland toplevel
    readonly property var toplevelByAddress: {
        const m = {}
        for (const t of ToplevelManager.toplevels.values)
            if (t.HyprlandToplevel) m["0x" + t.HyprlandToplevel.address] = t
        return m
    }

    property int sel: 0
    property real pos: 0                        // the carousel's position, easing after sel
    property int winSel: -1                     // a window picked in it (-1: the workspace)
    readonly property var shown: workspaces
    readonly property var cur: shown[Math.max(0, Math.min(sel, shown.length - 1))] || null
    readonly property var curWin: cur && winSel >= 0 ? cur.windows[winSel] || null : null
    onSelChanged: {
        winSel = -1
        if (glitchLevel > 0) fireGlitch(["tear", "tear", "blocks", "vhs", "bleed"][Math.floor(Math.random() * 5)], (0.15 + Math.random() * 0.15) * glitchLevel)
        revealAnim.restart()
    }
    property real reveal: 1
    NumberAnimation { id: revealAnim; target: view; property: "reveal"; from: 0.35; to: 1; duration: 380; easing.type: Easing.OutQuad }

    // what each window costs (wsstats.py, a line every 1.5 s while up)
    property var stats: ({ windows: {}, cpu: 0, mem: 0 })
    Process {
        id: statsProc
        running: view.active
        command: ["python3", Qt.resolvedUrl("wsstats.py").toString().replace(/^file:\/\//, "")]
        stdout: SplitParser { onRead: line => { try { view.stats = JSON.parse(line) } catch (e) {} } }
    }
    function wsCost(w) {
        let cpu = 0, mem = 0
        const pids = {}
        for (const c of (w ? w.windows : [])) {
            const s = stats.windows[c.address]
            if (!s || pids[c.pid]) continue
            pids[c.pid] = true
            cpu += s.cpu; mem += s.mem
        }
        return { cpu: cpu, mem: mem }
    }
    function human(n) {
        const u = ["B", "KB", "MB", "GB"]
        let i = 0
        while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
        return (i ? n.toFixed(i > 1 ? 1 : 0) : n) + " " + u[i]
    }

    // ---------------------------------------------------- carousel layouts
    readonly property var carouselStyles: ["arc", "line", "hand", "ring", "panorama", "triple", "grid", "pills", "blips"]
    property int gridCols: 6
    property real posRow: 0                    // the grid's scroll, easing after sel's row
    // where a card goes: off is its distance from the highlighted one (it
    // eases, so cards glide); returns position, size, scale, tilt (rot) and
    // turn (ry, about the vertical), depth, opacity, corner radius, and how
    // far it's shrunk to a pill
    function place(style, off, i) {
        const aw = arc.width, W = arc.cardW, H = arc.cardH, cx = aw / 2, a = Math.abs(off)
        const near = Math.max(0, 1 - a)
        const p = { x: cx - W / 2, y: 10, w: W, h: H, s: 1, rot: 0, ry: 0, z: 0, o: 1, radius: 6, pill: 0, vis: true }
        if (style === "line") {
            const sp = W * 0.62 + 24
            p.s = 0.62 + 0.38 * near
            p.x = cx + off * sp + Math.sign(off) * Math.min(1, a) * W * 0.19 - W / 2
            p.y = 10 + (1 - p.s) * H * 0.35
            p.o = 1 - Math.min(0.7, a * 0.07)
            p.z = 100 - a
            p.vis = a < aw / sp / 2 + 1.5
        } else if (style === "hand") {
            // a fanned hand of cards, the highlighted one lifted out of it
            const ang = off * 0.065, R = aw * 1.15
            p.x = cx + Math.sin(ang) * R - W / 2
            p.y = 46 + (1 - Math.cos(ang)) * R - 56 * near
            p.rot = ang * 180 / Math.PI * (1 - near)
            p.s = 0.78 + 0.22 * near
            p.z = 100 + off + 60 * near
            p.vis = a < 11
        } else if (style === "ring") {
            // a carousel turning in 3D: the far side small and dim behind
            const n = Math.max(6, Math.min(shown.length, 16)), ang = off * 2 * Math.PI / n
            const d = Math.cos(ang)
            p.x = cx + Math.sin(ang) * aw * 0.34 - W / 2
            p.y = 24 - d * 14
            p.s = 0.45 + 0.4 * (d + 1) / 2 + 0.15 * near
            p.z = d * 100
            p.o = 0.18 + 0.82 * (d + 1) / 2
            p.ry = -Math.sin(ang) * 35
            p.vis = a <= n / 2
        } else if (style === "panorama") {
            // a wall of cards bending away to either side
            const sp = W * 0.66
            p.ry = Math.max(-62, Math.min(62, -off * 26))
            p.x = cx + off * sp * (1 - Math.min(0.25, a * 0.03)) - W / 2
            p.s = 0.86 + 0.14 * near
            p.o = 1 - Math.min(0.6, a * 0.08)
            p.z = 100 - a
            p.vis = a < 7
        } else if (style === "triple") {
            p.x = cx + off * W * 0.95 - W / 2
            p.s = 1 - 0.3 * Math.min(1, a)
            p.o = (1 - 0.45 * Math.min(1, a)) * Math.max(0, Math.min(1, 1.7 - a))
            p.z = 100 - a
            p.vis = a < 1.7
        } else if (style === "grid") {
            // rows of smaller cards, scrolling a row at a time
            const gw = W * 0.62, gh = H * 0.62, cols = gridCols
            const row = Math.floor(i / cols), col = i % cols
            const rowOff = row - posRow
            p.w = gw; p.h = gh
            p.x = (aw - cols * (gw + 14) + 14) / 2 + col * (gw + 14)
            p.y = 6 + (rowOff + 0.15) * (gh + 16)
            p.s = i === sel ? 1.08 : 1
            p.z = i === sel ? 200 : 100
            p.o = Math.max(0, Math.min(1, 1.6 - Math.abs(rowOff - 0.5) * 1.3))
            p.vis = rowOff > -1.2 && rowOff < 2.2
        } else if (style === "pills") {
            // thin pills in each theme's colours; the highlighted one opens
            // out into its card
            const pw = 46, gap = 12
            const w = pw + (W - pw) * near
            const c = Math.sign(off) * (Math.min(1, a) * (W / 2 + gap + pw / 2) + Math.max(0, a - 1) * (pw + gap))
            p.w = w
            p.x = cx + c - w / 2
            p.radius = 14 * near + (pw / 2) * (1 - near)
            p.pill = 1 - Math.min(1, near * 1.6)
            p.z = 100 - a
            p.vis = a < (aw / 2 - W / 2) / (pw + gap) + 1
        } else if (style === "blips") {
            // only the highlighted card, risen over its blip
            p.y = 6
            p.o = Math.max(0, 1 - a * 1.8)
            p.s = 0.9 + 0.1 * near
            p.vis = a < 0.6
        } else {
            // arc (cover flow)
            const th = off * 0.3, d = Math.cos(Math.max(-1.55, Math.min(1.55, th)))
            p.x = cx + Math.sin(th) * aw * 0.44 - W / 2
            p.y = 10 + (1 - d) * 40
            p.z = d * 100
            p.s = 0.45 + 0.55 * d
            p.o = 0.25 + 0.75 * d
            p.vis = a < 9 && d > 0.05
        }
        return p
    }

    // r: a random theme (never the highlighted one again); Shift+R applies it too
    function randomPick(andApply) {
        if (shown.length < 2) return
        let i = sel
        while (i === sel) i = Math.floor(Math.random() * shown.length)
        terminal.push("> random palette :: " + shown[i].name)
        sel = i
        if (glitchLevel > 0) fireGlitch(["blocks", "tear", "vhs"][Math.floor(Math.random() * 3)], 0.5 * glitchLevel)
        if (andApply) apply(shown[i])
    }

    function step(d) {
        if (!shown.length) return
        sel = ((sel + d) % shown.length + shown.length) % shown.length
    }
    function stepWindow(d) {
        if (!cur || !cur.windows.length) return
        const n = cur.windows.length
        winSel = winSel < 0 ? (d > 0 ? 0 : n - 1) : ((winSel + d) % n + n) % n
    }
    function jump(id) {
        const i = shown.findIndex(w => w.id === id)
        if (i >= 0) sel = i
        else terminal.push("> workspace " + id + " :: empty")
    }

    // go: to the workspace (and the window, if one's picked), glitching out
    function go() {
        if (!cur) { if (closeRequest) closeRequest(); return }
        const ws = cur.id, win = curWin
        terminal.push("> jumping :: workspace " + ws + (win ? " :: " + (win.class || win.title) : ""))
        view.goTo = { ws: ws, address: win ? win.address : "" }
        dispatchGo()                     // switch underneath, then glitch out onto it
        goSoon.restart()
    }
    Timer { id: goSoon; interval: 140; onTriggered: if (view.closeRequest) view.closeRequest() }
    property var goTo: null
    function dispatchGo() {
        const g = goTo
        goTo = null
        if (!g) return
        if (g.address)
            Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({window = 'address:${g.address}'})` : `focuswindow address:${g.address}`)
        else
            Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({workspace = '${g.ws}'})` : `workspace ${g.ws}`)
    }

    // ------------------------------------------------------------------ time
    property real t: 0
    FrameAnimation {
        running: view.active && view.visible
        onTriggered: {
            const dt = Math.min(frameTime, 0.05)
            view.t += dt
            view.pos += (view.sel - view.pos) * Math.min(1, dt * 9)
            view.posRow += (Math.floor(view.sel / Math.max(1, view.gridCols)) - view.posRow) * Math.min(1, dt * 9)
        }
    }

    // --------------------------------------------------------------- glitches
    readonly property var glitchKinds: ["tear", "blocks", "vhs", "crt", "bleed", "invert"]
    property real glitch: 0
    property real glitchSeed: 0
    property int glitchKind: 0
    property int glitchHold: 180
    property real burstPeak: 1
    property real shakeX: 0
    property real shakeY: 0
    property real shakeToX: 0
    property real shakeToY: 0
    function fireGlitch(kind, peak) {
        glitchKind = Math.max(0, glitchKinds.indexOf(kind))
        burstPeak = peak === undefined ? 1 : peak
        const jolt = ["vhs", "crt", "bleed"].includes(kind) ? 0.25 : 1
        glitchHold = kind === "vhs" ? 420 : kind === "crt" ? 120 : kind === "bleed" ? 300 : 180
        glitchSeed = Math.random() * 100
        shakeToX = (Math.random() - 0.5) * 14 * jolt * burstPeak
        shakeToY = (Math.random() - 0.5) * 8 * jolt * burstPeak
        burst.restart()
    }
    // the old monitor acting up now and then: any kind (a negative flash
    // only rarely), at any strength, sometimes stuttering two or three times
    // in a row; or the set itself losing sync and rebuilding its picture
    function randomKind() {
        const r = Math.random()
        return r < 0.04 ? "invert" : ["tear", "blocks", "vhs", "crt", "bleed"][Math.floor(Math.random() * 5)]
    }
    Timer {
        id: actingUp
        running: view.active && view.glitchLevel > 0
        interval: 5000
        onTriggered: {
            const r = Math.random()
            if (r < 0.15) {
                revealAnim.restart()                             // signal lost ... reacquired
                terminal.push("> sync lost ... reacquired")
                view.fireGlitch("tear", 0.3)
            } else {
                view.fireGlitch(view.randomKind(), (0.35 + Math.random() * 0.65) * view.glitchLevel)
                if (r > 0.78) { stutter.left = 1 + Math.floor(Math.random() * 2); stutter.restart() }
                if (Math.random() < 0.5) terminal.say()
            }
            interval = 4500 + Math.random() * 10000
            restart()
        }
    }
    Timer {
        id: stutter
        property int left: 0
        interval: 140 + Math.random() * 220
        repeat: true
        onTriggered: {
            const k = view.randomKind()
            view.fireGlitch(k === "invert" ? "tear" : k, (0.3 + Math.random() * 0.5) * Math.max(0.5, view.glitchLevel))
            if (--left <= 0) stop()
        }
    }
    SequentialAnimation {
        id: burst
        ParallelAnimation {
            NumberAnimation { target: view; property: "glitch"; from: 0; to: view.burstPeak; duration: 60 }
            NumberAnimation { target: view; property: "shakeX"; to: view.shakeToX; duration: 60 }
            NumberAnimation { target: view; property: "shakeY"; to: view.shakeToY; duration: 60 }
        }
        PauseAnimation { duration: view.glitchHold }
        ScriptAction { script: if (view.glitchKind !== 3) view.glitchSeed = Math.random() * 100 }
        ParallelAnimation {
            NumberAnimation { target: view; property: "glitch"; to: 0; duration: 160 }
            NumberAnimation { target: view; property: "shakeX"; to: 0; duration: 220; easing.type: Easing.OutBack }
            NumberAnimation { target: view; property: "shakeY"; to: 0; duration: 220; easing.type: Easing.OutBack }
        }
    }

    // opening (0 -> 1) and closing (1 -> 0): a random kind, from / to the desktop
    property real opening: 1
    readonly property bool openingWanted: settings.openGlitch !== false
    property bool closingFx: false
    property var closeDone: null
    function pickTransitionKind() {
        glitchKind = Math.random() < 0.08 ? 5 : Math.floor(Math.random() * 5)
        glitchSeed = Math.random() * 100
    }
    function playOpening() {
        closeAnim.stop()
        closingFx = false
        pickTransitionKind()
        openAnim.restart()
    }
    function playClosing(done) {
        openAnim.stop()
        pickTransitionKind()
        closeDone = done
        closingFx = true
        closeAnim.restart()
    }
    NumberAnimation {
        id: openAnim; target: view; property: "opening"; from: 0; to: 1
        duration: view.glitchKind === 3 ? 760 : 620; easing.type: Easing.InOutQuad
    }
    NumberAnimation {
        id: closeAnim; target: view; property: "opening"; from: 1; to: 0
        duration: view.glitchKind === 3 ? 560 : 440; easing.type: Easing.InOutQuad
        onFinished: { const d = view.closeDone; view.closeDone = null; if (d) d() }
    }

    // fresh each time it opens
    onActiveChanged: if (active) {
        settingsOpen = false
        landing = true
        sel = 0; winSel = -1
        reader.running = true
        forceActiveFocus()
        terminal.scrawl(["> link established :: workspace grid", "> tracing windows..."])
    } else {
        altHeld = false
        pendingSteps = 0
    }

    // -------------------------------------------------------------- keyboard
    Keys.onPressed: event => {
        const k = event.key, ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier
        if (settingsOpen) {
            if (k === Qt.Key_Escape || (k === Qt.Key_Comma && ctrl)) { settingsOpen = false; event.accepted = true }
            return
        }
        const rowStep = settings.carousel === "grid" ? gridCols : 1
        if (k === Qt.Key_Escape) { goTo = null; if (closeRequest) closeRequest() }
        else if (k === Qt.Key_Comma && ctrl) settingsOpen = true
        else if (k === Qt.Key_Tab) step(shift ? -1 : 1)
        else if (k === Qt.Key_Backtab) step(-1)
        else if (k === Qt.Key_Left) step(-1)
        else if (k === Qt.Key_Right) step(1)
        else if (k === Qt.Key_Up) { if (rowStep > 1 && winSel < 0) step(-rowStep); else stepWindow(-1) }
        else if (k === Qt.Key_Down) { if (rowStep > 1 && winSel < 0 && !shift) step(rowStep); else stepWindow(1) }
        else if (k === Qt.Key_A && !ctrl) step(-1)
        else if (k === Qt.Key_D && !ctrl) step(1)
        else if (k === Qt.Key_W && !ctrl) stepWindow(-1)            // W / S like up / down
        else if (k === Qt.Key_S && !ctrl) stepWindow(1)
        else if (k === Qt.Key_Home) sel = 0
        else if (k === Qt.Key_End) sel = Math.max(0, shown.length - 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) go()
        else if (k >= Qt.Key_1 && k <= Qt.Key_9 && !ctrl) jump(k - Qt.Key_0)
        else if (k === Qt.Key_0 && !ctrl) jump(10)
        else if (k === Qt.Key_T && ctrl) { setSetting("crt", !settings.crt); if (glitchLevel > 0) fireGlitch("crt", 0.8 * glitchLevel) }
        else return
        event.accepted = true
    }
    // Alt+Tab: letting go of Alt goes there
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Alt && altHeld && !toggleMode && !settingsOpen) { altHeld = false; go(); event.accepted = true }
    }

    // ------------------------------------------------------------------ scene
    Item {
        id: scene
        anchors.fill: parent

        Rectangle { anchors.fill: parent; color: view.cBg }
        ShaderEffect {
            anchors.fill: parent
            property real time: view.t
            property vector2d resolution: Qt.vector2d(width, height)
            property color tint: Qt.darker(view.skyA, 2.2)
            property color starColor: view.skyA
            fragmentShader: Qt.resolvedUrl("shaders/stars.frag.qsb")
        }
        readonly property vector2d nebulaShift: Qt.vector2d(view.pos * 0.02 + view.t * 0.002, 0)
        Item {
            width: parent.width / 2; height: parent.height / 2
            scale: 2; transformOrigin: Item.TopLeft
            ShaderEffect {
                anchors.fill: parent
                property real time: view.t
                property vector2d resolution: Qt.vector2d(width, height)
                property vector2d shift: scene.nebulaShift
                property color tintA: view.skyB
                property color tintB: view.skyA
                property color dark: view.cBg
                property real mode: 0
                fragmentShader: Qt.resolvedUrl("shaders/nebula.frag.qsb")
            }
        }

        // ------------------------------------------------------------ header
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 34
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "// GLITCH-OVERVIEW  ·  " + view.shown.length + " WORKSPACES  ·  ON " + view.focusedWs
                      + "  ·  CPU " + Math.round(view.stats.cpu) + "%  ·  " + view.human(view.stats.mem)
                color: view.cPrimary; opacity: 0.7
                font.family: view.mono; font.pixelSize: 13; font.letterSpacing: 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !view.cur ? "> scanning..." : "> workspace " + view.cur.id + (view.curWin ? "  ::  " + (view.curWin.class || view.curWin.title) : "")
                      + (cursorBlink.on ? "_" : " ")
                color: view.cText
                font.family: view.mono; font.pixelSize: 22
                Timer { id: cursorBlink; property bool on: true; interval: 530; repeat: true; running: view.active; onTriggered: on = !on }
            }
        }

        // ----------------------------------------------------------- monitor
        // the old CRT set, showing the selected workspace live
        Item {
            id: monitor
            readonly property real screenW: Math.min(1180, view.width * 0.46)
            width: screenW + 56
            height: screenW * 9 / 16 + 56 + 34
            x: (view.width - width) / 2 - view.width * 0.08 + view.shakeX
            y: 108 + view.shakeY
            Rectangle {
                anchors.fill: bezel
                anchors.margins: -18
                radius: bezel.radius + 18
                color: "transparent"
                border.width: 18
                border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.10)
            }
            Rectangle {
                id: bezel
                width: parent.width
                height: parent.height - 34
                radius: 26
                color: Qt.darker(view.cBg, 1.6)
                border.width: 2
                border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.75)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 28
                    radius: 14
                    color: "black"
                    clip: true
                    WsPreview {
                        anchors.fill: parent
                        anchors.margins: 6
                        opacity: view.reveal
                        workspace: view.cur
                        monitors: view.monitors
                        toplevels: view.toplevelByAddress
                        live: true
                        picked: view.curWin ? view.curWin.address : ""
                        accent: view.cPrimary; back: view.cBg; text: view.cText; mono: view.mono
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.06) }
                            GradientStop { position: 0.35; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.3) }
                        }
                    }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 9
                    width: 7; height: 7; radius: 3.5
                    color: view.cur && view.cur.id === view.focusedWs ? view.cPrimary : "#ff4060"
                    opacity: 0.5 + 0.5 * Math.sin(view.t * 3)
                }
            }
            Row {
                anchors.left: parent.left; anchors.leftMargin: 14
                anchors.bottom: parent.bottom
                spacing: 14
                Text {
                    text: view.cur ? "WS " + String(view.cur.id).padStart(2, "0") : ""
                    color: view.cPrimary; font.family: view.mono; font.pixelSize: 14; font.bold: true
                }
                Text {
                    text: view.cur ? view.cur.windows.length + " WINDOW" + (view.cur.windows.length === 1 ? "" : "S") + "  ·  " + view.cur.monitor : ""
                    color: view.cText; font.family: view.mono; font.pixelSize: 14; font.bold: true; font.letterSpacing: 2
                }
                Text {
                    visible: !!view.cur && view.cur.id === view.focusedWs
                    text: "● YOU ARE HERE"
                    color: view.cPrimary; font.family: view.mono; font.pixelSize: 13
                }
            }
        }

        // ---------------------------------------------------------- readout
        // what the selected workspace is costing, window by window
        Rectangle {
            id: readout
            x: monitor.x + monitor.width + 36
            y: monitor.y
            width: Math.min(480, view.width - x - 40)
            height: Math.min(view.height - y - 300, readCol.implicitHeight + 32)
            radius: 6
            visible: width > 260
            color: Qt.rgba(view.cBg.r, view.cBg.g, view.cBg.b, 0.82)
            border.width: 1
            border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.6)
            clip: true
            Column {
                id: readCol
                x: 16; y: 16
                width: parent.width - 32
                spacing: 8
                readonly property var cost: view.wsCost(view.cur)
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: "// WORKSPACE :: " + (view.cur ? view.cur.id + (view.cur.name !== String(view.cur.id) ? " (" + view.cur.name + ")" : "") : "-")
                    color: view.cText; font.family: view.mono; font.pixelSize: 17; font.bold: true
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: !view.cur ? "" : "CPU " + readCol.cost.cpu.toFixed(1) + "%   ·   MEM " + view.human(readCol.cost.mem)
                          + "   ·   " + view.cur.windows.length + " windows"
                    color: view.cPrimary; font.family: view.mono; font.pixelSize: 12
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.35) }
                Text {
                    visible: !!view.cur && view.cur.windows.length === 0
                    text: "> nothing running here"
                    color: view.cText; opacity: 0.6; font.family: view.mono; font.pixelSize: 12
                }
                Repeater {
                    model: view.cur ? view.cur.windows : []
                    delegate: Column {
                        id: wrow
                        required property var modelData
                        required property int index
                        readonly property var s: view.stats.windows[modelData.address] || { cpu: 0, mem: 0, procs: 0 }
                        readonly property bool picked: view.winSel === index
                        width: readCol.width
                        spacing: 3
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: (wrow.picked ? "▶ " : "  ") + (modelData.class || "?") + (modelData.floating ? "  [float]" : "") + (modelData.fullscreen ? "  [full]" : "")
                            color: wrow.picked ? view.cPrimary : view.cText
                            font.family: view.mono; font.pixelSize: 12; font.bold: wrow.picked
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: "  " + (modelData.title || "")
                            color: view.cText; opacity: 0.55; font.family: view.mono; font.pixelSize: 10
                        }
                        // its load, as a bar and numbers
                        Row {
                            spacing: 8
                            x: 12
                            Rectangle {
                                width: readCol.width * 0.42; height: 6; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.15)
                                Rectangle {
                                    width: parent.width * Math.min(1, wrow.s.cpu / 100); height: parent.height; radius: 3
                                    color: wrow.s.cpu > 60 ? "#ff4060" : view.cPrimary
                                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                }
                            }
                            Text {
                                text: wrow.s.cpu.toFixed(1).padStart(5, " ") + "%  " + view.human(wrow.s.mem).padStart(8, " ") + "  " + wrow.s.procs + " proc"
                                color: view.cText; opacity: 0.8; font.family: view.mono; font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------ the carousel
        // every workspace as a card: a small picture of it (one capture),
        // laid out in the chosen style
        Item {
            id: arc
            anchors.left: parent.left; anchors.right: parent.right
            y: monitor.y + monitor.height + 30
            height: view.height - y - 70
            readonly property string style: view.carouselStyles.indexOf(view.settings.carousel) >= 0 ? view.settings.carousel : "line"
            readonly property real cardW: Math.min(360, height * 1.2)
            readonly property real cardH: cardW * 0.62
            readonly property int cols: Math.max(1, Math.floor((width - 120) / (cardW * 0.62 + 14)))
            onColsChanged: view.gridCols = cols
            Component.onCompleted: view.gridCols = cols
            Repeater {
                model: view.shown
                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property var at: view.place(arc.style, index - view.pos, index)
                    readonly property bool isSel: index === view.sel
                    visible: at.vis
                    x: at.x; y: at.y
                    width: at.w; height: at.h
                    z: at.z
                    scale: at.s
                    opacity: at.o
                    rotation: at.rot
                    transform: Rotation {
                        origin.x: card.width / 2; origin.y: card.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: card.at.ry
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: card.at.radius
                        color: "black"
                        border.width: card.isSel ? 2 : 1
                        border.color: card.isSel ? view.cPrimary : Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.45)
                        clip: true
                        WsPreview {
                            anchors.fill: parent
                            anchors.margins: 3
                            visible: card.at.pill < 0.5
                            workspace: card.modelData
                            monitors: view.monitors
                            toplevels: card.at.vis ? view.toplevelByAddress : ({})
                            live: false
                            titles: false
                            accent: view.cPrimary; back: view.cBg; text: view.cText; mono: view.mono
                        }
                        // pills: just its number and how busy it is
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 2
                            radius: Math.max(0, card.at.radius - 2)
                            opacity: card.at.pill
                            visible: opacity > 0.01
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: view.cPrimary }
                                GradientStop { position: 1.0; color: view.cBg }
                            }
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top
                            anchors.margins: 4
                            width: wsLabel.implicitWidth + 12; height: 22; radius: 3
                            color: Qt.rgba(0, 0, 0, 0.7)
                            Text {
                                id: wsLabel
                                anchors.centerIn: parent
                                text: (card.modelData.id === view.focusedWs ? "● " : "") + card.modelData.id
                                      + (card.at.pill < 0.5 ? "  ·  " + card.modelData.windows.length : "")
                                color: card.isSel ? view.cPrimary : view.cText
                                font.family: view.mono; font.pixelSize: 12; font.bold: true
                            }
                        }
                    }
                    Rectangle {
                        visible: card.isSel
                        anchors.fill: parent
                        anchors.margins: -8
                        radius: card.at.radius + 6
                        color: "transparent"
                        border.width: 6
                        border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.22)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.isSel ? view.go() : (view.sel = card.index)
                    }
                }
            }
            Repeater {
                model: arc.style === "blips" ? view.shown : []
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property real off: index - view.pos
                    readonly property real near: Math.max(0, 1 - Math.abs(off))
                    width: 8 + 10 * near; height: width; radius: width / 2
                    x: arc.width / 2 + off * 26 - width / 2
                    y: arc.cardH + 46 - height / 2
                    color: modelData.id === view.focusedWs ? view.cPrimary : view.cText
                    opacity: 0.35 + 0.65 * near
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: view.sel = parent.index }
                }
            }
        }
        WheelHandler { onWheel: event => view.step(event.angleDelta.y > 0 || event.angleDelta.x > 0 ? -1 : 1) }

        // the options button
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 30
            width: gearText.implicitWidth + 24; height: 32; radius: 4
            color: gearHover.hovered ? Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.15) : "transparent"
            border.width: 1
            border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.6)
            Text { id: gearText; anchors.centerIn: parent; text: "[ options ]"; color: view.cPrimary; font.family: view.mono; font.pixelSize: 13 }
            HoverHandler { id: gearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: view.settingsOpen = !view.settingsOpen }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 26
            text: "[TAB / ← → / A D] workspace   [↑ ↓ / W S] window   [1-9] jump   [ENTER] go"
                  + (view.toggleMode ? " (or ALT+TAB again)" : view.altHeld ? " (or let go of ALT)" : "")
                  + "   [CTRL+T] crt   [CTRL+,] options   [ESC] stay"
            color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 12
        }

        // a terminal in the corner that talks now and then
        Column {
            id: terminal
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 40
            spacing: 2
            ListModel { id: termLines }
            property var queue: []
            function push(text) {
                termLines.append({ line: text.length > 64 ? text.slice(0, 63) + "…" : text })
                while (termLines.count > 8) termLines.remove(0)
            }
            function scrawl(list) { queue = queue.concat(list) }
            Timer {
                interval: 240; repeat: true
                running: terminal.queue.length > 0
                onTriggered: { terminal.push(terminal.queue[0]); terminal.queue = terminal.queue.slice(1) }
            }
            readonly property var phrases: [
                "> polling compositor :: ok", "> frame sync 0x%h", "> window table %n entries", "> sync lost ... reacquired",
                "> scheduler load %n%", "> wake up, operator", "> signal %n% :: holding", "> follow the white rabbit"]
            function say() {
                if (queue.length) return
                // now and then, an easter egg instead (eggs.js)
                const egg = Eggs.maybe(0.3)
                if (egg) { push(egg); return }
                let s = phrases[Math.floor(Math.random() * phrases.length)]
                s = s.replace("%h", Math.floor(Math.random() * 0xffff).toString(16).padStart(4, "0")).replace("%n", Math.floor(Math.random() * 99))
                push(s)
            }
            Repeater {
                model: termLines
                delegate: Text {
                    required property string line
                    required property int index
                    property int shown: 0
                    text: line.slice(0, shown) + (shown < line.length ? "▌" : "")
                    color: view.cPrimary
                    opacity: 0.25 + 0.6 * (index + 1) / termLines.count
                    font.family: view.mono; font.pixelSize: 12
                    Timer { interval: 18; repeat: true; running: parent.shown < parent.line.length; onTriggered: parent.shown++ }
                }
            }
        }
    }

    // ---------------------------------------------- the glitch / CRT pass
    ShaderEffectSource {
        id: sceneTex
        anchors.fill: parent
        sourceItem: scene
        hideSource: true
        live: true
        visible: false
    }
    ShaderEffectSource { id: deskTex; sourceItem: view.deskItem; hideSource: true; live: true; visible: false }
    ShaderEffect {
        anchors.fill: parent
        property var source: sceneTex
        property var desk: deskTex
        property real time: view.t
        property vector2d resolution: Qt.vector2d(width, height)
        property real intensity: view.glitch
        property real seed: view.glitchSeed
        property real scanlines: 1
        property color tint: view.cPrimary
        property real kind: view.glitchKind
        property real trans: view.opening
        property real crt: view.settings.crt === false ? 0 : 1
        property real closing: view.closingFx ? 1 : 0
        property vector2d shockCenter: Qt.vector2d(0, 0)
        property real shockR: 0
        property real shockAmt: 0
        fragmentShader: Qt.resolvedUrl("shaders/glitch.frag.qsb")
    }

    // ---------------------------------------------------------------- options
    // drawn outside the glitch pass, so it stays readable
    property bool settingsOpen: false
    Rectangle {
        id: options
        visible: view.settingsOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 72
        anchors.rightMargin: 30
        width: 420
        height: optCol.implicitHeight + 32
        radius: 6
        color: Qt.rgba(view.cBg.r, view.cBg.g, view.cBg.b, 0.95)
        border.width: 1
        border.color: view.cPrimary
        MouseArea { anchors.fill: parent }        // keep clicks off the cards

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

        ColumnLayout {
            id: optCol
            x: 16; y: 16
            width: parent.width - 32
            spacing: 10
            Text { text: "> OPTIONS"; color: view.cText; font.family: view.mono; font.pixelSize: 16; font.bold: true }

            Heading { text: "CAROUSEL" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Repeater {
                    model: [["arc", "Arc"], ["line", "Line"], ["hand", "Hand"], ["ring", "Ring"], ["panorama", "Panorama"],
                            ["triple", "Triple"], ["grid", "Grid"], ["pills", "Pills"], ["blips", "Blips"]]
                    delegate: Chip {
                        required property var modelData
                        label: modelData[1]
                        on: (view.carouselStyles.indexOf(view.settings.carousel) >= 0 ? view.settings.carousel : "arc") === modelData[0]
                        onClicked: view.setSetting("carousel", modelData[0])
                    }
                }
            }

            Heading { text: "ALT+TAB" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Chip { label: "Hold Alt"; on: !view.toggleMode; onClicked: view.setSetting("mode", "hold") }
                Chip { label: "Toggle"; on: view.toggleMode; onClicked: view.setSetting("mode", "toggle") }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: view.toggleMode ? "stays up: ALT+TAB again, ENTER or a click goes · ESC stays" : "letting go of ALT goes"
                color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 10
            }

            Heading { text: "SCREEN" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Chip { label: "CRT monitor"; on: view.settings.crt !== false; onClicked: view.setSetting("crt", view.settings.crt === false) }
            }

            Heading { text: "GLITCHES" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Chip { label: "Normal"; on: (view.settings.glitch || "normal") === "normal"; onClicked: view.setSetting("glitch", "normal") }
                Chip { label: "Subtle"; on: view.settings.glitch === "subtle"; onClicked: view.setSetting("glitch", "subtle") }
                Chip { label: "Off"; on: view.settings.glitch === "off"; onClicked: view.setSetting("glitch", "off") }
                Chip { label: "Open/close glitch"; on: view.settings.openGlitch !== false; onClicked: view.setSetting("openGlitch", view.settings.openGlitch === false) }
            }
            Text { text: "[ESC] close options"; color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 11 }
        }
    }
}
