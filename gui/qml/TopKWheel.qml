import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var topk: []               // list of {id, token, prob}
    property int sampledId: -1
    property string sampledToken: ""
    property real sampledProb: 0.0

    property color coldColor: "#00e5ff"
    property color hotColor: "#ff8a00"

    implicitWidth: 260
    implicitHeight: 260

    Canvas {
        id: wheel
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.save()
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)

            var cx = width / 2
            var cy = height / 2
            var r = Math.min(width, height) * 0.40
            var lw = Math.max(6, Math.min(width, height) * 0.04)

            // Outer ring
            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,229,255,0.18)"
            ctx.lineWidth = lw
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.stroke()

            if (!root.topk || root.topk.length === 0)
                return

            // Normalize to sum(topk) so the wheel fills the circle.
            var sum = 0.0
            for (var i = 0; i < root.topk.length; i++) {
                sum += Math.max(0.0, root.topk[i].prob)
            }
            if (sum <= 0) sum = 1.0

            var gap = 0.03
            var a = -Math.PI / 2
            for (var j = 0; j < root.topk.length; j++) {
                var item = root.topk[j]
                var p = Math.max(0.0, item.prob) / sum
                var sweep = Math.max(0.0, p * Math.PI * 2 - gap)

                var isSel = (item.id === root.sampledId)
                var col = isSel ? root.hotColor : root.coldColor
                var alpha = isSel ? 0.9 : 0.55

                ctx.beginPath()
                ctx.shadowColor = isSel ? "rgba(255,138,0,0.35)" : "rgba(0,229,255,0.25)"
                ctx.shadowBlur = isSel ? 18 : 10
                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, alpha)
                ctx.lineWidth = isSel ? (lw + 3) : lw
                ctx.arc(cx, cy, r, a, a + sweep)
                ctx.stroke()

                a += p * Math.PI * 2
            }
            ctx.restore()
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 4
        Text {
            text: root.sampledToken === "" ? "—" : root.sampledToken
            color: root.hotColor
            font.family: "Consolas"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }
        Text {
            text: "p=" + root.sampledProb.toFixed(3)
            color: Qt.rgba(root.coldColor.r, root.coldColor.g, root.coldColor.b, 0.85)
            font.family: "Consolas"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }
    }

    Connections {
        target: root
        function onTopkChanged() { wheel.requestPaint() }
        function onSampledIdChanged() { wheel.requestPaint() }
    }
}
