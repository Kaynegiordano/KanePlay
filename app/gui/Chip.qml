import QtQuick

// A small rounded label, with an optional status dot
Rectangle {
    property string text
    property color textColor: Theme.textSecondary
    property color dotColor: "transparent"

    implicitWidth: chipRow.implicitWidth + 24
    implicitHeight: 30
    radius: 15
    color: Theme.raised
    visible: text !== ""

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: dotColor.a > 0
            width: 8
            height: 8
            radius: 4
            color: dotColor
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.parent.text
            font.family: Theme.textFont
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: parent.parent.textColor
        }
    }
}
