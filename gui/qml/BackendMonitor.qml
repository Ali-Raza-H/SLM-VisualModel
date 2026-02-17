import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: mon
    width: 900
    height: 600
    title: "Backend Monitor"

    readonly property color bg: "#05080f"
    readonly property color cyan: "#00e5ff"
    readonly property color orange: "#ff8a00"
    readonly property color panel: "#07111f"

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    onClosing: function(close) {
        close.accepted = false
        mon.visible = false
    }

    Shortcut {
        sequence: "Esc"
        onActivated: mon.visible = false
    }

    Shortcut {
        sequence: "F12"
        onActivated: mon.visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: mon.bg
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        ColumnLayout {
            Layout.preferredWidth: 360
            Layout.fillHeight: true
            spacing: 14

            HudPanel {
                Layout.fillWidth: true
                Layout.preferredHeight: 260
                title: "STATUS"
                accent: mon.cyan

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    Text { text: ws.connected ? "CONNECTED" : "DISCONNECTED"; color: ws.connected ? mon.withAlpha(mon.cyan, 0.92) : mon.withAlpha(mon.orange, 0.92); font.family: "Consolas"; font.pixelSize: 14 }
                    Text { text: ws.busy ? "busy: true" : "busy: false"; color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12 }
                    Text { text: ws.done ? "done: true" : "done: false"; color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12 }
                    Text { text: "device: " + ws.device; color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                    Rectangle { Layout.fillWidth: true; height: 1; color: mon.withAlpha(mon.cyan, 0.12) }

                    Text { text: "t: " + (ws.meta["t"] !== undefined ? ws.meta["t"] : "—"); color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12 }
                    Text { text: "max_seq_len: " + (ws.meta["max_seq_len"] !== undefined ? ws.meta["max_seq_len"] : "—"); color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12 }
                    Text { text: "viz_window: " + (ws.meta["viz_window"] !== undefined ? ws.meta["viz_window"] : "—"); color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12 }
                    Text { text: "gpu: " + (ws.meta["gpu_name"] !== undefined && ws.meta["gpu_name"] !== "" ? ws.meta["gpu_name"] : "—"); color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Text { text: "cuda_available: " + (ws.meta["cuda_available"] !== undefined ? ws.meta["cuda_available"] : "—"); color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12 }
                    Text { text: "torch_cuda: " + (ws.meta["torch_cuda"] !== undefined && ws.meta["torch_cuda"] !== "" ? ws.meta["torch_cuda"] : "—"); color: mon.withAlpha(mon.cyan, 0.75); font.family: "Consolas"; font.pixelSize: 12 }

                    Rectangle { Layout.fillWidth: true; height: 1; color: mon.withAlpha(mon.cyan, 0.12) }

                    Text {
                        text: ws.lastError
                        visible: ws.lastError !== ""
                        color: mon.withAlpha(mon.orange, 0.92)
                        font.family: "Consolas"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            HudPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "PERFORMANCE"
                accent: mon.cyan

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    Text { text: "last_roundtrip_ms: " + ws.lastRoundTripMs.toFixed(0); color: mon.withAlpha(mon.cyan, 0.85); font.family: "Consolas"; font.pixelSize: 12 }
                    Text { text: "last_payload_bytes: " + ws.lastPayloadBytes; color: mon.withAlpha(mon.cyan, 0.85); font.family: "Consolas"; font.pixelSize: 12 }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            HudPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "EVENT LOG"
                accent: mon.cyan

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        HudButton {
                            text: "Clear"
                            accent: mon.cyan
                            panelColor: mon.panel
                            Layout.preferredWidth: 90
                            onClicked: ws.clearLog()
                        }
                        Text {
                            text: ws.logLines.length + " lines"
                            color: mon.withAlpha(mon.cyan, 0.55)
                            font.family: "Consolas"
                            font.pixelSize: 12
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    ListView {
                        id: logView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: ws.logLines
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { }

                        onCountChanged: {
                            if (count > 0) positionViewAtEnd()
                        }

                        delegate: Text {
                            text: modelData
                            width: logView.width
                            wrapMode: Text.WordWrap
                            color: mon.withAlpha(mon.cyan, 0.80)
                            font.family: "Consolas"
                            font.pixelSize: 12
                        }
                    }
                }
            }

            HudPanel {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                title: "LAST JSON"
                accent: mon.cyan

                ScrollView {
                    anchors.fill: parent
                    clip: true

                    TextArea {
                        text: ws.lastJson
                        readOnly: true
                        wrapMode: TextArea.Wrap
                        color: mon.withAlpha(mon.cyan, 0.85)
                        font.family: "Consolas"
                        font.pixelSize: 11
                        background: Rectangle { color: "transparent" }
                    }
                }
            }
        }
    }
}
