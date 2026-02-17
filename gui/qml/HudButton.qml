import QtQuick
import QtQuick.Controls

Button {
    id: control

    property color accent: "#00e5ff"
    property color panelColor: "#07111f"
    property color textColor: accent

    implicitHeight: 36

    font.family: "Consolas"
    font.pixelSize: 12

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled
               ? Qt.rgba(control.textColor.r, control.textColor.g, control.textColor.b, 0.92)
               : Qt.rgba(control.textColor.r, control.textColor.g, control.textColor.b, 0.35)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 10
        color: control.down
               ? Qt.rgba(control.panelColor.r, control.panelColor.g, control.panelColor.b, 0.92)
               : control.hovered
                 ? Qt.rgba(control.panelColor.r, control.panelColor.g, control.panelColor.b, 0.78)
                 : Qt.rgba(control.panelColor.r, control.panelColor.g, control.panelColor.b, 0.64)
        border.width: 1
        border.color: control.enabled
                      ? Qt.rgba(control.accent.r, control.accent.g, control.accent.b, control.hovered ? 0.55 : 0.35)
                      : Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.18)
    }
}

