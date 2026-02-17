import QtQuick
import QtQuick.Controls

ComboBox {
    id: control

    property color accent: "#00e5ff"
    property color panelColor: "#07111f"

    implicitHeight: 34

    font.family: "Consolas"
    font.pixelSize: 12

    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.enabled
               ? Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.92)
               : Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.35)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        leftPadding: 10
        rightPadding: control.indicator.implicitWidth + control.spacing
    }

    indicator: Canvas {
        implicitWidth: 18
        implicitHeight: 18
        x: control.width - width - 8
        y: (control.height - height) / 2
        contextType: "2d"
        onPaint: {
            var ctx = getContext("2d")
            ctx.save()
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = "rgba(" + Math.round(control.accent.r * 255) + "," + Math.round(control.accent.g * 255) + "," + Math.round(control.accent.b * 255) + ",0.75)"
            ctx.beginPath()
            ctx.moveTo(4, 7)
            ctx.lineTo(width - 4, 7)
            ctx.lineTo(width / 2, height - 5)
            ctx.closePath()
            ctx.fill()
            ctx.restore()
        }
    }

    background: Rectangle {
        radius: 10
        color: Qt.rgba(control.panelColor.r, control.panelColor.g, control.panelColor.b, 0.65)
        border.width: 1
        border.color: Qt.rgba(control.accent.r, control.accent.g, control.accent.b, control.hovered ? 0.45 : 0.28)
    }

    delegate: ItemDelegate {
        width: control.width
        padding: 8
        contentItem: Text {
            text: modelData
            font: control.font
            color: Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.92)
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: (control.highlightedIndex === index)
                   ? Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.14)
                   : Qt.rgba(control.panelColor.r, control.panelColor.g, control.panelColor.b, 0.92)
        }
    }

    popup: Popup {
        y: control.height - 1
        width: control.width
        padding: 0

        background: Rectangle {
            radius: 10
            color: Qt.rgba(control.panelColor.r, control.panelColor.g, control.panelColor.b, 0.96)
            border.width: 1
            border.color: Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.28)
        }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
        }
    }
}

