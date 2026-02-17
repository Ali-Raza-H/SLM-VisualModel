import QtQuick
import QtQuick.Controls

Item {
    id: root
    property string title: ""
    property color accent: "#00e5ff"
    property color background: "#07111f"

    implicitWidth: 400
    implicitHeight: 260

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 14
        color: root.background
        border.width: 1
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.65)
    }

    // Subtle scanlines + diagonal HUD hatch (painted once per size change).
    Canvas {
        id: hatch
        anchors.fill: panel
        opacity: 0.25
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.save()
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)

            // Scanlines
            ctx.strokeStyle = "rgba(0,229,255,0.08)"
            ctx.lineWidth = 1
            for (var y = 0; y < height; y += 6) {
                ctx.beginPath()
                ctx.moveTo(0, y + 0.5)
                ctx.lineTo(width, y + 0.5)
                ctx.stroke()
            }

            // Diagonal hatch
            ctx.strokeStyle = "rgba(255,138,0,0.05)"
            for (var x = -height; x < width; x += 14) {
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x + height, height)
                ctx.stroke()
            }
            ctx.restore()
        }
    }

    // Soft outer glow
    Canvas {
        id: glow
        anchors.fill: panel
        opacity: 0.65
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.save()
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)

            ctx.shadowColor = "rgba(0,229,255,0.35)"
            ctx.shadowBlur = 18
            ctx.strokeStyle = "rgba(0,229,255,0.25)"
            ctx.lineWidth = 2
            var x = 6, y = 6, w = width - 12, h = height - 12, r = 12
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.lineTo(x + w - r, y)
            ctx.arcTo(x + w, y, x + w, y + r, r)
            ctx.lineTo(x + w, y + h - r)
            ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
            ctx.lineTo(x + r, y + h)
            ctx.arcTo(x, y + h, x, y + h - r, r)
            ctx.lineTo(x, y + r)
            ctx.arcTo(x, y, x + r, y, r)
            ctx.closePath()
            ctx.stroke()
            ctx.restore()
        }
    }

    Text {
        id: titleText
        text: root.title
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 12
        color: root.accent
        font.pixelSize: 14
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        width: parent.width - 24
    }

    Item {
        id: contentItem
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: titleText.bottom
        anchors.margins: 12
        clip: true
    }

    default property alias content: contentItem.data
}
