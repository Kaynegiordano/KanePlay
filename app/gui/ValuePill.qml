import QtQuick

// The value of a setting between ◀ and ▶, which change it with the mouse
Rectangle {
    id: pill

    property string text
    property bool arrows: true

    signal previous()
    signal next()

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 38
    radius: height / 2
    color: Theme.background
    border.width: 1
    border.color: Theme.border

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Item {
            visible: pill.arrows
            width: 18
            height: 38

            KpIcon {
                anchors.centerIn: parent
                name: "arrowLeft"
                size: 14
                color: previousArea.containsMouse ? Theme.text : Theme.textTertiary
            }

            MouseArea {
                id: previousArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: pill.previous()
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            font.family: Theme.textFont
            font.pixelSize: 14
            font.weight: Font.Bold
            color: Theme.text
        }

        Item {
            visible: pill.arrows
            width: 18
            height: 38

            KpIcon {
                anchors.centerIn: parent
                name: "right"
                size: 14
                color: nextArea.containsMouse ? Theme.text : Theme.textTertiary
            }

            MouseArea {
                id: nextArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: pill.next()
            }
        }
    }
}
