import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1280
    height: 720
    visible: true
    title: "SLM Visual Model — Tiny Transformer HUD"

    readonly property color bg: "#05080f"
    readonly property color cyan: "#00e5ff"
    readonly property color orange: "#ff8a00"
    readonly property color panel: "#07111f"

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    property bool needsReset: true
    property real flicker: 0.0
    property real phase: 0.0

    Rectangle {
        anchors.fill: parent
        color: win.bg
    }

    // Background grid
    Canvas {
        anchors.fill: parent
        opacity: 0.25
        onPaint: {
            var ctx = getContext("2d")
            ctx.save()
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)

            ctx.strokeStyle = "rgba(0,229,255,0.06)"
            ctx.lineWidth = 1
            var step = 40
            for (var x = 0; x < width; x += step) {
                ctx.beginPath()
                ctx.moveTo(x + 0.5, 0)
                ctx.lineTo(x + 0.5, height)
                ctx.stroke()
            }
            for (var y = 0; y < height; y += step) {
                ctx.beginPath()
                ctx.moveTo(0, y + 0.5)
                ctx.lineTo(width, y + 0.5)
                ctx.stroke()
            }
            ctx.restore()
        }
    }

    Timer {
        interval: 80
        running: true
        repeat: true
        onTriggered: {
            win.phase += 0.22
            win.flicker = 0.5 + 0.5 * Math.sin(win.phase * 1.7) + 0.12 * (Math.random() - 0.5)
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // VISUALS
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            HudPanel {
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                title: "TOKEN STREAM"
                accent: win.cyan

                TokenStream {
                    anchors.fill: parent
                    tokens: ws.tokens
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                HudPanel {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "ATTENTION (L" + ws.attentionLayer + " / H" + ws.attentionHead + ")"
                    accent: win.cyan
                    AttentionView {
                        anchors.fill: parent
                        matrix: ws.attentionMatrix
                        tokens: ws.tokens
                        head: ws.attentionHead
                        phase: win.phase
                    }
                }

                HudPanel {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "MLP POST-GELU (L" + ws.mlpLayer + ")"
                    accent: win.cyan
                    MLPView {
                        anchors.fill: parent
                        activations: ws.mlpActivations
                        flicker: win.flicker
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 260
                spacing: 14

                HudPanel {
                    Layout.preferredWidth: 360
                    Layout.fillHeight: true
                    title: "TOP-K WHEEL"
                    accent: win.cyan
                    TopKWheel {
                        anchors.centerIn: parent
                        topk: ws.topk
                        sampledId: ws.sampledId
                        sampledToken: ws.sampledToken
                        sampledProb: ws.sampledProb
                    }
                }

                HudPanel {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "RESIDUAL ENERGY (LAST TOKEN)"
                    accent: win.cyan

                    Item {
                        id: resid
                        anchors.fill: parent
                        property real maxNorm: 1.0

                        function updateMax() {
                            if (!ws.residualLayersLast || ws.residualLayersLast.length === 0)
                                return
                            var m = maxNorm
                            for (var i = 0; i < ws.residualLayersLast.length; i++) {
                                m = Math.max(m, ws.residualLayersLast[i])
                            }
                            // gentle decay so the gauge adapts
                            maxNorm = Math.max(1.0, m * 0.98)
                        }

                        Connections {
                            target: ws
                            function onResidualLayersLastChanged() { resid.updateMax(); ring.requestPaint() }
                        }

                        Canvas {
                            id: ring
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.save()
                                ctx.setTransform(1, 0, 0, 1, 0, 0)
                                ctx.clearRect(0, 0, width, height)

                                var vals = ws.residualLayersLast
                                if (!vals || vals.length === 0) return

                                var cx = width / 2
                                var cy = height / 2
                                var r = Math.min(width, height) * 0.32
                                var lw = Math.max(10, Math.min(width, height) * 0.06)
                                var gap = 0.08
                                var seg = (Math.PI * 2) / vals.length

                                for (var i = 0; i < vals.length; i++) {
                                    var start = -Math.PI / 2 + i * seg + gap
                                    var end = -Math.PI / 2 + (i + 1) * seg - gap

                                    // background segment
                                    ctx.beginPath()
                                    ctx.strokeStyle = "rgba(0,229,255,0.14)"
                                    ctx.lineWidth = lw
                                    ctx.arc(cx, cy, r, start, end)
                                    ctx.stroke()

                                    var v = Math.max(0.0, vals[i]) / Math.max(1e-6, resid.maxNorm)
                                    v = Math.min(1.0, v)

                                    var isSel = (i === ws.attentionLayer)
                                    var col = isSel ? win.orange : win.cyan
                                    var alpha = isSel ? 0.92 : 0.55
                                    var ee = start + (end - start) * v

                                    ctx.beginPath()
                                    ctx.shadowColor = isSel ? "rgba(255,138,0,0.35)" : "rgba(0,229,255,0.25)"
                                    ctx.shadowBlur = isSel ? 22 : 14
                                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, alpha)
                                    ctx.lineWidth = lw
                                    ctx.arc(cx, cy, r, start, ee)
                                    ctx.stroke()
                                }

                                // center label
                                ctx.shadowBlur = 0
                                ctx.fillStyle = "rgba(0,229,255,0.85)"
                                ctx.font = "12px Consolas"
                                ctx.textAlign = "center"
                                ctx.fillText("device: " + ws.device, cx, cy - 6)
                                ctx.fillStyle = ws.connected ? "rgba(0,229,255,0.95)" : "rgba(255,138,0,0.85)"
                                ctx.fillText(ws.connected ? "CONNECTED" : "DISCONNECTED", cx, cy + 14)
                                ctx.restore()
                            }
                        }
                    }
                }
            }
        }

        // CONTROLS
        HudPanel {
            Layout.preferredWidth: 360
            Layout.fillHeight: true
            title: "CONTROL PANEL"
            accent: win.cyan

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                Text {
                    text: ws.connected ? "ws://localhost:8765  •  " + ws.device : "Waiting for backend…"
                    color: ws.connected ? win.withAlpha(win.cyan, 0.85) : win.withAlpha(win.orange, 0.85)
                    font.family: "Consolas"
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                TextArea {
                    id: promptArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    placeholderText: "Type a prompt… (next step resets when you press Reset or edit text)"
                    wrapMode: TextArea.Wrap
                    text: "Hello, tiny transformer."
                    color: win.withAlpha(win.cyan, 0.92)
                    selectionColor: win.withAlpha(win.orange, 0.45)
                    font.family: "Consolas"
                    font.pixelSize: 14
                    background: Rectangle {
                        radius: 10
                        color: win.withAlpha(win.panel, 0.85)
                        border.width: 1
                        border.color: win.withAlpha(win.cyan, 0.25)
                    }
                    onTextChanged: win.needsReset = true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button {
                        text: "Reset"
                        Layout.fillWidth: true
                        onClicked: win.needsReset = true
                    }
                    Button {
                        text: ws.busy ? "Working…" : "Generate Next"
                        enabled: ws.connected && !ws.busy && !ws.done
                        Layout.fillWidth: true
                        onClicked: {
                            var p = win.needsReset ? promptArea.text : ""
                            ws.step(p, tempSlider.value, Math.round(topKSlider.value), topPSlider.value,
                                    layerBox.currentIndex, headBox.currentIndex)
                            win.needsReset = false
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    CheckBox {
                        id: autoRun
                        text: "Auto-run"
                        checked: false
                        enabled: ws.connected
                    }
                    Text {
                        text: ws.done ? "EOS sampled" : ""
                        color: win.withAlpha(win.orange, 0.85)
                        font.family: "Consolas"
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }
                }

                Timer {
                    interval: 140
                    running: autoRun.checked
                    repeat: true
                    onTriggered: {
                        if (!ws.connected || ws.busy || ws.done) return
                        var p2 = win.needsReset ? promptArea.text : ""
                        ws.step(p2, tempSlider.value, Math.round(topKSlider.value), topPSlider.value,
                                layerBox.currentIndex, headBox.currentIndex)
                        win.needsReset = false
                    }
                }

                GroupBox {
                    title: "Sampling"
                    Layout.fillWidth: true
                    background: Rectangle { radius: 10; color: win.withAlpha(win.panel, 0.55); border.color: win.withAlpha(win.cyan, 0.18); border.width: 1 }
                    label: Text { text: "Sampling"; color: win.cyan; font.family: "Consolas"; font.pixelSize: 12 }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Temperature"; color: win.withAlpha(win.cyan, 0.85); font.family: "Consolas"; font.pixelSize: 12; Layout.preferredWidth: 110 }
                            Slider { id: tempSlider; Layout.fillWidth: true; from: 0.1; to: 2.0; value: 0.8 }
                            Text { text: tempSlider.value.toFixed(2); color: win.orange; font.family: "Consolas"; font.pixelSize: 12; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Top-k"; color: win.withAlpha(win.cyan, 0.85); font.family: "Consolas"; font.pixelSize: 12; Layout.preferredWidth: 110 }
                            Slider { id: topKSlider; Layout.fillWidth: true; from: 0; to: 100; value: 40; stepSize: 1 }
                            Text { text: Math.round(topKSlider.value); color: win.orange; font.family: "Consolas"; font.pixelSize: 12; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Top-p"; color: win.withAlpha(win.cyan, 0.85); font.family: "Consolas"; font.pixelSize: 12; Layout.preferredWidth: 110 }
                            Slider { id: topPSlider; Layout.fillWidth: true; from: 0.05; to: 1.0; value: 0.9 }
                            Text { text: topPSlider.value.toFixed(2); color: win.orange; font.family: "Consolas"; font.pixelSize: 12; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                GroupBox {
                    title: "Visualization"
                    Layout.fillWidth: true
                    background: Rectangle { radius: 10; color: win.withAlpha(win.panel, 0.55); border.color: win.withAlpha(win.cyan, 0.18); border.width: 1 }
                    label: Text { text: "Visualization"; color: win.cyan; font.family: "Consolas"; font.pixelSize: 12 }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Layer"; color: win.withAlpha(win.cyan, 0.85); font.family: "Consolas"; font.pixelSize: 12; Layout.preferredWidth: 110 }
                            ComboBox {
                                id: layerBox
                                Layout.fillWidth: true
                                model: ["0", "1", "2", "3"]
                                currentIndex: 1
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Head"; color: win.withAlpha(win.cyan, 0.85); font.family: "Consolas"; font.pixelSize: 12; Layout.preferredWidth: 110 }
                            ComboBox {
                                id: headBox
                                Layout.fillWidth: true
                                model: ["0", "1", "2", "3"]
                                currentIndex: 2
                            }
                        }
                    }
                }

                HudPanel {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "OUTPUT (UTF-8, REPLACE ERRORS)"
                    accent: win.cyan

                    ScrollView {
                        anchors.fill: parent
                        clip: true
                        TextArea {
                            text: ws.generated
                            readOnly: true
                            wrapMode: TextArea.Wrap
                            color: win.withAlpha(win.cyan, 0.92)
                            font.family: "Consolas"
                            font.pixelSize: 13
                            background: Rectangle { color: "transparent" }
                        }
                    }
                }

                Text {
                    text: ws.lastError
                    visible: ws.lastError !== ""
                    color: win.withAlpha(win.orange, 0.92)
                    font.family: "Consolas"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }
}
