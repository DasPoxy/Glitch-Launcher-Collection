import QtQuick
import QtQuick.Shapes

// Glitch-Globe-Launcher's sky traffic, behind the globe: shooting stars now and then,
// a comet once in a while, and spacecraft crossing in the distance. Colours
// come from the theme (`primary` lights the craft and tints the tails).
Item {
    id: sky

    property bool running: true
    property color primary: "#3dff8a"
    property color dark: "#010603"
    // white, leaning a little to the theme: the streaks' tails
    readonly property color tail: Qt.tint("white", Qt.rgba(primary.r, primary.g, primary.b, 0.35))

    function rnd(a, b) { return a + Math.random() * (b - a) }

    // ---------------------------------------------------------- shooting stars
    // a fast streak with a fading tail; three of them, each on its own clock
    component Streak: Item {
        id: st
        property real len: 160
        property real thick: 2
        property real angle: 0
        property real speed: 900          // px/s
        property bool comet: false
        property real minGap: 5000
        property real maxGap: 16000
        visible: fly.running
        width: len
        height: comet ? 18 : thick + 4
        rotation: angle
        transformOrigin: Item.Right

        // the tail, fading out behind the head
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: st.thick
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.75; color: Qt.rgba(sky.tail.r, sky.tail.g, sky.tail.b, 0.45) }
                GradientStop { position: 1.0; color: "white" }
            }
        }
        // a comet's glowing head
        Rectangle {
            visible: st.comet
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.right
            width: 18; height: 18; radius: 9
            color: Qt.rgba(sky.primary.r, sky.primary.g, sky.primary.b, 0.25)
            Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white" }
        }

        function launch() {
            // start just off one side, cross on a shallow diagonal
            const fromLeft = Math.random() < 0.5
            angle = fromLeft ? sky.rnd(12, 38) : 180 - sky.rnd(12, 38)
            const rad = angle * Math.PI / 180
            const dist = sky.rnd(0.45, 0.9) * Math.max(sky.width, sky.height)
            const sx = fromLeft ? sky.rnd(-0.1, 0.55) * sky.width : sky.rnd(0.45, 1.1) * sky.width
            const sy = sky.rnd(-0.1, 0.45) * sky.height
            fx.from = sx - width; fx.to = sx - width + Math.cos(rad) * dist
            fy.from = sy - height / 2; fy.to = sy - height / 2 + Math.sin(rad) * dist
            fx.duration = fy.duration = dist / speed * 1000
            fly.restart()
        }
        ParallelAnimation {
            id: fly
            NumberAnimation { id: fx; target: st; property: "x" }
            NumberAnimation { id: fy; target: st; property: "y" }
            SequentialAnimation {
                NumberAnimation { target: st; property: "opacity"; from: 0; to: 1; duration: 120 }
                PauseAnimation { duration: Math.max(0, fx.duration - 420) }
                NumberAnimation { target: st; property: "opacity"; to: 0; duration: 300 }
            }
        }
        Timer {
            running: sky.running
            interval: sky.rnd(st.minGap * 0.4, st.maxGap * 0.6)
            onTriggered: { st.launch(); interval = sky.rnd(st.minGap, st.maxGap); restart() }
        }
    }

    Streak { len: 170; thick: 2; speed: 1100 }
    Streak { len: 120; thick: 1.5; speed: 1300; minGap: 7000; maxGap: 20000 }
    Streak { len: 220; thick: 2.2; speed: 950; minGap: 9000; maxGap: 24000 }
    // the comet: slower, longer, with a head, and rarer
    Streak { comet: true; len: 420; thick: 4; speed: 260; minGap: 30000; maxGap: 70000 }

    // -------------------------------------------------------------- spacecraft
    // dark hulls with their edges lit in the theme colour, engines flickering
    component Craft: Item {
        id: craft
        property int design: 0           // 0 fighter, 1 freighter, 2 satellite
        width: 64; height: 28

        // engine glow, behind (at the craft's tail, on the left: it flies right)
        Rectangle {
            visible: craft.design !== 2
            x: craft.design === 1 ? -10 : -6
            anchors.verticalCenter: parent.verticalCenter
            width: craft.design === 1 ? 16 : 12; height: width; radius: width / 2
            color: Qt.rgba(sky.primary.r, sky.primary.g, sky.primary.b, 0.55)
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: sky.running
                NumberAnimation { to: 0.35; duration: 90 }
                NumberAnimation { to: 1.0; duration: 120 }
            }
            Rectangle { anchors.centerIn: parent; width: parent.width * 0.4; height: width; radius: width / 2; color: "white" }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // fighter: a dart with swept wings
            ShapePath {
                strokeWidth: craft.design === 0 ? 1.2 : 0
                strokeColor: sky.primary
                fillColor: craft.design === 0 ? sky.dark : "transparent"
                startX: 64; startY: 14
                PathLine { x: 30; y: 9 }
                PathLine { x: 14; y: 0 }
                PathLine { x: 20; y: 10 }
                PathLine { x: 2; y: 11 }
                PathLine { x: 2; y: 17 }
                PathLine { x: 20; y: 18 }
                PathLine { x: 14; y: 28 }
                PathLine { x: 30; y: 19 }
                PathLine { x: 64; y: 14 }
            }
            // freighter: a long blocky hull with a bridge and cargo pods
            ShapePath {
                strokeWidth: craft.design === 1 ? 1.2 : 0
                strokeColor: sky.primary
                fillColor: craft.design === 1 ? sky.dark : "transparent"
                startX: 0; startY: 8
                PathLine { x: 44; y: 8 }
                PathLine { x: 52; y: 4 }
                PathLine { x: 60; y: 4 }
                PathLine { x: 64; y: 12 }
                PathLine { x: 64; y: 16 }
                PathLine { x: 60; y: 22 }
                PathLine { x: 0; y: 22 }
                PathLine { x: 0; y: 8 }
            }
            ShapePath {
                strokeWidth: craft.design === 1 ? 1 : 0
                strokeColor: Qt.rgba(sky.primary.r, sky.primary.g, sky.primary.b, 0.6)
                fillColor: "transparent"
                startX: 10; startY: 8; PathLine { x: 10; y: 22 }
                PathMove { x: 22; y: 8 } PathLine { x: 22; y: 22 }
                PathMove { x: 34; y: 8 } PathLine { x: 34; y: 22 }
            }
            // satellite: a body with two solar panels
            ShapePath {
                strokeWidth: craft.design === 2 ? 1.2 : 0
                strokeColor: sky.primary
                fillColor: craft.design === 2 ? sky.dark : "transparent"
                startX: 26; startY: 8
                PathLine { x: 38; y: 8 } PathLine { x: 38; y: 20 } PathLine { x: 26; y: 20 } PathLine { x: 26; y: 8 }
                PathMove { x: 2; y: 10 } PathLine { x: 22; y: 10 } PathLine { x: 22; y: 18 } PathLine { x: 2; y: 18 } PathLine { x: 2; y: 10 }
                PathMove { x: 42; y: 10 } PathLine { x: 62; y: 10 } PathLine { x: 62; y: 18 } PathLine { x: 42; y: 18 } PathLine { x: 42; y: 10 }
                PathMove { x: 22; y: 14 } PathLine { x: 26; y: 14 }
                PathMove { x: 38; y: 14 } PathLine { x: 42; y: 14 }
            }
        }
        // a blinking nav light
        Rectangle {
            x: craft.design === 2 ? 31 : craft.design === 1 ? 56 : 30
            y: craft.design === 2 ? 5 : craft.design === 1 ? 1 : 12
            width: 3; height: 3; radius: 1.5
            color: "#ff4060"
            SequentialAnimation on opacity {
                loops: Animation.Infinite; running: sky.running
                NumberAnimation { to: 1; duration: 60 } PauseAnimation { duration: 140 }
                NumberAnimation { to: 0.1; duration: 60 } PauseAnimation { duration: 1200 }
            }
        }
    }

    // one pass across the sky: a craft, sometimes a formation of three
    Item {
        id: pass
        visible: passAnim.running
        property bool rightward: true
        property int design: 0
        property bool formation: false
        property real depth: 1             // smaller and slower = farther
        width: 140; height: 90
        scale: depth
        opacity: 0.35 + 0.5 * depth
        transform: Scale { origin.x: pass.width / 2; xScale: pass.rightward ? 1 : -1 }

        Craft { design: pass.design; x: 60; y: 30 }
        Craft { design: pass.design; x: 18; y: 4; visible: pass.formation; scale: 0.8 }
        Craft { design: pass.design; x: 18; y: 58; visible: pass.formation; scale: 0.8 }

        SequentialAnimation on rotation {
            loops: Animation.Infinite; running: passAnim.running && pass.design === 2
            NumberAnimation { from: -8; to: 8; duration: 5000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 8; to: -8; duration: 5000; easing.type: Easing.InOutSine }
        }

        function go() {
            design = Math.floor(Math.random() * 3)
            formation = design !== 2 && Math.random() < 0.3
            rightward = Math.random() < 0.5
            depth = sky.rnd(0.45, 1.1)
            const y0 = sky.rnd(0.08, 0.85) * sky.height
            const y1 = y0 + sky.rnd(-0.12, 0.12) * sky.height
            px.from = rightward ? -width * 1.2 : sky.width + width * 0.2
            px.to = rightward ? sky.width + width * 0.2 : -width * 1.2
            py.from = y0; py.to = y1
            px.duration = py.duration = (design === 2 ? 26000 : 13000) / depth * sky.rnd(0.8, 1.2)
            passAnim.restart()
        }
        ParallelAnimation {
            id: passAnim
            NumberAnimation { id: px; target: pass; property: "x" }
            NumberAnimation { id: py; target: pass; property: "y"; easing.type: Easing.InOutSine }
        }
        Timer {
            running: sky.running && !passAnim.running
            interval: sky.rnd(8000, 20000)
            onTriggered: { pass.go(); interval = sky.rnd(20000, 50000) }
        }
    }
}
