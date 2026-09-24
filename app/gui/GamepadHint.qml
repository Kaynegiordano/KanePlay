import QtQuick 2.9

// One entry of the gamepad hint bar: a button glyph followed by what it does
Row {
    property string glyph
    property string label

    spacing: 8

    Rectangle {
        width: Math.max(24, glyphText.implicitWidth + 12)
        height: 24
        radius: 12
        color: Theme.text
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: glyphText
            anchors.centerIn: parent
            text: glyph
            font.family: Theme.textFont
            font.pointSize: 9
            font.bold: true
            color: Theme.background
        }
    }

    Text {
        text: label
        font.family: Theme.textFont
        font.pointSize: 11
        color: Theme.textSecondary
        anchors.verticalCenter: parent.verticalCenter
    }
}
