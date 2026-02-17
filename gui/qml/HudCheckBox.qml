import QtQuick
import QtQuick.Controls

CheckBox {
    id: control

    property color accent: "#00e5ff"
    property color panelColor: "#07111f"

    spacing: 8

    font.family: "Consolas"
    font.pixelSize: 12

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        radius: 4
        color: Qt.rgba(control.panelColor.r, control.panelColor.g, control.panelColor.b, 0.65)
        border.width: 1
        border.color: Qt.rgba(control.accent.r, control.accent.g, control.accent.b, control.enabled ? 0.35 : 0.18)

        Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: 2
            visible: control.checked
            color: Qt.rgba(control.accent.r, control.accent.g, control.accent.b, control.enabled ? 0.9 : 0.35)
        }
    }

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled
               ? Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.85)
               : Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.35)
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.implicitWidth + control.spacing
        elide: Text.ElideRight
    }
}

