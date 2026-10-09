import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons

// Matrix-Theme-Select's scene: every Omarchy theme on a cover-flow arc under
// an old CRT monitor showing the highlighted one's preview, its full palette
// and backgrounds read out beside it, over a starfield and a nebula tinted
// by the theme. Arrows browse, typing filters, Enter applies (it stays
// open), Tab changes the monitor's look, Ctrl+T switches the CRT off / on.
// The screen glitches now and then, a little as you browse, hard when a
// theme is applied - and on the way in and out.
FocusScope {
    id: view

    property bool active: false
    property var closeRequest: null
    property var deskItem: null                // the desktop, captured as it opened

    // ---------------------------------------------------------------- settings
    // ~/.config/matrix-theme-select/settings.json
    readonly property string settingsPath: Quickshell.env("HOME") + "/.config/matrix-theme-select/settings.json"
    property var settings: ({ crt: true, look: "clean" })
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
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/matrix-theme-select"] }

    // the UI's colours: the highlighted theme's own (matrix green until the
    // themes are read), easing across as you browse - text, borders, panels,
    // the sky, the glitches, all of it
    property color cPrimary: tAccent
    property color cGlow: tSecond
    property color cBg: colorOf(cur, "background", "dark_background") || "#010603"
    property color cText: colorOf(cur, "foreground", "bright_foreground", "light_foreground") || "#c9ffdc"
    Behavior on cPrimary { ColorAnimation { duration: 450 } }
    Behavior on cGlow { ColorAnimation { duration: 450 } }
    Behavior on cBg { ColorAnimation { duration: 450 } }
    Behavior on cText { ColorAnimation { duration: 450 } }
    readonly property string mono: Style.font.family || "monospace"

    // ---------------------------------------------------------------- themes
    // themes.py: [{slug, name, mode, preview, backgrounds, colors: [[key, hex]], current, user}]
    property var themes: []
    Process {
        id: themeReader
        command: ["python3", Qt.resolvedUrl("themes.py").toString().replace(/^file:\/\//, "")]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = []
                try { list = JSON.parse(text) } catch (e) {}
                // on opening, land on the running theme; after an apply, stay put
                const keep = view.landOnCurrent ? "" : (view.cur ? view.cur.slug : "")
                view.landOnCurrent = false
                view.themes = list
                // land on the same theme again, or else the active one
                let i = keep ? view.shown.findIndex(t => t.slug === keep) : -1
                if (i < 0) i = view.shown.findIndex(t => t.current)
                if (i >= 0 && !keep) { view.sel = i; view.pos = i }
                else if (i >= 0) view.sel = i
            }
        }
    }
    property bool landOnCurrent: true
    property string query: ""
    readonly property var shown: {
        const q = query.trim().toLowerCase()
        return q ? themes.filter(t => (t.name + " " + t.slug + " " + t.mode).toLowerCase().includes(q)) : themes
    }
    property int sel: 0
    property real pos: 0                       // the arc's position, easing after sel
    readonly property var cur: shown[Math.max(0, Math.min(sel, shown.length - 1))] || null
    readonly property var activeTheme: themes.find(t => t.current) || null
    onShownChanged: if (sel >= shown.length) sel = Math.max(0, shown.length - 1)

    function colorOf(t, ...keys) {
        if (!t) return ""
        for (const k of keys) {
            const c = t.colors.find(p => p[0] === k)
            if (c) return c[1]
        }
        return ""
    }
    // the highlighted theme's colours, for the sky and the monitor's glow
    readonly property color tAccent: colorOf(cur, "accent", "blue", "cyan", "foreground") || "#3dff8a"
    readonly property color tSecond: colorOf(cur, "magenta", "bright_magenta", "cyan", "accent") || "#11c46a"
    readonly property color tBack: colorOf(cur, "darker_background", "dark_background", "background") || "#010603"
    property color skyA: cPrimary
    property color skyB: cGlow

    function step(d) {
        if (!shown.length) return
        sel = ((sel + d) % shown.length + shown.length) % shown.length
    }
    // browsing: a small glitch, of any of the lighter kinds
    onSelChanged: {
        fireGlitch(["tear", "tear", "blocks", "vhs", "bleed"][Math.floor(Math.random() * 5)], 0.18 + Math.random() * 0.17)
        revealAnim.restart(); paletteReveal.restart()
    }

    // apply: `omarchy theme set`, a hard glitch, and stay open
    Process {
        id: applier
        onExited: (code) => {
            terminal.push(code === 0 ? "> theme applied :: " + applier.name : "> theme failed (" + code + ") :: " + applier.name)
            themeReader.running = true                       // the active one has changed
        }
        property string name: ""
    }
    function apply(t) {
        if (!t) return
        if (t.current) { terminal.push("> already running :: " + t.name); fireGlitch("tear", 0.4); return }
        if (applier.running) return
        applier.name = t.name
        applier.command = ["omarchy-theme-set", t.name]
        applier.running = true
        fireGlitch(["blocks", "vhs", "crt", "bleed", "tear"][Math.floor(Math.random() * 5)], 1)
        stutter.left = 2; stutter.restart()                      // and it keeps fighting it
        terminal.scrawl(["> rewriting palette :: " + t.slug, "> pushing to the shell, terminals, editors..."])
    }

    // ------------------------------------------------------------------ time
    property real t: 0
    FrameAnimation {
        running: view.active && view.visible
        onTriggered: {
            const dt = Math.min(frameTime, 0.05)
            view.t += dt
            view.pos += (view.sel - view.pos) * Math.min(1, dt * 9)
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
        running: view.active
        interval: 5000
        onTriggered: {
            const r = Math.random()
            if (r < 0.15) {
                revealAnim.restart()                             // signal lost ... reacquired
                terminal.push("> sync lost ... reacquired")
                view.fireGlitch("tear", 0.3)
            } else {
                view.fireGlitch(view.randomKind(), 0.35 + Math.random() * 0.65)
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
            view.fireGlitch(view.randomKind() === "invert" ? "tear" : view.randomKind(), 0.3 + Math.random() * 0.5)
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
        landOnCurrent = true
        themeReader.running = true
        forceActiveFocus()
        terminal.scrawl(["> link established :: theme registry", "> " + (themes.length || "scanning") + " palettes on file"])
    }

    // -------------------------------------------------------------- keyboard
    Keys.onPressed: event => {
        const k = event.key, ctrl = event.modifiers & Qt.ControlModifier
        if (k === Qt.Key_Escape) { if (query) query = ""; else if (closeRequest) closeRequest() }
        else if (k === Qt.Key_Left || k === Qt.Key_Up) step(-1)
        else if (k === Qt.Key_Right || k === Qt.Key_Down) step(1)
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
        else if (k === Qt.Key_T && ctrl) { setSetting("crt", !settings.crt); fireGlitch("crt", 0.8) }
        else if (k === Qt.Key_Backspace) { query = query.slice(0, -1); sel = 0; pos = 0 }
        else if (event.text && event.text.length === 1 && event.text >= " " && !ctrl) { query += event.text; sel = 0; pos = 0 }
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
                anchors.horizontalCenter: parent.horizontalCenter
                text: "// MATRIX-THEME-SELECT  ·  " + view.shown.length + " THEMES"
                      + (view.activeTheme ? "  ·  RUNNING: " + view.activeTheme.name.toUpperCase() : "")
                      + (view.query ? "  ·  FILTER ACTIVE" : "")
                color: view.cPrimary; opacity: 0.7
                font.family: view.mono; font.pixelSize: 13; font.letterSpacing: 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (view.query ? "> " + view.query : "> type to filter") + (cursorBlink.on ? "_" : " ")
                color: view.query ? view.cText : Qt.rgba(view.cText.r, view.cText.g, view.cText.b, 0.45)
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
                        Image {
                            id: shot
                            anchors.fill: parent
                            visible: view.cur && view.cur.preview !== ""
                            source: view.cur && view.cur.preview ? "file://" + encodeURI(view.cur.preview).replace(/#/g, "%23") : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(1400, 800)
                        }
                        // no preview: the palette as colour bars
                        Row {
                            anchors.fill: parent
                            visible: !shot.visible && !!view.cur
                            Repeater {
                                model: view.cur ? view.cur.colors.slice(0, 16) : []
                                delegate: Rectangle {
                                    required property var modelData
                                    width: screenContent.width / Math.max(1, Math.min(16, view.cur ? view.cur.colors.length : 1))
                                    height: screenContent.height
                                    color: modelData[1]
                                }
                            }
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
                        anchors.centerIn: parent
                        visible: !view.cur
                        text: view.themes.length ? "> NO SIGNAL :: nothing matches \"" + view.query + "\"" : "> NO SIGNAL"
                        color: view.cPrimary; font.family: view.mono; font.pixelSize: 20
                    }
                }
                // a power light
                Rectangle {
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 9
                    width: 7; height: 7; radius: 3.5
                    color: view.cur && view.cur.current ? view.cPrimary : "#ff4060"
                    opacity: 0.5 + 0.5 * Math.sin(view.t * 3)
                }
            }
            // the channel strip under the set
            Row {
                anchors.left: parent.left; anchors.leftMargin: 14
                anchors.bottom: parent.bottom
                spacing: 14
                Text {
                    text: "CH " + String(view.sel + 1).padStart(2, "0") + "/" + String(view.shown.length).padStart(2, "0")
                    color: view.cPrimary; font.family: view.mono; font.pixelSize: 14; font.bold: true
                }
                Text {
                    text: view.cur ? view.cur.name.toUpperCase() : ""
                    color: view.cText; font.family: view.mono; font.pixelSize: 14; font.bold: true; font.letterSpacing: 2
                }
                Text {
                    visible: !!view.cur && view.cur.current
                    text: "● RUNNING"
                    color: view.cPrimary; font.family: view.mono; font.pixelSize: 13
                }
                Text {
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
                    width: parent.width; elide: Text.ElideRight
                    text: "// THEME :: " + (view.cur ? view.cur.name : "-")
                    color: view.cText; font.family: view.mono; font.pixelSize: 17; font.bold: true
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: !view.cur ? "" : [view.cur.slug, view.cur.mode, view.cur.user ? "installed" : "stock",
                                            view.cur.colors.length + " colours", view.cur.current ? "RUNNING" : ""].filter(s => s).join("  ·  ")
                    color: view.cPrimary; opacity: 0.8; font.family: view.mono; font.pixelSize: 11
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.35) }
                Text { text: "PALETTE"; color: view.cPrimary; opacity: 0.8; font.family: view.mono; font.pixelSize: 11; font.letterSpacing: 2 }
                Grid {
                    columns: 2
                    columnSpacing: 14
                    rowSpacing: 5
                    Repeater {
                        model: view.cur ? view.cur.colors : []
                        delegate: Row {
                            required property var modelData
                            required property int index
                            spacing: 8
                            width: (readCol.width - 14) / 2
                            opacity: view.paletteShown > index ? 1 : 0
                            Rectangle {
                                width: 20; height: 20; radius: 3
                                color: modelData[1]
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.18)
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: modelData[0]; color: view.cText; font.family: view.mono; font.pixelSize: 10; elide: Text.ElideRight; width: (readCol.width - 14) / 2 - 30 }
                                Text { text: modelData[1]; color: view.cPrimary; opacity: 0.7; font.family: view.mono; font.pixelSize: 10 }
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.35); visible: bgRow.count > 0 }
                Text {
                    visible: bgRow.count > 0
                    text: "BACKGROUNDS  ·  " + (view.cur ? view.cur.backgrounds.length : 0) + (view.cur && view.cur.backgrounds.length >= 6 ? "+" : "")
                    color: view.cPrimary; opacity: 0.8; font.family: view.mono; font.pixelSize: 11; font.letterSpacing: 2
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        id: bgRow
                        model: view.cur ? view.cur.backgrounds.slice(0, 6) : []
                        delegate: Rectangle {
                            required property string modelData
                            width: (readCol.width - 12) / 3; height: width * 9 / 16
                            radius: 3
                            color: "black"
                            border.width: 1
                            border.color: Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.4)
                            clip: true
                            Image {
                                anchors.fill: parent; anchors.margins: 1
                                source: "file://" + encodeURI(modelData).replace(/#/g, "%23")
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(240, 135)
                            }
                        }
                    }
                }
            }
        }
        // the palette typing in, a row at a time
        NumberAnimation { id: paletteReveal; target: view; property: "paletteShown"; from: 0; to: 40; duration: 700 }

        // ---------------------------------------------------------- the arc
        // every theme as a card on a cover-flow arc: the highlighted one big
        // in front, its neighbours turning away to either side
        Item {
            id: arc
            anchors.left: parent.left; anchors.right: parent.right
            y: monitor.y + monitor.height + 30
            height: view.height - y - 70
            Repeater {
                model: view.shown
                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property real off: index - view.pos
                    readonly property real th: off * 0.3
                    readonly property bool near: Math.abs(off) < 9
                    readonly property real depth: Math.cos(Math.max(-1.55, Math.min(1.55, th)))
                    readonly property bool isSel: index === view.sel
                    visible: near && depth > 0.05
                    width: Math.min(360, arc.height * 1.2)
                    height: width * 0.62
                    x: arc.width / 2 + Math.sin(th) * arc.width * 0.44 - width / 2
                    y: 10 + (1 - depth) * 40
                    z: depth * 100
                    scale: 0.45 + 0.55 * depth
                    opacity: 0.25 + 0.75 * depth
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: "black"
                        border.width: card.isSel ? 2 : 1
                        border.color: card.isSel ? view.cPrimary : Qt.rgba(view.cPrimary.r, view.cPrimary.g, view.cPrimary.b, 0.45)
                        clip: true
                        Image {
                            anchors.fill: parent; anchors.margins: 2
                            source: card.near && card.modelData.preview ? "file://" + encodeURI(card.modelData.preview).replace(/#/g, "%23") : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(320, 200)
                        }
                        // its palette, a strip along the bottom
                        Row {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.margins: 2
                            height: 8
                            Repeater {
                                model: card.modelData.colors.slice(0, 12)
                                delegate: Rectangle {
                                    required property var modelData
                                    width: (card.width - 4) / Math.max(1, Math.min(12, card.modelData.colors.length))
                                    height: 8
                                    color: modelData[1]
                                }
                            }
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 2
                            height: 24
                            color: Qt.rgba(0, 0, 0, 0.65)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 8; width: parent.width - 16; elide: Text.ElideRight
                                text: (card.modelData.current ? "● " : "") + card.modelData.name
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
                        radius: 12
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
        }
        // wheel over the arc browses
        WheelHandler {
            onWheel: event => view.step(event.angleDelta.y > 0 || event.angleDelta.x > 0 ? -1 : 1)
        }

        // ------------------------------------------------------------ hints
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 26
            text: "[← →] browse   [ENTER] apply   [TAB] look   [CTRL+T] crt " + (view.settings.crt ? "off" : "on") + "   [type] filter   [ESC] " + (view.query ? "clear" : "exit")
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
}
