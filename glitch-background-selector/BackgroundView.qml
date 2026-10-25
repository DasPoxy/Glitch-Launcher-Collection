import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
// Omarchy's theme colours, qualified: since Qt 6.12 a bare `Color` is
// QtQuick's own Color singleton, whose .accent etc. are undefined.
import qs.Commons as Omarchy
import "eggs.js" as Eggs

// Glitch-Background-Selector's scene: your wallpapers on a carousel under an
// old CRT monitor showing the highlighted one, its size and colours read out
// beside it, over a starfield and a nebula tinted by it. The current theme's
// wallpapers come first, together; then the ones in your folder (options).
// Arrows or WASD browse, T jumps to the theme's wallpapers, F to your folder's, /
// filters, Enter sets it (it stays open), Tab changes the monitor's look,
// Ctrl+T switches the CRT off / on, Ctrl+, opens the options. The screen
// glitches now and then, a little as you browse, hard when one is set - and
// on the way in and out.
FocusScope {
    id: view

    property bool active: false
    property var closeRequest: null
    property var deskItem: null                // the desktop, captured as it opened

    // ---------------------------------------------------------------- settings
    // ~/.config/glitch-background-selector/settings.json
    readonly property string settingsPath: Quickshell.env("HOME") + "/.config/glitch-background-selector/settings.json"
    property var settings: ({ crt: true, look: "clean", carousel: "arc", glitch: "normal", openGlitch: true, afterApply: "stay", fit: "fill", desktopLook: "off",
                              desktopColors: ["#3dff8a", "#11c46a", "#010603"],
                              folder: "~/Pictures/Wallpapers" })
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
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/glitch-background-selector"] }
    readonly property string folderPath: (settings.folder || "").replace(/^~(?=\/|$)/, Quickshell.env("HOME"))

    // the UI's colours: the highlighted wallpaper's own (its brightest, most
    // vivid colour for the accent, its darkest for the panels), the running
    // theme's until it's read - easing across as you browse
    property color cPrimary: pAccent
    property color cGlow: pSecond
    property color cBg: pDark
    property color cText: pLight
    Behavior on cPrimary { ColorAnimation { duration: 450 } }
    Behavior on cGlow { ColorAnimation { duration: 450 } }
    Behavior on cBg { ColorAnimation { duration: 450 } }
    Behavior on cText { ColorAnimation { duration: 450 } }
    readonly property string mono: Style.font.family || "monospace"

    // ------------------------------------------------------------ wallpapers
    // backgrounds.py: {theme, current, items: [{path, name, section, dir}]}
    property var items: []
    property string themeName: ""
    property string currentPath: ""
    property string currentFit: "fill"            // the fit it was set in
    property string currentLook: "clean"          // and the look baked into it
    Process {
        id: bgReader
        command: ["python3", Qt.resolvedUrl("backgrounds.py").toString().replace(/^file:\/\//, ""), view.folderPath]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = { items: [] }
                try { d = JSON.parse(text) } catch (e) {}
                // on opening, land on the one in use; after setting one, stay put
                const keep = view.landOnCurrent ? "" : (view.cur ? view.cur.path : "")
                view.landOnCurrent = false
                view.themeName = d.theme || ""
                view.currentPath = d.current || ""
                view.currentFit = d.mode || "fill"
                view.currentLook = d.look || "clean"
                view.items = d.items || []
                let i = view.shown.findIndex(b => b.path === (keep || view.currentPath))
                if (i < 0) i = 0
                view.sel = i
                if (!keep) view.pos = i
            }
        }
    }
    onFolderPathChanged: if (active) bgReader.running = true
    property bool landOnCurrent: true
    property string query: ""
    property bool filtering: false             // after "/": typing filters
    readonly property var shown: {
        const q = query.trim().toLowerCase()
        return q ? items.filter(b => (b.name + " " + b.dir).toLowerCase().includes(q)) : items
    }
    property int sel: 0
    property real pos: 0                       // the carousel's position, easing after sel
    readonly property var cur: shown[Math.max(0, Math.min(sel, shown.length - 1))] || null
    onShownChanged: if (sel >= shown.length) sel = Math.max(0, shown.length - 1)
    readonly property int themeCount: shown.filter(b => b.section === "theme").length
    function jumpTo(section) {
        const i = shown.findIndex(b => b.section === section)
        if (i >= 0) sel = i
        else terminal.push(section === "theme" ? "> the theme has no wallpapers" : "> nothing in your folder")
    }

    // r: a random one (never the highlighted one again); Shift+R sets it too
    function randomPick(andSet) {
        if (shown.length < 2) return
        let i = sel
        while (i === sel) i = Math.floor(Math.random() * shown.length)
        terminal.push("> random frame :: " + shown[i].name)
        sel = i
        if (glitchLevel > 0) fireGlitch(["blocks", "tear", "vhs"][Math.floor(Math.random() * 3)], 0.5 * glitchLevel)
        if (andSet) apply(shown[i])
    }

    // the highlighted wallpaper's palette (palette.py), read once it settles
    property var palette: ({ w: 0, h: 0, colors: [] })
    Timer { id: paletteSettle; interval: 120; onTriggered: { paletteReader.running = false; if (view.cur) { paletteReader.command = ["python3", Qt.resolvedUrl("palette.py").toString().replace(/^file:\/\//, ""), view.cur.path]; paletteReader.running = true } } }
    Process {
        id: paletteReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(text)
                    if (view.cur && p.path === view.cur.path) view.palette = p
                } catch (e) {}
            }
        }
    }
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function vivid(c) { const mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b); return (mx - mn) * (0.4 + mx) }
    readonly property var pcols: (palette.colors || []).map(h => Qt.color(h))
    // accent: the most vivid colour, lifted if it's too dark to read
    readonly property color pAccent: {
        if (!pcols.length) return Omarchy.Color.accent
        const c = pcols.slice().sort((a, b) => vivid(b) - vivid(a))[0]
        return lum(c) < 0.35 ? Qt.lighter(c, 1 + (0.35 - lum(c)) * 4) : c
    }
    readonly property color pSecond: {
        if (pcols.length < 2) return Qt.darker(pAccent, 1.4)
        const c = pcols.slice().sort((a, b) => vivid(b) - vivid(a))[1]
        return lum(c) < 0.25 ? Qt.lighter(c, 1.8) : c
    }
    readonly property color pDark: {
        if (!pcols.length) return Omarchy.Color.background
        const c = pcols.slice().sort((a, b) => lum(a) - lum(b))[0]
        return Qt.darker(c, lum(c) > 0.15 ? 3 : 1.4)
    }
    readonly property color pLight: {
        if (!pcols.length) return Omarchy.Color.foreground
        const c = pcols.slice().sort((a, b) => lum(b) - lum(a))[0]
        return lum(c) < 0.7 ? Qt.lighter(c, 1 + (0.8 - lum(c)) * 2) : c
    }
    property color skyA: cPrimary
    property color skyB: cGlow
    readonly property color tAccent: cPrimary
    readonly property color tSecond: cGlow
    readonly property color tBack: Qt.darker(cBg, 1.3)
    function human(n) {
        const u = ["B", "KB", "MB", "GB"]
        let i = 0
        while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
        return (i ? n.toFixed(1) : n) + " " + u[i]
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

    function step(d) {
        if (!shown.length) return
        sel = ((sel + d) % shown.length + shown.length) % shown.length
    }
    // browsing: a small glitch, of any of the lighter kinds
    readonly property real glitchLevel: settings.glitch === "off" ? 0 : settings.glitch === "subtle" ? 0.5 : 1
    onSelChanged: {
        if (glitchLevel > 0)
            fireGlitch(["tear", "tear", "blocks", "vhs", "bleed"][Math.floor(Math.random() * 5)], (0.18 + Math.random() * 0.17) * glitchLevel)
        revealAnim.restart(); paletteReveal.restart(); paletteSettle.restart()
    }

    readonly property var fitModes: ["fill", "fit", "blur", "stretch", "center", "tile"]
    // options: the monitor's look on the desktop too - "off", "baked" (a
    // still, rendered into the picture) or "live" (GlitchBackgroundSelector's
    // desktop layer runs the shader over the wallpaper)
    readonly property string desktopLook: ["off", "baked", "live"].indexOf(settings.desktopLook) >= 0 ? settings.desktopLook : "off"
    readonly property string monitorLook: ["clean", "grid", "glyph", "rain"].indexOf(settings.look) >= 0 ? settings.look : "clean"
    readonly property string bakedLook: desktopLook === "baked" ? monitorLook : "clean"
    function hexOf(c) { return "#" + [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("") }
    // set it: `omarchy theme bg set`, a hard glitch, and stay open
    Process {
        id: applier
        property string name: ""
        property real pixels: 0                              // its size, to judge the decode
        property bool thenClose: false
        onExited: (code) => {
            terminal.push(code === 0 ? "> wallpaper set :: " + applier.name : "> failed (" + code + ") :: " + applier.name)
            bgReader.running = true                          // the one in use has changed
            if (thenClose) {
                thenClose = false
                // the shell's background now decodes the picture and fades it
                // in (420 ms): go once that's surely done, so the desktop we
                // glitch out to already shows it
                outAfterApply.interval = Math.min(2100, 700 + applier.pixels / 24000)
                outAfterApply.restart()
                if (code === 0) terminal.push("> letting the backdrop settle...")
            }
        }
    }
    function apply(b) {
        if (!b) return
        if (b.path === currentPath && currentFit === (fitModes.indexOf(settings.fit) >= 0 ? settings.fit : "fill") && currentLook === bakedLook) {
            // nothing to repaint -- but with the live desktop look the effect
            // is what's being applied: take this picture's colours for it,
            // and leave the way a new background does (glitching out to the
            // desktop when that's the setting)
            if (desktopLook === "live") setSetting("desktopColors", [hexOf(pAccent), hexOf(pSecond), hexOf(Qt.darker(pDark, 1.3))])
            if (settings.afterApply === "close") {
                terminal.push(desktopLook === "live" && monitorLook !== "clean" ? "> desktop look :: " + monitorLook + " (live)" : "> already on screen :: " + b.name)
                if (glitchLevel > 0) {
                    fireGlitch(["blocks", "vhs", "crt", "bleed", "tear"][Math.floor(Math.random() * 5)], glitchLevel)
                    stutter.left = 2; stutter.restart()
                }
                outAfterApply.interval = 700
                outAfterApply.restart()
            } else {
                terminal.push("> already on screen :: " + b.name)
                fireGlitch("tear", 0.4 * glitchLevel)
            }
            return
        }
        if (applier.running) return
        applier.name = b.name
        applier.pixels = view.palette.path === b.path && view.palette.w ? view.palette.w * view.palette.h : 3840 * 2160
        applier.thenClose = settings.afterApply === "close"
        // another fit than fill: render it at the screen's size first
        const fit = fitModes.indexOf(settings.fit) >= 0 ? settings.fit : "fill"
        // the look's colours: this picture's own (as the UI wears them),
        // kept for the live desktop layer too
        const cols = [hexOf(pAccent), hexOf(pSecond), hexOf(Qt.darker(pDark, 1.3))]
        if (desktopLook !== "off") setSetting("desktopColors", cols)
        applier.command = fit === "fill" && bakedLook === "clean" ? ["omarchy-theme-bg-set", b.path]
            : ["bash", "-c", "out=$(python3 \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" \"$7\") && omarchy-theme-bg-set \"$out\"", "_",
               Qt.resolvedUrl("render-bg.py").toString().replace(/^file:\/\//, ""), b.path, fit, bakedLook, cols[0], cols[1], cols[2]]
        applier.running = true
        if (glitchLevel > 0) {
            fireGlitch(["blocks", "vhs", "crt", "bleed", "tear"][Math.floor(Math.random() * 5)], glitchLevel)
            stutter.left = 2; stutter.restart()                  // and it keeps fighting it
        }
        terminal.scrawl(["> repainting the backdrop :: " + b.name])
    }
    // options: after setting one, glitch out to the desktop - but only once the
    // shell has actually put it up (started when bg set returns, above)
    Timer { id: outAfterApply; interval: 900; onTriggered: if (view.closeRequest) view.closeRequest() }
    // ...glitching the whole while, so it runs straight into the glitch-out
    Timer {
        interval: 210 + Math.random() * 120
        repeat: true
        running: view.glitchLevel > 0 && ((applier.running && applier.thenClose) || outAfterApply.running)
        onTriggered: view.fireGlitch(["tear", "blocks", "vhs", "bleed"][Math.floor(Math.random() * 4)], (0.3 + Math.random() * 0.35) * view.glitchLevel)
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
        query = ""
        filtering = false
        settingsOpen = false
        landOnCurrent = true
        bgReader.running = true
        forceActiveFocus()
        terminal.scrawl(["> link established :: backdrop archive", "> " + (items.length || "scanning") + " frames on file"])
    }

    // -------------------------------------------------------------- keyboard
    Keys.onPressed: event => {
        let k = event.key
        const ctrl = event.modifiers & Qt.ControlModifier
        if (settingsOpen) {
            if (k === Qt.Key_Escape || (k === Qt.Key_Comma && ctrl)) { settingsOpen = false; view.forceActiveFocus(); event.accepted = true }
            return
        }
        // "/" starts a filter; while filtering, letters type into it
        if (filtering) {
            if (k === Qt.Key_Escape) { filtering = false; query = ""; event.accepted = true; return }
            if (k === Qt.Key_Backspace) { if (query) query = query.slice(0, -1); else filtering = false; sel = 0; pos = 0; event.accepted = true; return }
            if (event.text && event.text.length === 1 && event.text >= " " && !ctrl) { query += event.text; sel = 0; pos = 0; event.accepted = true; return }
        }
        // W A S D browse like the arrows (not with Ctrl; while filtering they type)
        if (!ctrl) k = ({ [Qt.Key_W]: Qt.Key_Up, [Qt.Key_A]: Qt.Key_Left, [Qt.Key_S]: Qt.Key_Down, [Qt.Key_D]: Qt.Key_Right })[k] || k
        const rowStep = settings.carousel === "grid" ? gridCols : 1
        if (k === Qt.Key_Escape) { if (query) query = ""; else if (closeRequest) closeRequest() }
        else if (k === Qt.Key_Slash && !ctrl) { filtering = true; query = "" }
        else if (k === Qt.Key_T && !ctrl) jumpTo("theme")
        else if (k === Qt.Key_F && !ctrl) jumpTo("folder")
        else if (k === Qt.Key_R && !ctrl) randomPick(!!(event.modifiers & Qt.ShiftModifier))
        else if (k === Qt.Key_Comma && ctrl) settingsOpen = true
        else if (k === Qt.Key_Left) step(-1)
        else if (k === Qt.Key_Right) step(1)
        else if (k === Qt.Key_Up) step(-rowStep)
        else if (k === Qt.Key_Down) step(rowStep)
        else if (k === Qt.Key_PageUp) step(-5)
        else if (k === Qt.Key_PageDown) step(5)
        else if (k === Qt.Key_Home) sel = 0
        else if (k === Qt.Key_End) sel = Math.max(0, shown.length - 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) apply(cur)
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            const looks = ["clean", "grid", "glyph", "rain"], back = k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
            setSetting("look", looks[(looks.indexOf(settings.look) + (back ? 3 : 1)) % 4])
            revealAnim.restart()
        }
        else if (k === Qt.Key_T && ctrl) { setSetting("crt", !settings.crt); if (glitchLevel > 0) fireGlitch("crt", 0.8 * glitchLevel) }
        else return
        event.accepted = true
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
        // the nebula, in the highlighted theme's colours, sliding as you browse
        readonly property vector2d nebulaShift: Qt.vector2d(view.pos * 0.012 + view.t * 0.002, 0)
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
        ShaderEffect {
            anchors.fill: parent
            property real time: view.t
            property vector2d resolution: Qt.vector2d(width, height)
            property vector2d shift: scene.nebulaShift
            property color tintA: view.skyB
            property color tintB: view.skyA
            property color dark: view.cBg
            property real mode: 1
            fragmentShader: Qt.resolvedUrl("shaders/nebula.frag.qsb")
        }

        // ------------------------------------------------------------ header
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 34
            spacing: 6
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: "// GLITCH-BACKGROUND-SELECTOR  ·  " + view.shown.length + " WALLPAPERS"
                      + (view.themeName ? "  ·  THEME: " + view.themeName.toUpperCase().replace(/-/g, " ") + " (" + view.themeCount + ")" : "")
                      + (view.query ? "  ·  FILTER ACTIVE" : "")
                color: view.cPrimary; opacity: 0.7
                font.family: view.mono; font.pixelSize: 13; font.letterSpacing: 2
            }
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: (view.filtering ? "/" + view.query : "> [/] filter   [T] theme   [F] your folder   [R] random") + (cursorBlink.on ? "_" : " ")
                color: view.filtering ? view.cText : Qt.rgba(view.cText.r, view.cText.g, view.cText.b, 0.45)
                font.family: view.mono; font.pixelSize: 22
                Timer { id: cursorBlink; property bool on: true; interval: 530; repeat: true; running: view.active; onTriggered: on = !on }
            }
        }

        // ----------------------------------------------------------- monitor
        // an old CRT set: a thick bezel glowing in the theme's accent, the
        // preview on its screen through the chosen look, a channel strip
        Item {
            id: monitor
            readonly property real screenW: Math.min(1180, view.width * 0.46)
            width: screenW + 56
            height: screenW * 9 / 16 + 56 + 34
            x: (view.width - width) / 2 - view.width * 0.08 + view.shakeX
            y: 108 + view.shakeY

            // the glow behind the set
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
                Behavior on border.color { ColorAnimation { duration: 400 } }
                // the screen
                Rectangle {
                    id: screenGlass
                    anchors.fill: parent
                    anchors.margins: 28
                    radius: 14
                    color: "black"
                    clip: true
                    Item {
                        id: screenContent
                        anchors.fill: parent
                        // the screen previews the chosen fit: a blurred backdrop for
                        // blur fit (a tiny copy, scaled up), the picture laid out as
                        // the desktop will show it (actual size scaled to the set)
                        readonly property string fit: view.fitModes.indexOf(view.settings.fit) >= 0 ? view.settings.fit : "fill"
                        readonly property real k: width / 2560
                        Rectangle { anchors.fill: parent; color: view.palette.colors && view.palette.colors.length ? view.palette.colors.slice().sort((a, b) => view.lum(Qt.color(a)) - view.lum(Qt.color(b)))[0] : "black" }
                        Image {
                            anchors.fill: parent
                            visible: !!view.cur && screenContent.fit === "blur"
                            source: visible ? shot.source : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(48, 27)
                            smooth: true
                            asynchronous: true
                            opacity: 0.55
                        }
                        Image {
                            id: shot
                            readonly property bool actual: screenContent.fit === "center" || screenContent.fit === "tile"
                            anchors.centerIn: parent
                            width: actual && screenContent.fit === "center" && view.palette.w ? view.palette.w * screenContent.k : parent.width
                            height: actual && screenContent.fit === "center" && view.palette.h ? view.palette.h * screenContent.k : parent.height
                            visible: !!view.cur
                            source: view.cur ? "file://" + encodeURI(view.cur.path).replace(/#/g, "%23").replace(/\?/g, "%3F") : ""
                            fillMode: screenContent.fit === "fit" || screenContent.fit === "blur" ? Image.PreserveAspectFit
                                    : screenContent.fit === "stretch" ? Image.Stretch
                                    : screenContent.fit === "tile" ? Image.Tile
                                    : screenContent.fit === "center" ? Image.Stretch
                                    : Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: screenContent.fit === "tile" && view.palette.w ? Qt.size(view.palette.w * screenContent.k, view.palette.h * screenContent.k) : Qt.size(1400, 800)
                        }
                    }
                    ShaderEffectSource { id: screenTex; sourceItem: screenContent; hideSource: true; live: true; visible: false }
                    ShaderEffect {
                        anchors.fill: parent
                        property var source: screenTex
                        property var glyphs: glyphTex
                        property real time: view.t
                        property vector2d resolution: Qt.vector2d(width, height)
                        property real look: Math.max(0, ["clean", "grid", "glyph", "rain"].indexOf(view.settings.look))
                        property real reveal: view.reveal
                        property real glyphCount: glyphRow.count
                        property color primary: view.cPrimary
                        property color glow: view.cGlow
                        property color bg: view.tBack
                        fragmentShader: Qt.resolvedUrl("shaders/preview.frag.qsb")
                    }
                    // the glass: a sheen and a vignette
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
                            GradientStop { position: 0.35; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.35) }
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !view.cur
                        text: view.items.length ? "> NO SIGNAL :: nothing matches \"" + view.query + "\"" : "> NO SIGNAL :: no wallpapers found"
                        color: view.cPrimary; font.family: view.mono; font.pixelSize: 20
                    }
                }
                // a power light
                Rectangle {
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 9
                    width: 7; height: 7; radius: 3.5
                    color: view.cur && view.cur.path === view.currentPath ? view.cPrimary : "#ff4060"
                    opacity: 0.5 + 0.5 * Math.sin(view.t * 3)
                }
            }
            // the channel strip under the set
            Row {
                anchors.left: parent.left; anchors.leftMargin: 14
                anchors.bottom: parent.bottom
                spacing: 14
                Text {
                    textFormat: Text.PlainText
                    text: !view.cur ? "" : view.cur.section === "theme"
                          ? "THEME " + String(view.sel + 1).padStart(2, "0") + "/" + String(view.themeCount).padStart(2, "0")
                          : "FOLDER " + String(view.sel - view.themeCount + 1).padStart(3, "0") + "/" + String(view.shown.length - view.themeCount).padStart(3, "0")
                    color: view.cPrimary; font.family: view.mono; font.pixelSize: 14; font.bold: true
                }
                Text {
                    textFormat: Text.PlainText
                    text: view.cur ? view.cur.name.toUpperCase() : ""
                    color: view.cText; font.family: view.mono; font.pixelSize: 14; font.bold: true; font.letterSpacing: 2
                }
                Text {
                    textFormat: Text.PlainText
                    visible: !!view.cur && view.cur.path === view.currentPath
                    text: "● ON SCREEN"
                    color: view.cPrimary; font.family: view.mono; font.pixelSize: 13
                }
                Text {
                    textFormat: Text.PlainText
                    text: "look: " + (view.settings.look || "clean")
                    color: view.cText; opacity: 0.5; font.family: view.mono; font.pixelSize: 12
                }
            }
        }
        // the monitor materialising a new picture
        NumberAnimation { id: revealAnim; target: view; property: "reveal"; from: 0; to: 1; duration: 520; easing.type: Easing.OutQuad }

        // ---------------------------------------------------------- readout
        // the highlighted theme: its name and kind, its whole palette, its
        // backgrounds - the palette rows typing in one after another
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
                Text {
                    textFormat: Text.PlainText
                    width: parent.width; elide: Text.ElideMiddle
                    text: "// FRAME :: " + (view.cur ? view.cur.name : "-")
                    color: view.cText; font.family: view.mono; font.pixelSize: 17; font.bold: true
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width; elide: Text.ElideMiddle
                    text: view.cur ? view.cur.dir : ""
                    color: view.cPrimary; opacity: 0.8; font.family: view.mono; font.pixelSize: 11
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width; elide: Text.ElideRight
                    text: !view.cur ? "" : [view.cur.section === "theme" ? "THEME · " + view.themeName.replace(/-/g, " ") : "YOUR FOLDER",
                                            view.palette.w ? view.palette.w + " x " + view.palette.h : "",
                                            view.palette.w ? (view.palette.w / view.palette.h).toFixed(2) + ":1" : "",
                                            view.cur.path === view.currentPath ? "ON SCREEN" : "",
                                            "fit: " + (view.settings.fit || "fill"),
                                            view.desktopLook !== "off" && view.monitorLook !== "clean" ? "desktop: " + view.monitorLook + " (" + view.desktopLook + ")" : ""].filter(x => x).join("  ·  ")
                    color: view.cText; opacity: 0.75; font.family: view.mono; font.pixelSize: 11
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.35) }
                Text { textFormat: Text.PlainText; text: "COLOURS"; color: view.cPrimary; opacity: 0.8; font.family: view.mono; font.pixelSize: 11; font.letterSpacing: 2 }
                // the picture's colours, most common first
                Row {
                    spacing: 4
                    Repeater {
                        model: view.palette.colors || []
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: (readCol.width - 28) / 8; height: 34; radius: 3
                            color: modelData
                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                            opacity: view.paletteShown > index * 4 ? 1 : 0
                        }
                    }
                }
                Grid {
                    columns: 4
                    columnSpacing: 10
                    rowSpacing: 2
                    Repeater {
                        model: view.palette.colors || []
                        delegate: Text {
                            textFormat: Text.PlainText
                            required property string modelData
                            required property int index
                            text: modelData
                            color: view.cText; opacity: view.paletteShown > index * 4 ? 0.7 : 0
                            font.family: view.mono; font.pixelSize: 10
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.35) }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "THEME WALLPAPERS  " + view.themeCount + "   ·   YOUR FOLDER  " + (view.shown.length - view.themeCount)
                          + "\n" + (view.settings.folder || "(no folder set - options)")
                    color: view.cText; opacity: 0.6; font.family: view.mono; font.pixelSize: 10; lineHeight: 1.3
                }
            }
        }
        // the palette typing in, a row at a time
        NumberAnimation { id: paletteReveal; target: view; property: "paletteShown"; from: 0; to: 40; duration: 700 }

        // ------------------------------------------------------ the carousel
        // every theme as a card, laid out in the chosen style (options):
        // arc, line, hand, ring, panorama, triple, grid, pills or blips
        Item {
            id: arc
            anchors.left: parent.left; anchors.right: parent.right
            y: monitor.y + monitor.height + 30
            height: view.height - y - 70
            readonly property string style: view.carouselStyles.indexOf(view.settings.carousel) >= 0 ? view.settings.carousel : "arc"
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
                    readonly property bool themed: modelData.section === "theme"
                    readonly property bool onScreen: modelData.path === view.currentPath
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
                        Image {
                            anchors.fill: parent; anchors.margins: 2
                            source: card.at.vis ? "file://" + encodeURI(card.modelData.path).replace(/#/g, "%23").replace(/\?/g, "%3F") : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(320, 200)
                        }
                        // a pill is a thin slice of the picture, a little dimmed
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 2
                            radius: Math.max(0, card.at.radius - 2)
                            color: Qt.rgba(0, 0, 0, 0.35)
                            opacity: card.at.pill
                            visible: opacity > 0.01
                        }
                        // the theme's own wallpapers carry a bar in the accent
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.margins: 2
                            height: 5
                            visible: card.themed
                            color: view.cPrimary
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 2
                            height: 24
                            visible: card.at.pill < 0.5
                            color: Qt.rgba(0, 0, 0, 0.65)
                            Text {
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                x: 8; width: parent.width - 16; elide: Text.ElideRight
                                text: (card.onScreen ? "● " : "") + (card.themed ? "[T] " : "") + card.modelData.name
                                color: card.isSel ? view.cText : Qt.rgba(view.cText.r, view.cText.g, view.cText.b, 0.75)
                                font.family: view.mono; font.pixelSize: 12; font.bold: card.isSel
                            }
                        }
                    }
                    // the highlighted card's glow
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
                        onClicked: card.isSel ? view.apply(card.modelData) : (view.sel = card.index)
                    }
                }
            }
            // blips: a dot for every theme along the bottom, the highlighted
            // one bright, its card risen above it
            Repeater {
                model: arc.style === "blips" ? view.shown : []
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property real off: index - view.pos
                    readonly property real near: Math.max(0, 1 - Math.abs(off))
                    visible: Math.abs(off) < arc.width / 2 / 22
                    width: 8 + 10 * near; height: width; radius: width / 2
                    x: arc.width / 2 + off * 22 - width / 2
                    y: arc.cardH + 46 - height / 2
                    color: modelData.section === "theme" ? view.cPrimary : view.cText
                    opacity: 0.35 + 0.65 * near
                    border.width: index === view.sel ? 2 : 0
                    border.color: view.cText
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: view.sel = parent.index }
                }
            }
            // blips: the line the card rises from
            Rectangle {
                visible: arc.style === "blips"
                x: arc.width / 2 - 1; y: arc.cardH + 6
                width: 2; height: 40 - 9
                color: view.cPrimary; opacity: 0.6
            }
        }
        // wheel over the arc browses
        WheelHandler {
            onWheel: event => view.step(event.angleDelta.y > 0 || event.angleDelta.x > 0 ? -1 : 1)
        }

        // the options button
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 30
            width: gearText.implicitWidth + 24; height: 32; radius: 4
            color: gearHover.hovered ? Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.15) : "transparent"
            border.width: 1
            border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.6)
            Text { textFormat: Text.PlainText; id: gearText; anchors.centerIn: parent; text: "[ options ]"; color: view.cPrimary; font.family: view.mono; font.pixelSize: 13 }
            HoverHandler { id: gearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: view.settingsOpen = !view.settingsOpen }
        }

        // ------------------------------------------------------------ hints
        Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 26
            text: "[← → / WASD] browse   [T] theme   [F] folder   [R] random   [ENTER] set   [TAB] look   [CTRL+T] crt " + (view.settings.crt ? "off" : "on") + "   [CTRL+,] options   [/] filter   [ESC] " + (view.query ? "clear" : "exit")
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
                "> recalibrating phosphor :: %n%", "> carrier drift 0x%h", "> degauss cycle ok", "> sync lost ... reacquired",
                "> palette checksum 0x%h", "> wake up, operator", "> signal %n% :: holding", "> follow the white rabbit"]
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
                    textFormat: Text.PlainText
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
    property real reveal: 1
    property real paletteShown: 40

    // the glyph atlas for the monitor's glyph / rain looks
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
                    textFormat: Text.PlainText
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
    ShaderEffectSource { id: glyphTex; sourceItem: glyphAtlas; hideSource: true; visible: false }

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
            Text { textFormat: Text.PlainText; id: chipText; anchors.centerIn: parent; text: chip.label; color: chip.on ? view.cPrimary : view.cText; font.family: view.mono; font.pixelSize: 12 }
            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: chip.clicked() }
        }
        component Heading: Text { textFormat: Text.PlainText; color: view.cPrimary; opacity: 0.8; font.family: view.mono; font.pixelSize: 11; font.letterSpacing: 2 }

        ColumnLayout {
            id: optCol
            x: 16; y: 16
            width: parent.width - 32
            spacing: 10
            Text { textFormat: Text.PlainText; text: "> OPTIONS"; color: view.cText; font.family: view.mono; font.pixelSize: 16; font.bold: true }

            Heading { text: "WALLPAPERS FOLDER  ·  after the theme's own" ; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Rectangle {
                Layout.fillWidth: true; height: 30; radius: 3
                color: "transparent"; border.width: 1
                border.color: folderIn.activeFocus ? view.cPrimary : Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.35)
                TextInput {
                    id: folderIn
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    text: view.settings.folder || ""
                    color: view.cText; font.family: view.mono; font.pixelSize: 12
                    selectByMouse: true
                    onAccepted: { view.setSetting("folder", text.trim()); terminal.push("> folder :: " + (text.trim() || "(none)")); view.forceActiveFocus() }
                    Keys.onEscapePressed: { text = view.settings.folder || ""; view.forceActiveFocus() }
                }
            }
            Text {
                textFormat: Text.PlainText
                text: "[ENTER] use it   ·   empty: the theme's wallpapers only"
                color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 10
            }

            Heading { text: "WALLPAPER FIT" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Repeater {
                    model: [["fill", "Fill"], ["fit", "Fit"], ["blur", "Blur fit"], ["stretch", "Stretch"], ["center", "Center"], ["tile", "Tile"]]
                    delegate: Chip {
                        required property var modelData
                        label: modelData[1]
                        on: (view.fitModes.indexOf(view.settings.fit) >= 0 ? view.settings.fit : "fill") === modelData[0]
                        onClicked: view.setSetting("fit", modelData[0])
                    }
                }
            }

            Heading { text: "DESKTOP LOOK  ·  the monitor's look (TAB) on your desktop"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Chip { label: "Off"; on: view.desktopLook === "off"; onClicked: view.setSetting("desktopLook", "off") }
                Chip { label: "Baked"; on: view.desktopLook === "baked"; onClicked: view.setSetting("desktopLook", "baked") }
                Chip { label: "Live"; on: view.desktopLook === "live"; onClicked: view.setSetting("desktopLook", "live") }
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: view.desktopLook === "baked" ? "rendered into the picture when you set it: free, but still"
                    : view.desktopLook === "live" ? "drawn live over the wallpaper, animated (~30 fps for rain); pauses when a window is fullscreen"
                    : "the desktop shows the picture as it is"
                color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 10
            }

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

            Heading { text: "MONITOR  ·  [TAB] cycles"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Repeater {
                    model: ["clean", "grid", "glyph", "rain"]
                    delegate: Chip {
                        required property string modelData
                        label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        on: (view.settings.look || "clean") === modelData
                        onClicked: { view.setSetting("look", modelData); view.reveal = 0; revealAnim.restart() }
                    }
                }
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
            Heading { text: "AFTER APPLYING" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Chip { label: "Stay open"; on: view.settings.afterApply !== "close"; onClicked: view.setSetting("afterApply", "stay") }
                Chip { label: "Glitch out to desktop"; on: view.settings.afterApply === "close"; onClicked: view.setSetting("afterApply", "close") }
            }
            Text { textFormat: Text.PlainText; text: "[ESC] close options"; color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 11 }
        }
    }
}
