import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var tokens: []
    property color coldColor: "#00e5ff"
    property color hotColor: "#ff8a00"

    clip: true

    onTokensChanged: {
        Qt.callLater(function() {
            if (view.count > 0) view.positionViewAtEnd()
        })
    }

    ListView {
        id: view
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: 2
        clip: true
        model: root.tokens
        boundsBehavior: Flickable.StopAtBounds

        onCountChanged: {
            if (count > 0) positionViewAtEnd()
        }

        delegate: Text {
            text: modelData
            color: (index === view.count - 1) ? root.hotColor : root.coldColor
            opacity: (index === view.count - 1) ? 1.0 : 0.72
            font.family: "Consolas"
            font.pixelSize: 16
            font.weight: Font.Light
            font.letterSpacing: 0.6

            scale: (index === view.count - 1) ? 1.15 : 1.0
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
        }
    }
}
