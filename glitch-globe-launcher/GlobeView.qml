import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import "eggs.js" as Eggs

// Glitch-Globe-Launcher's scene: a starfield (with traffic), the globe, your apps -
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
    // ~/.config/glitch-globe-launcher/settings.json
    readonly property string settingsPath: Quickshell.env("HOME") + "/.config/glitch-globe-launcher/settings.json"
    property var settings: ({ theme: "matrix", style: "dots", glitch: "normal", autoSpin: true, traffic: true, net: true, netStyle: "streams", nebula: true, crt: false, openGlitch: true, preview: "grid",
                              glitchKinds: ["tear", "blocks", "vhs", "crt", "bleed"],
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
        watchChanges: true                       // edits by hand apply at once
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text())
                view.settings = Object.assign({}, view.settings, s, { custom: Object.assign({}, view.settings.custom, s.custom || {}) })
            } catch (e) {}
        }
    }
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/glitch-globe-launcher"] }

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
    // the globe's looks, in the shader's order
    readonly property var globeStyles: ["dots", "wire", "binary", "code", "holo", "unicron", "dyson", "rain", "hex"]
    // the style drawn: the chosen one, or with "random" a fresh pick (not
    // the last one again) each time it opens
    property string randomStyle: "dots"
    readonly property string activeStyle: settings.style === "random" ? randomStyle
        : globeStyles.indexOf(settings.style) < 0 ? "dots" : settings.style
    function pickRandomStyle() {
        const others = globeStyles.filter(g => g !== randomStyle)
        randomStyle = others[Math.floor(Math.random() * others.length)]
    }
    readonly property string glyphFont: Style.font.menuFamily || mono    // the Omarchy menu's icons

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
    // the Omarchy menu's actions (its default file, then your extension of it,
    // which can override rows): what ">" shows before you type. Rows whose
    // `when` fails here (no laptop, no webcam...) are left out, as in the menu.
    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    property var menuAll: []
    property var menuItems: []
    FileView { id: menuDefault; path: view.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"; printErrors: false; watchChanges: true; onFileChanged: reload(); onLoaded: view.buildMenu() }
    FileView { id: menuUser; path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"; printErrors: false; watchChanges: true; onFileChanged: reload(); onLoaded: view.buildMenu() }
    function parseJsonc(raw) {
        try { return JSON.parse(String(raw || "").replace(/^\s*\/\/[^\n]*(\n|$)/gm, "").replace(/,(\s*[}\]])/g, "$1")) || {} }
        catch (e) { return {} }
    }
    function buildMenu() {
        const all = {}, order = []
        for (const src of [parseJsonc(menuDefault.text()), parseJsonc(menuUser.text())]) {
            const items = src.items && typeof src.items === "object" ? src.items : src
            for (const id in items) {
                const e = items[id]
                if (!e || typeof e !== "object" || Array.isArray(e)) continue
                if (!all[id]) order.push(id)
                all[id] = Object.assign({}, all[id] || {}, e)
            }
        }
        const label = id => (all[id] && all[id].label) || id.split(".").pop()
        const out = []
        for (const id of order) {
            const e = all[id]
            if (id === "apps" || id.startsWith("apps.")) continue       // the globe is for apps already
            // an action, or a submenu filled at runtime (fonts): open it in the menu
            const run = e.action || (e.provider ? "omarchy-menu summon " + id : "")
            if (!run) continue
            const parts = id.split("."), trail = []
            for (let i = 1; i < parts.length; i++) trail.push(label(parts.slice(0, i).join(".")))
            const name = e.label || parts[parts.length - 1], where = trail.join(" › ")
            const aliases = Array.isArray(e.aliases) ? e.aliases.join(" ") : (e.aliases || "")
            out.push({ kind: "menu", id: id, name: name, sub: where, detail: e.description || run, glyph: e.icon || "",
                       icon: "", run: run, when: e.when || "", nameLower: name.toLowerCase(),
                       words: [where, name, e.description || "", e.keywords || "", aliases].join(" ").toLowerCase() })
        }
        menuAll = out
        checkMenu()
    }
    // every `when` at once; prints the indexes of the rows that stay
    function checkMenu() {
        whenChecker.running = false
        whenChecker.command = ["bash", "-c", menuAll.map((m, i) => m.when
            ? "{ " + m.when + "\n} >/dev/null 2>&1 </dev/null && echo " + i + " &" : "echo " + i).join("\n") + "\nwait"]
        whenChecker.running = true
    }
    Process {
        id: whenChecker
        stdout: StdioCollector {
            onStreamFinished: {
                const keep = {}
                for (const l of text.split("\n")) if (l) keep[l] = true
                view.menuItems = view.menuAll.filter((m, i) => keep[i])
            }
        }
    }

    // after ">": the menu's actions; typing searches them and every Omarchy
    // command (menu rows first); once a whole command is typed and a
    // space after it, just that one, with what follows as its arguments
    readonly property var commandNodes: {
        const t = term
        if (!t) return menuItems
        let exact = null
        for (const c of commands) if (t.startsWith(c.base.toLowerCase() + " ") && (!exact || c.base.length > exact.base.length)) exact = c
        if (exact) return [Object.assign({}, exact, { typedArgs: query.slice(1).trim().slice(exact.base.length).trim() })]
        const words = t.split(/\s+/).filter(w => w)
        // best first: the name starts with what's typed, then has every word
        // in it, then the rest (words only in the description)
        const rank = c => {
            const key = c.kind === "menu" ? c.nameLower : c.baseLower
            return (key.startsWith(t) ? 0 : words.every(w => key.includes(w)) ? 1 : 2) * 2 + (c.kind === "menu" ? 0 : 1)
        }
        return menuItems.concat(commands).filter(c => words.every(w => c.words.includes(w)))
            .map(c => ({ c: c, r: rank(c) })).sort((a, b) => a.r - b.r || a.c.name.length - b.c.name.length)
            .map(x => x.c).slice(0, 160)
    }

    // files: an index of your home (fd) when "/" is typed, then fzf picks
    readonly property string fileIndex: Quickshell.env("HOME") + "/.cache/glitch-globe-launcher/files.txt"
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
        if (["stl", "3mf", "obj", "step", "stp"].includes(e)) return "model"
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
        if (mode === "cmd" && menuAll.length) checkMenu()                       // whens can change (recording...)
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
    function turn(x, y, z, a) {
        rot = mul(axisAngle(x, y, z, a), rot)
        // the nebula drifts the way the globe turns (parallax)
        parX -= y * a * 0.05
        parY += x * a * 0.05
    }
    property real parX: 0
    property real parY: 0
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
        if (exploded) {
            const out = []
            for (let i = 0; i < nodes.length; i++) {
                const p = debrisSpot(nodes[i], i)
                out.push({ x: p.x, y: p.y, sx: p.x, sy: p.y, z: p.z })
            }
            proj = out
            const sel = aim >= 0 ? aim : (selected >= 0 && selected < out.length ? selected : 0)
            if (sel !== selected) { selected = sel; selectPulse.restart() }
            return
        }
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
            if (view.doom) {
                view.doomT += dt
                if (view.doom === "countdown") {
                    const amp = 2 + 16 * Math.pow(view.doomT / view.countdownLength, 2)
                    view.shakeX = (Math.random() - 0.5) * amp
                    view.shakeY = (Math.random() - 0.5) * amp * 0.7
                    const left = Math.ceil(view.countdownLength - view.doomT)
                    if (left !== view.doomSaid && left <= 3 && left >= 1) { view.doomSaid = left; terminal.push("> " + left) }
                    if (view.doomT >= view.countdownLength) { view.shakeX = 0; view.shakeY = 0; view.explode() }
                }
            }
            if (view.exploded) {
                view.project()
                return
            }
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
        if (n.kind === "menu") {
            Quickshell.execDetached(alt ? ["omarchy-launch-floating-terminal-with-presentation", n.run] : ["bash", "-lc", n.run])
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
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && query.trim().toLowerCase() === "<namek") { query = ""; selfDestruct() }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) activate(selected, !!(event.modifiers & Qt.ShiftModifier))
        else if (k === Qt.Key_Left) hop(-1, 0)
        else if (k === Qt.Key_Right) hop(1, 0)
        else if (k === Qt.Key_Up) hop(0, -1)
        else if (k === Qt.Key_Down) hop(0, 1)
        else if (k === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier)) settingsOpen = true
        else if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && mode === "file") {
            // the preview's look, round and round (Shift+Tab: backwards)
            const looks = ["clean", "grid", "glyph", "rain"], back = k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
            setSetting("preview", looks[(looks.indexOf(settings.preview) + (back ? 3 : 1)) % 4])
        }
        else if (k === Qt.Key_Backspace) query = query.slice(0, -1)
        else if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) query += event.text
        else return
        event.accepted = true
    }
    // fresh each time it opens
    onActiveChanged: if (active) { burstPeak = 1; doom = ""; doomT = 0; doomChunks = []; doomSaid = 0; if (settings.style === "random") pickRandomStyle(); query = ""; settingsOpen = false; zoom = 1; idle = 0; aimAt(-1); forceActiveFocus() } else described = ""

    // --------------------------------------------------------- the readout
    // linger on something for a few seconds and the corner terminal scans it:
    // an app's description, categories and command; a file's type, size,
    // length, pixels, folder; a command's arguments; a menu row's action
    property string described: ""
    function nodeKey(n) { return n ? n.kind + ":" + (n.path || n.id || n.base || n.name) : "" }
    Timer {
        id: dwell
        interval: 2600
        running: view.active
        onTriggered: view.describe(view.nodes[view.selected])
    }
    onSelectedChanged: dwell.restart()
    function describe(n) {
        const key = nodeKey(n)
        if (!n || key === described) return
        described = key
        const out = ["> scan :: " + (n.kind === "cmd" ? "omarchy " + n.base : n.name)]
        if (n.kind === "app") {
            const e = n.entry
            if (e.comment) out.push("> desc    " + e.comment)
            if (e.genericName) out.push("> kind    " + e.genericName)
            if (e.categories && e.categories.length) out.push("> class   " + e.categories.filter(c => c).join(" / "))
            if (e.execString) out.push("> exec    " + e.execString)
            if (e.id) out.push("> id      " + e.id + (e.runInTerminal ? "  [terminal]" : ""))
            terminal.scrawl(out)
        } else if (n.kind === "file") {
            infoProbe.lead = out
            infoProbe.dir = n.sub
            infoProbe.running = false
            infoProbe.command = ["bash", Qt.resolvedUrl("info.sh").toString().replace(/^file:\/\//, ""), n.path]
            infoProbe.running = true
        } else if (n.kind === "cmd") {
            if (n.sub) out.push("> args    " + n.sub + (n.needsArg ? "  (required)" : ""))
            out.push("> desc    " + n.detail)
            terminal.scrawl(out)
        } else if (n.kind === "menu") {
            if (n.sub) out.push("> path    " + n.sub)
            out.push("> run     " + n.run)
            if (n.detail && n.detail !== n.run) out.push("> desc    " + n.detail)
            terminal.scrawl(out)
        }
    }
    Process {
        id: infoProbe
        property var lead: []
        property string dir: ""
        stdout: StdioCollector {
            onStreamFinished: terminal.scrawl(infoProbe.lead
                .concat(text.split("\n").filter(l => l).map(l => "> " + l))
                .concat(["> dir     " + infoProbe.dir]))
        }
    }

    // ------------------------------------------------------- network traffic
    // bytes in and out per second, summed over the real interfaces, read from
    // /proc/net/dev each second while open; levels 0..1 on a log scale
    // (1 KB/s ~ 0.1, 1 MB/s ~ 0.7, 30 MB/s ~ 1)
    readonly property bool netOn: settings.net !== false
    property real netDown: 0          // bytes/s
    property real netUp: 0
    property real netDownLevel: 0
    property real netUpLevel: 0
    property real netTest: 0          // a level to show regardless (see GlitchGlobeLauncher.open)
    Behavior on netDownLevel { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }
    Behavior on netUpLevel { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }
    property var netLast: null
    function netLevel(bps) { return Math.max(0, Math.min(1, (Math.log10(bps + 1) - 2.5) / 5)) }
    function rate(bps) {
        return bps >= 1048576 ? (bps / 1048576).toFixed(1) + " MB/s" : bps >= 1024 ? Math.round(bps / 1024) + " KB/s" : Math.round(bps) + " B/s"
    }
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: view.active && view.netOn
        onRunningChanged: if (!running) { view.netLast = null; view.netDownLevel = 0; view.netUpLevel = 0 }
        onTriggered: if (!netReader.running) netReader.running = true
    }
    Process {
        id: netReader
        command: ["cat", "/proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rx = 0, tx = 0
                for (const line of text.split("\n").slice(2)) {
                    const m = line.match(/^\s*([^:]+):\s*(.*)$/)
                    if (!m || /^(lo|veth|docker|br-|virbr)/.test(m[1])) continue
                    const f = m[2].trim().split(/\s+/)
                    rx += Number(f[0]) || 0; tx += Number(f[8]) || 0
                }
                const now = Date.now(), last = view.netLast
                if (last) {
                    const dt = Math.max(0.2, (now - last.t) / 1000)
                    view.netDown = Math.max(0, rx - last.rx) / dt
                    view.netUp = Math.max(0, tx - last.tx) / dt
                    view.netDownLevel = view.netLevel(view.netDown)
                    view.netUpLevel = view.netLevel(view.netUp)
                }
                view.netLast = { t: now, rx: rx, tx: tx }
            }
        }
    }

    // ----------------------------------------------------------- <namek
    // the secret: "<namek" + Enter. The globe flares in its theme's opposite
    // colour, pulses ripple off it and the screen shakes harder and harder,
    // then it explodes - a flash, a shockwave - into chunks of itself (in its
    // style), and the apps are flung out into the debris field, still there
    // to pick, until the launcher next opens
    property string doom: ""             // "", "countdown", "boom" (then the field)
    property real doomT: 0               // seconds into the phase
    readonly property real countdownLength: 4.6
    readonly property bool exploded: doom === "boom"
    readonly property color doomColor: Qt.hsla((cPrimary.hslHue + 0.5) % 1, Math.max(0.75, cPrimary.hslSaturation), 0.55, 1)
    readonly property real doomPulse: doom !== "countdown" ? 0
        : Math.pow(0.5 + 0.5 * Math.sin(doomT * (3 + doomT * 2.6)), 3) * Math.min(1, 0.35 + doomT / countdownLength)
    property var doomRot: null           // the globe's turn when it blew
    property var doomChunks: []          // the pieces: where each starts and flies
    property var doomFrom: ({})          // each app's spot when it blew, by name
    readonly property int chunkCount: 18
    property int doomSaid: 0
    function selfDestruct() {
        if (doom) return
        doom = "countdown"
        doomT = 0
        aimAt(-1)
        terminal.scrawl(["> <namek :: command accepted", "> SELF-DESTRUCT SEQUENCE ENGAGED", "> core containment failing"])
    }
    function explode() {
        doomRot = rotation4
        // the chunks: one per seed (the shader's Fibonacci points), starting
        // over their part of the globe and flying outward
        const out = [], R = radius, n = chunkCount, golden = Math.PI * (3 - Math.sqrt(5))
        for (let i = 0; i < n; i++) {
            const y = 1 - 2 * (i + 0.5) / n, r = Math.sqrt(Math.max(0, 1 - y * y)), phi = i * golden
            const q = apply([Math.cos(phi) * r, y, Math.sin(phi) * r])
            const size = R * 1.2
            const px = cx + q[0] * R, py = cy - q[1] * R
            let dx = px - cx, dy = py - cy
            const len = Math.hypot(dx, dy) || 1
            const k = Math.random()
            dx = dx / len + (Math.random() - 0.5) * 0.6; dy = dy / len + (Math.random() - 0.5) * 0.6
            const dist = Math.min(width, height) * (0.25 + 0.3 * Math.random()) * (q[2] < 0 ? 0.7 : 1)
            out.push({ i: i, x0: px - size / 2, y0: py - size / 2, size: size,
                       cx: cx - (px - size / 2), cy: cy - (py - size / 2), R: R,
                       vx: dx * dist, vy: dy * dist, spin: (Math.random() - 0.5) * 2, drift: (Math.random() - 0.5) * 8,
                       k: k * 6.28, back: q[2] < 0 })
        }
        doomChunks = out
        // where each app was when it blew: it flies from there
        const from = {}
        for (let i = 0; i < nodes.length; i++) if (proj[i]) from[nodes[i].name] = { x: proj[i].x, y: proj[i].y }
        doomFrom = from
        const keep = selected
        doom = "boom"
        doomT = 0
        burstPeak = 0.5
        fireGlitch("tear")
        boomFlash.restart()
        boomGlitches.left = 3
        boomGlitches.restart()
        if (keep >= 0) aimAt(keep)
        terminal.scrawl(["> ...", "> planet destroyed. the apps drift on."])
    }
    // the blast scrambling the feed: a quick run of glitch bursts, any kind
    Timer {
        id: boomGlitches
        property int left: 0
        interval: 170 + Math.random() * 160
        repeat: true
        onTriggered: {
            view.fireGlitch(["tear", "blocks"][Math.floor(Math.random() * 2)])
            if (--left <= 0) { stop(); view.burstPeak = 1 }
        }
    }
    // an app's place in the debris field: a stable spot from its name, flown
    // to from where it was, then bobbing
    function nameHash(s, salt) {
        let h = 2166136261 ^ salt
        for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) }
        return ((h >>> 0) % 100000) / 100000
    }
    function debrisSpot(node, i) {
        const name = node.name || String(i)
        const a = nameHash(name, 1) * Math.PI * 2, r = Math.sqrt(0.08 + 0.92 * nameHash(name, 2))
        const tx = width / 2 + Math.cos(a) * r * width * 0.42
        const ty = height * 0.48 + Math.sin(a) * r * height * 0.33
        const from = doomFrom[name] || { x: cx, y: cy }
        const fly = 1 - Math.exp(-doomT * 1.8)
        const k = nameHash(name, 3) * 6.28
        return { x: from.x + (tx - from.x) * fly + Math.sin(driftT * 0.4 + k) * 7,
                 y: from.y + (ty - from.y) * fly + Math.cos(driftT * 0.33 + k) * 5,
                 z: 0.4 + 0.6 * nameHash(name, 4) }
    }

    // ------------------------------------------------------------- the glitches
    property real glitch: 0          // 0..1, the glitch pass's intensity
    property real glitchSeed: 0
    property real shakeX: 0
    property real shakeY: 0
    property real shakeToX: 0        // where this burst jolts to
    property real shakeToY: 0
    readonly property bool glitchesOn: settings.glitch !== "off"
    // the kinds, in the shader's order; each burst is one of the enabled ones
    readonly property var glitchKinds: ["tear", "blocks", "vhs", "crt", "bleed", "invert"]
    property int glitchKind: 0
    property real burstPeak: 1       // the blast's run of bursts is gentler
    property int glitchHold: 180     // ms at full strength
    function fireGlitch(kind) {
        if (kind === undefined) {
            const on = (settings.glitchKinds || glitchKinds).filter(g => glitchKinds.includes(g))
            kind = on.length ? on[Math.floor(Math.random() * on.length)] : "tear"
        }
        glitchKind = Math.max(0, glitchKinds.indexOf(kind))
        // a jolt for the tearing kinds; the picture-wide ones barely move
        const jolt = ["vhs", "crt", "bleed"].includes(kind) ? 0.25 : 1
        glitchHold = kind === "vhs" ? 420 : kind === "crt" ? 120 : kind === "bleed" ? 300 : 180
        glitchSeed = Math.random() * 100
        shakeToX = (Math.random() - 0.5) * 14 * jolt
        shakeToY = (Math.random() - 0.5) * 8 * jolt
        burst.restart()
    }
    // opening: 0 -> 1, the screen glitching over from the desktop to the
    // launcher in one of the enabled kinds (1 when not opening)
    property real opening: 1
    readonly property bool openingWanted: settings.openGlitch !== false
    function pickTransitionKind() {
        const on = (settings.glitchKinds || glitchKinds).filter(g => glitchKinds.includes(g))
        const all = on.length ? on : glitchKinds.slice(0, 5)
        glitchKind = Math.max(0, glitchKinds.indexOf(all[Math.floor(Math.random() * all.length)]))
        glitchSeed = Math.random() * 100
    }
    function playOpening() {
        closeAnim.stop()
        closingFx = false
        pickTransitionKind()
        openAnim.restart()
    }
    // closing: the same, backwards, to see-through (the window shows the
    // live desktop where the launcher has gone); then done() hides it
    property bool closingFx: false
    property var closeDone: null
    function playClosing(done) {
        openAnim.stop()
        pickTransitionKind()
        closeDone = done
        closingFx = true
        closeAnim.restart()
    }
    NumberAnimation {
        id: closeAnim; target: view; property: "opening"; from: 1; to: 0
        duration: view.glitchKind === 3 ? 560 : 440; easing.type: Easing.InOutQuad
        onFinished: { const d = view.closeDone; view.closeDone = null; if (d) d() }
    }
    NumberAnimation {
        id: openAnim; target: view; property: "opening"; from: 0; to: 1
        duration: view.glitchKind === 3 ? 760 : 620; easing.type: Easing.InOutQuad
    }
    Timer {
        id: glitchTimer
        running: view.active && view.glitchesOn && view.doom !== "countdown"
        interval: 4000
        onTriggered: {
            view.fireGlitch()
            if (Math.random() < 0.5) terminal.say()
            interval = (view.settings.glitch === "subtle" ? 14000 : 5000) + Math.random() * (view.settings.glitch === "subtle" ? 16000 : 9000)
            restart()
        }
    }
    SequentialAnimation {
        id: burst
        ParallelAnimation {
            NumberAnimation { target: view; property: "glitch"; from: 0; to: (view.settings.glitch === "subtle" ? 0.45 : 1) * view.burstPeak; duration: 60 }
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

        // the nebula: far gas (half resolution, it's soft), then near dust;
        // each layer shifts its own amount as the globe turns and the mouse
        // moves, so they slide past one another
        readonly property vector2d nebulaShift: Qt.vector2d(
            view.parX + (sceneHover.point.position.x / Math.max(1, width) - 0.5) * 0.035,
            view.parY + (sceneHover.point.position.y / Math.max(1, height) - 0.5) * 0.025)
        HoverHandler { id: sceneHover }
        Item {
            width: parent.width / 2
            height: parent.height / 2
            scale: 2
            transformOrigin: Item.TopLeft
            visible: view.settings.nebula !== false
            ShaderEffect {
                anchors.fill: parent
                property real time: view.driftT
                property vector2d resolution: Qt.vector2d(width, height)
                property vector2d shift: scene.nebulaShift
                property color tintA: view.cGlow
                property color tintB: view.cPrimary
                property color dark: view.cBg
                property real mode: 0
                fragmentShader: Qt.resolvedUrl("shaders/nebula.frag.qsb")
            }
        }
        ShaderEffect {
            anchors.fill: parent
            visible: view.settings.nebula !== false
            property real time: view.driftT
            property vector2d resolution: Qt.vector2d(width, height)
            property vector2d shift: scene.nebulaShift
            property color tintA: view.cGlow
            property color tintB: view.cPrimary
            property color dark: view.cBg
            property real mode: 1
            fragmentShader: Qt.resolvedUrl("shaders/nebula.frag.qsb")
        }

        // shooting stars, comets and spacecraft, behind the globe
        SpaceTraffic {
            anchors.fill: parent
            running: view.active && view.settings.traffic !== false
            visible: view.settings.traffic !== false
            primary: view.cPrimary
            dark: view.cBg
        }

        // network traffic: packets streaming in to the globe (down) and out
        // (up) - or, as orbits, rings round it, drawn over the globe (their
        // far halves come dimmed) but under the apps
        ShaderEffect {
            anchors.fill: parent
            z: view.settings.netStyle === "orbits" ? 5 : 0
            property real mode: view.settings.netStyle === "orbits" ? 1 : 0
            visible: view.netOn
            property real time: view.driftT
            property vector2d resolution: Qt.vector2d(width, height)
            property vector2d center: Qt.vector2d(view.cx, view.cy)
            property real radius: view.radius
            property real down: Math.max(view.netDownLevel, view.netTest)
            property real up: Math.max(view.netUpLevel, view.netTest * 0.6)
            property color inColor: view.cPrimary
            property color outColor: view.cGlow
            property var glyphs: globeGlyphTex
            property real glyphCount: globeGlyphs.count
            fragmentShader: Qt.resolvedUrl("shaders/traffic.frag.qsb")
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
            property real style: Math.max(0, view.globeStyles.indexOf(view.activeStyle))
            property real pulse: view.pulse
            property var land: landMap
            property var glyphs: globeGlyphTex
            property real glyphCount: globeGlyphs.count
            property color doomColor: view.doomColor
            property real doomPulse: view.doomPulse
            property real chunk: -1
            property real chunkCount: view.chunkCount
            visible: !view.exploded
            fragmentShader: Qt.resolvedUrl("shaders/globe.frag.qsb")
        }

        // <namek: pulses rippling off the globe during the countdown
        Repeater {
            model: view.doom === "countdown" ? 3 : 0
            delegate: Rectangle {
                required property int index
                readonly property real ph: (view.doomT * (0.7 + view.doomT * 0.35) + index / 3) % 1
                width: view.radius * 2 * (1 + ph * 0.9); height: width; radius: width / 2
                x: view.cx - width / 2; y: view.cy - height / 2
                color: "transparent"
                border.width: 3 + 10 * (1 - ph)
                border.color: view.doomColor
                opacity: (1 - ph) * 0.8
            }
        }
        // the globe in pieces, each drawn by the globe shader as its own chunk
        Repeater {
            model: view.exploded ? view.doomChunks : []
            delegate: Item {
                id: piece
                required property var modelData
                readonly property real fly: 1 - Math.exp(-view.doomT * 1.5)
                x: modelData.x0 + modelData.vx * fly + Math.sin(view.driftT * 0.3 + modelData.k) * 6
                y: modelData.y0 + modelData.vy * fly + Math.cos(view.driftT * 0.27 + modelData.k) * 5
                width: modelData.size; height: modelData.size
                rotation: modelData.spin * fly * 70 + view.doomT * modelData.drift
                scale: 1 - 0.45 * fly                // receding into the field
                opacity: modelData.back ? 0.75 : 1
                ShaderEffect {
                    anchors.fill: parent
                    property real time: view.driftT
                    property vector2d resolution: Qt.vector2d(width, height)
                    property vector2d center: Qt.vector2d(piece.modelData.cx, piece.modelData.cy)
                    property real radius: piece.modelData.R
                    property matrix4x4 rotation: view.doomRot || view.rotation4
                    property color dotColor: view.cPrimary
                    property color glowColor: view.cGlow
                    property real rings: 34
                    property real style: Math.max(0, view.globeStyles.indexOf(view.activeStyle))
                    property real pulse: 0
                    property var land: landMap
                    property var glyphs: globeGlyphTex
                    property real glyphCount: globeGlyphs.count
                    property color doomColor: view.doomColor
                    property real doomPulse: 0
                    property real chunk: piece.modelData.i
                    property real chunkCount: view.chunkCount
                    fragmentShader: Qt.resolvedUrl("shaders/globe.frag.qsb")
                }
            }
        }
        // the debris field's particles: shards, dust, embers, sparks
        ShaderEffect {
            anchors.fill: parent
            visible: view.exploded
            property real time: view.driftT
            property vector2d resolution: Qt.vector2d(width, height)
            property vector2d center: Qt.vector2d(view.width / 2, view.height * 0.47)
            property real age: view.doomT
            property color metal: Qt.rgba(0.32, 0.34, 0.46, 1)
            property color ember: view.doomColor
            property color glow: view.cPrimary
            fragmentShader: Qt.resolvedUrl("shaders/debris.frag.qsb")
        }
        // the blast: a shockwave ring racing out, and a flash over everything
        Rectangle {
            visible: view.exploded && view.doomT < 1.6
            readonly property real k: Math.min(1, view.doomT / 1.4)
            width: view.radius * 2 * (0.6 + k * 5); height: width; radius: width / 2
            x: view.width / 2 - width / 2; y: view.height * 0.47 - height / 2
            color: "transparent"
            border.width: 40 * (1 - k) + 2
            border.color: view.doomColor
            opacity: 1 - k
        }
        Rectangle {
            id: flash
            anchors.fill: parent
            z: 40
            color: Qt.lighter(view.doomColor, 1.6)
            opacity: 0
            NumberAnimation on opacity { id: boomFlash; running: false; from: 1; to: 0; duration: 900; easing.type: Easing.OutCubic }
        }
        // what the earth styles are drawn from: the land (Natural Earth, public
        // domain), and a row of glyphs - 0 and 1 first, for the binary skin
        Image { id: landMap; source: "land.png"; visible: false; smooth: true }
        Item {
            id: globeGlyphAtlas
            width: globeGlyphs.count * 16
            height: 26
            Rectangle { anchors.fill: parent; color: "black" }
            Row {
                Repeater {
                    id: globeGlyphs
                    model: "01ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎ23456789:=+*<>Z".split("")
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
                        font.bold: true
                    }
                }
            }
        }
        ShaderEffectSource { id: globeGlyphTex; sourceItem: globeGlyphAtlas; hideSource: true; visible: false; smooth: true }

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
                        visible: !node.modelData.glyph
                        source: node.modelData.glyph ? "" : Quickshell.iconPath(node.modelData.icon || "", "application-x-executable")
                        asynchronous: true
                    }
                    // the Omarchy menu's rows have a Nerd Font glyph instead
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !!node.modelData.glyph
                        text: node.modelData.glyph || ""
                        color: view.cPrimary
                        font.family: view.glyphFont
                        font.pixelSize: parent.width * 0.62
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
                        Text { textFormat: Text.PlainText; text: ">"; color: view.cPrimary; font.family: view.mono; font.pixelSize: 16; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { textFormat: Text.PlainText; text: node.modelData.name || ""; color: view.cText; font.family: view.mono; font.pixelSize: 15; font.bold: true }
                            Text { textFormat: Text.PlainText; visible: text !== ""; text: node.modelData.sub || ""; color: view.cPrimary; opacity: 0.75; font.family: view.mono; font.pixelSize: 11 }
                        }
                    }
                }
            }
        }

        // after "/": the selected file, previewed beside the globe (when there's room)
        FilePreview {
            z: 30                                   // over the globe's apps and orbits
            readonly property real room: parent.width / 2 - view.radius * view.lift - 130
            anchors.right: parent.right
            anchors.rightMargin: 40
            y: 120
            width: Math.min(680, room)
            height: parent.height - y - 60
            visible: opacity > 0
            active: view.active && view.mode === "file" && room >= 320
            file: view.mode === "file" ? (view.nodes[view.selected] || null) : null
            look: view.settings.preview || "grid"
            time: view.driftT
            primary: view.cPrimary
            glow: view.cGlow
            bg: view.cBg
            fg: view.cText
            mono: view.mono
        }

        // ------------------------------------------------------------- the HUD
        // top: what you're searching for
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 46
            spacing: 6
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: "// GLOBE-LAUNCHER  ·  " + view.nodes.length + (view.mode === "cmd" ? (view.term ? " OMARCHY ACTIONS + COMMANDS" : " OMARCHY MENU ACTIONS") : view.mode === "file" ? " FILES" : " APPS")
                      + (view.term ? "  ·  FILTER ACTIVE" : "")
                color: view.cPrimary; opacity: 0.7
                font.family: view.mono; font.pixelSize: 13; font.letterSpacing: 2
            }
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: (!view.query ? "> type to search   ·   > commands   ·   / files"
                       : view.mode === "app" ? "> " + view.query : view.query) + (cursorBlink.on ? "_" : " ")
                color: view.query ? view.cText : Qt.rgba(view.cText.r, view.cText.g, view.cText.b, 0.45)
                font.family: view.mono; font.pixelSize: 22
                Timer { id: cursorBlink; property bool on: true; interval: 530; repeat: true; running: view.active; onTriggered: on = !on }
            }
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: view.netOn && view.netLast !== null
                text: "▼ " + view.rate(view.netDown) + "   ▲ " + view.rate(view.netUp)
                color: view.cPrimary; opacity: 0.55
                font.family: view.mono; font.pixelSize: 11; font.letterSpacing: 1
            }
        }

        // bottom: the selected app, big
        Rectangle {
            id: card
            z: 30
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
                Item {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    IconImage {
                        anchors.fill: parent
                        visible: !!card.app && !card.app.glyph
                        source: card.app && !card.app.glyph ? Quickshell.iconPath(card.app.icon || "", "application-x-executable") : ""
                    }
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !!card.app && !!card.app.glyph
                        text: card.app ? (card.app.glyph || "") : ""
                        color: view.cPrimary
                        font.family: view.glyphFont
                        font.pixelSize: 40
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: !card.app ? "" : card.app.kind === "cmd" ? "omarchy " + card.app.base + " " + (card.app.typedArgs || card.app.sub)
                            : card.app.kind === "menu" ? ((card.app.sub ? card.app.sub + " › " : "") + card.app.name).toUpperCase()
                            : (card.app.name || "").toUpperCase()
                        color: view.cText; font.family: view.mono; font.pixelSize: 20; font.bold: true; font.letterSpacing: 1.5
                    }
                    Text { textFormat: Text.PlainText; Layout.fillWidth: true; elide: Text.ElideMiddle; visible: text !== ""; text: card.app ? (card.app.detail || "") : ""; color: view.cPrimary; opacity: 0.85; font.family: view.mono; font.pixelSize: 13 }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: !card.app ? ""
                            : card.app.kind === "file" ? "[ENTER] open   [SHIFT+ENTER] open its folder   [← → ↑ ↓] hop   [ESC] back"
                            : card.app.kind === "menu" ? "[ENTER] run   [SHIFT+ENTER] run in a terminal   [← → ↑ ↓] hop   [type] search all commands   [ESC] back"
                            : card.app.kind === "cmd" ? (card.app.needsArg && !card.app.typedArgs ? "[ENTER] type its arguments: " + card.app.sub + "   [ESC] back"
                                                         : "[ENTER] run   [SHIFT+ENTER] run in a terminal   [← → ↑ ↓] hop   [ESC] back")
                            : "[ENTER] launch   [← → ↑ ↓] hop   [drag] spin   [type] search   [>] commands   [/] files   [CTRL+,] options   [ESC] exit"
                        color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 11
                    }
                }
            }
        }
        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: view.nodes.length === 0
            text: view.mode === "cmd" ? (!view.term ? "> reading the omarchy menu..." : view.commands.length === 0 ? "> reading omarchy commands..." : "> no command matches \"" + view.term + "\"")
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
            // lines as a model, so only a new line types itself out
            ListModel { id: termLines }
            property var queue: []               // lines waiting their turn
            function push(text) {
                termLines.append({ line: text.length > 74 ? text.slice(0, 73) + "…" : text })
                while (termLines.count > 10) termLines.remove(0)
            }
            function scrawl(list) { queue = queue.concat(list) }
            Timer {
                interval: 240; repeat: true
                running: terminal.queue.length > 0
                onTriggered: { terminal.push(terminal.queue[0]); terminal.queue = terminal.queue.slice(1) }
            }
            readonly property var phrases: [
                "> handshake ok :: node %h", "> tracing route //apps/%n", "> sync shard 0x%h ... ok",
                "> signal drift detected, recalibrating", "> uplink %n%% :: carrier stable", "> decrypting index 0x%h",
                "> wake up, operator", "> follow the white rabbit", "> mapping %n nodes to the sphere", "> packet loss 0.%n%"]
            function say() {
                if (queue.length) return
                // now and then, an easter egg instead (eggs.js)
                const egg = Eggs.maybe(0.3)
                if (egg) { push(egg); return }                 // don't talk over a readout
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

        // options button
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 30
            width: gearText.implicitWidth + 24; height: 32; radius: 4
            color: gearHover.hovered ? Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.15) : "transparent"
            border.width: 1
            border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.5)
            Text { textFormat: Text.PlainText; id: gearText; anchors.centerIn: parent; text: "[ options ]"; color: view.cPrimary; font.family: view.mono; font.pixelSize: 13 }
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
        property real kind: view.glitchKind
        property real trans: view.opening
        property real crt: view.settings.crt ? 1 : 0
        property real closing: view.closingFx ? 1 : 0
        // <namek: the shockwave, bending the feed (matches the ring drawn in the scene)
        readonly property real shockK: Math.min(1, view.doomT / 1.4)
        property vector2d shockCenter: Qt.vector2d(view.width / 2, view.height * 0.47)
        property real shockR: view.radius * (0.6 + shockK * 5)
        property real shockAmt: view.exploded && view.doomT < 1.6 ? 1 - shockK : 0
        property var desk: deskTex
        fragmentShader: Qt.resolvedUrl("shaders/glitch.frag.qsb")
    }
    // the desktop as it was when the launcher opened (GlitchGlobeLauncher captures
    // it), for the opening transition
    property var deskItem: null
    ShaderEffectSource { id: deskTex; sourceItem: view.deskItem; hideSource: true; live: true; visible: false }

    // --------------------------------------------------------------- options
    property bool settingsOpen: false
    Rectangle {
        id: options
        visible: view.settingsOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 72
        anchors.rightMargin: 30
        width: 400
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
            Text { textFormat: Text.PlainText; id: chipText; anchors.centerIn: parent; text: chip.label; color: chip.on ? view.cPrimary : view.cText; font.family: view.mono; font.pixelSize: 12 }
            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: chip.clicked() }
        }
        component Heading: Text { textFormat: Text.PlainText; color: view.cPrimary; opacity: 0.8; font.family: view.mono; font.pixelSize: 11; font.letterSpacing: 2 }
        component HexField: RowLayout {
            id: hf
            property string label: ""
            property string key: ""
            spacing: 8
            Text { textFormat: Text.PlainText; text: hf.label; color: view.cText; font.family: view.mono; font.pixelSize: 12; Layout.preferredWidth: 90 }
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
            Text { textFormat: Text.PlainText; text: "> OPTIONS"; color: view.cText; font.family: view.mono; font.pixelSize: 16; font.bold: true }

            Heading { text: "COLOURS" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
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
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Repeater {
                    model: [["dots", "Dots"], ["wire", "Wireframe"], ["binary", "Binary"], ["code", "Code Earth"], ["holo", "Holo Earth"],
                            ["unicron", "Unicron"], ["dyson", "Dyson Sphere"], ["rain", "Matrix Rain"], ["hex", "Bestagon"], ["random", "Random"]]
                    delegate: Chip {
                        required property var modelData
                        label: modelData[1]
                        on: (view.settings.style === "random" || view.globeStyles.indexOf(view.settings.style) >= 0 ? view.settings.style : "dots") === modelData[0]
                        onClicked: view.setSetting("style", modelData[0])
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Chip { label: "Auto-spin"; on: view.settings.autoSpin; onClicked: view.setSetting("autoSpin", !view.settings.autoSpin) }
                Chip { label: "Space traffic"; on: view.settings.traffic !== false; onClicked: view.setSetting("traffic", view.settings.traffic === false) }
                Chip { label: "CRT monitor"; on: view.settings.crt === true; onClicked: view.setSetting("crt", view.settings.crt !== true) }
                Chip { label: "Nebula"; on: view.settings.nebula !== false; onClicked: view.setSetting("nebula", view.settings.nebula === false) }
            }

            Heading { text: "NETWORK TRAFFIC" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Chip { label: "Off"; on: view.settings.net === false; onClicked: view.setSetting("net", false) }
                Chip {
                    label: "Particles"
                    on: view.settings.net !== false && view.settings.netStyle !== "orbits"
                    onClicked: { view.setSetting("net", true); view.setSetting("netStyle", "streams") }
                }
                Chip {
                    label: "Orbits"
                    on: view.settings.net !== false && view.settings.netStyle === "orbits"
                    onClicked: { view.setSetting("net", true); view.setSetting("netStyle", "orbits") }
                }
            }

            Heading { text: "FILE PREVIEW  ·  [TAB] cycles"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Repeater {
                    model: ["clean", "grid", "glyph", "rain"]
                    delegate: Chip {
                        required property string modelData
                        label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        on: (view.settings.preview || "grid") === modelData
                        onClicked: view.setSetting("preview", modelData)
                    }
                }
            }

            Heading { text: "GLITCHES" }
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                Chip { label: "Normal"; on: view.settings.glitch === "normal"; onClicked: view.setSetting("glitch", "normal") }
                Chip { label: "Subtle"; on: view.settings.glitch === "subtle"; onClicked: view.setSetting("glitch", "subtle") }
                Chip { label: "Off"; on: view.settings.glitch === "off"; onClicked: view.setSetting("glitch", "off") }
                Chip { label: "Open/close glitch"; on: view.settings.openGlitch !== false; onClicked: view.setSetting("openGlitch", view.settings.openGlitch === false) }
            }
            // which kinds: click one to switch it on (and see it) or off
            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: optCol.width
                spacing: 6
                visible: view.glitchesOn
                Repeater {
                    model: [["tear", "Tear"], ["blocks", "Blocks"], ["vhs", "VHS"], ["crt", "CRT"], ["bleed", "Code bleed"], ["invert", "Invert"]]
                    delegate: Chip {
                        required property var modelData
                        readonly property var kinds: view.settings.glitchKinds || view.glitchKinds
                        label: modelData[1]
                        on: kinds.includes(modelData[0])
                        onClicked: {
                            const k = modelData[0], was = on
                            view.setSetting("glitchKinds", was ? kinds.filter(x => x !== k) : kinds.concat([k]))
                            if (!was) view.fireGlitch(k)
                        }
                    }
                }
            }
            Text { textFormat: Text.PlainText; text: "[ESC] close options"; color: view.cText; opacity: 0.45; font.family: view.mono; font.pixelSize: 11 }
        }
    }
}
