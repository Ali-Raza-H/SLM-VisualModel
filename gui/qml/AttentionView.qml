import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var matrix: []    // 2D array [T][T] (one head)
    property var tokens: []    // token strings (should contain at least last T tokens)
    property int head: 0
    property real phase: 0.0

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.save()
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)

            var m = root.matrix
            if (!m || m.length === 0)
                return

            var n = m.length
            var pad = 18
            var y0 = height - pad

            // Color keyed by head index.
            var pal = [
                {r: 0, g: 229, b: 255},   // cyan
                {r: 255, g: 138, b: 0},   // orange
                {r: 180, g: 0, b: 255},   // violet
                {r: 0, g: 255, b: 160}    // mint
            ]
            var hc = pal[Math.abs(root.head) % pal.length]
            function rgba(alpha) {
                return "rgba(" + hc.r + "," + hc.g + "," + hc.b + "," + alpha.toFixed(3) + ")"
            }

            // Baseline
            ctx.beginPath()
            ctx.strokeStyle = rgba(0.20)
            ctx.lineWidth = 1
            ctx.moveTo(pad, y0 + 0.5)
            ctx.lineTo(width - pad, y0 + 0.5)
            ctx.stroke()

            // Token positions along the baseline
            function xFor(i) {
                if (n <= 1) return width / 2
                return pad + i * (width - 2 * pad) / (n - 1)
            }

            var q = n - 1 // visualize attention from the newest token
            var xq = xFor(q)

            // Choose top-3 keys for the last query token to avoid clutter.
            var weights = m[q]
            var idx = []
            for (var i = 0; i < n; i++) idx.push(i)
            idx.sort(function(a, b) { return (weights[b] || 0) - (weights[a] || 0) })
            idx = idx.slice(0, Math.min(3, idx.length))

            var pulse = 0.65 + 0.35 * Math.sin(root.phase)

            for (var k = 0; k < idx.length; k++) {
                var j = idx[k]
                var w = Math.max(0.0, weights[j] || 0.0)
                var xj = xFor(j)
                var dx = Math.abs(xj - xq)
                var arcHeight = Math.max(24, (height - 2 * pad) * (dx / Math.max(1, (width - 2 * pad))))
                var cy = y0 - arcHeight
                var cx = (xj + xq) / 2

                ctx.beginPath()
                ctx.moveTo(xq, y0)
                ctx.quadraticCurveTo(cx, cy, xj, y0)

                var alpha = (0.08 + 0.92 * w) * pulse
                ctx.strokeStyle = rgba(alpha)
                ctx.shadowColor = rgba(0.35 * alpha)
                ctx.shadowBlur = 14
                ctx.lineWidth = 1 + 8 * w
                ctx.stroke()
            }

            // Draw token markers (highlight last token)
            for (var t = 0; t < n; t++) {
                var xt = xFor(t)
                var isLast = (t === q)
                ctx.beginPath()
                ctx.fillStyle = isLast ? "rgba(255,138,0,0.95)" : rgba(0.55)
                ctx.arc(xt, y0, isLast ? 4.2 : 2.6, 0, Math.PI * 2)
                ctx.fill()
            }
            ctx.restore()
        }
    }

    Connections {
        target: root
        function onMatrixChanged() { canvas.requestPaint() }
        function onPhaseChanged() { canvas.requestPaint() }
    }
}
