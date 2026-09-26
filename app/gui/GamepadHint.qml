import QtQuick

// One entry of the gamepad hint bar: a button glyph followed by what it does
Row {
    property string glyph
    property string label
    property bool accent: false

    spacing: 8

    GamepadGlyph {
        anchors.verticalCenter: parent.verticalCenter
        glyph: parent.glyph
        accent: parent.accent
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: parent.label
        font.family: Theme.textFont
        font.pixelSize: 14
        color: Theme.textSecondary
    }
}
