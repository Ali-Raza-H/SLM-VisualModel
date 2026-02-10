import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var activations: []   // 2D array [T][d_ff]
    property real flicker: 0.0

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.save()
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)

            var a = root.activations
            if (!a || a.length === 0)
                return

            var rows = a.length
            var cols = (a[0] && a[0].length) ? a[0].length : 0
            if (cols <= 0)
                return

            // Compute normalization scale (max abs).
            var maxAbs = 0.0
            for (var r = 0; r < rows; r++) {
                var row = a[r]
                for (var c = 0; c < cols; c++) {
                    var v = row[c] || 0.0
                    var av = Math.abs(v)
                    if (av > maxAbs) maxAbs = av
                }
            }
            if (maxAbs <= 1e-9) maxAbs = 1.0

            var cellW = width / cols
            var cellH = height / rows

            // Heatmap: negative -> blue, positive -> orange.
            for (var rr = 0; rr < rows; rr++) {
                var row2 = a[rr]
                for (var cc = 0; cc < cols; cc++) {
                    var x = cc * cellW
                    var y = rr * cellH
                    var val = (row2[cc] || 0.0) / maxAbs
                    if (val > 1) val = 1
                    if (val < -1) val = -1

                    var mag = Math.abs(val)
                    var boost = 1.0 + 0.18 * root.flicker * (mag * mag)

                    var rCol, gCol, bCol
                    if (val >= 0) {
                        // Orange-ish
                        rCol = 255
                        gCol = 138
                        bCol = 0
                    } else {
                        // Blue-ish
                        rCol = 0
                        gCol = 110
                        bCol = 255
                    }

                    var alpha = 0.05 + 0.75 * mag
                    alpha = Math.min(0.95, alpha * boost)

                    ctx.fillStyle = "rgba(" + rCol + "," + gCol + "," + bCol + "," + alpha.toFixed(3) + ")"
                    ctx.fillRect(x, y, cellW + 0.6, cellH + 0.6)
                }
            }

            // Subtle grid overlay
            ctx.strokeStyle = "rgba(0,229,255,0.05)"
            ctx.lineWidth = 1
            for (var gy = 0; gy < height; gy += Math.max(10, height / 8)) {
                ctx.beginPath()
                ctx.moveTo(0, gy + 0.5)
                ctx.lineTo(width, gy + 0.5)
                ctx.stroke()
            }
            ctx.restore()
        }
    }

    Connections {
        target: root
        function onActivationsChanged() { canvas.requestPaint() }
        function onFlickerChanged() { canvas.requestPaint() }
    }
}
