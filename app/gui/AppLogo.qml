import QtQuick

// Logo of the app: KaneMode's (its accent color, like its own logo) when embedded, KanePlay's otherwise
Item {
    id: logo

    property real size: 48

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        visible: Theme.kaneMode
        radius: logo.size / 4
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.accent }
            GradientStop { position: 1; color: "#6A5CFF" }
        }

        Image {
            anchors.fill: parent
            source: "qrc:/res/kanemode-k.svg"
            sourceSize.width: logo.size
            sourceSize.height: logo.size
        }
    }

    Image {
        anchors.fill: parent
        visible: !Theme.kaneMode
        source: "qrc:/res/kaneplay.svg"
        sourceSize.width: logo.size
        sourceSize.height: logo.size
    }
}
