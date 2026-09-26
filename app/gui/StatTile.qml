import QtQuick
import QtQuick.Layouts

// A figure with its label and unit, like the latency of the last session
Rectangle {
    property string label
    property var value
    property string unit

    Layout.fillWidth: true
    implicitHeight: 72
    radius: 14
    color: Theme.background

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            text: label.toUpperCase()
            font.family: Theme.textFont
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 0.7
            color: Theme.textSecondary
        }

        RowLayout {
            spacing: 4

            Text {
                Layout.alignment: Qt.AlignBaseline
                text: value !== undefined ? value : ""
                font.family: Theme.displayFont
                font.pixelSize: 22
                font.weight: Font.DemiBold
                color: Theme.text
            }

            Text {
                Layout.alignment: Qt.AlignBaseline
                text: unit
                font.family: Theme.textFont
                font.pixelSize: 13
                color: Theme.textSecondary
            }
        }
    }
}
