import QtQuick

// A gamepad button as drawn in the hints: A, B, LB, ◀ ▶…
Rectangle {
    property string glyph
    property bool accent: false

    implicitWidth: Math.max(24, glyphText.implicitWidth + 14)
    implicitHeight: 24
    radius: 12
    color: accent ? Theme.accent : Theme.raised
    border.width: 1
    border.color: Theme.border

    Text {
        id: glyphText
        anchors.centerIn: parent
        text: parent.glyph
        font.family: Theme.textFont
        font.pixelSize: 11
        font.weight: Font.Bold
        color: parent.accent ? Theme.accentText : Theme.text
    }
}
