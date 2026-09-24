import QtQuick 2.9
import QtQuick.Controls 2.2

// Large action button of the library screen. The primary one is filled with the
// accent color and can show the gamepad button that triggers it.
Button {
    property bool primary: false
    property string glyph: ""

    id: heroButton
    activeFocusOnTab: true
    font.family: Theme.textFont
    font.pointSize: 14
    font.weight: primary ? Font.Bold : Font.DemiBold
    leftPadding: glyph ? 18 : 26
    rightPadding: 28
    topPadding: 14
    bottomPadding: 14

    contentItem: Row {
        spacing: 12

        Rectangle {
            visible: heroButton.glyph !== ""
            width: 26
            height: 26
            radius: 13
            anchors.verticalCenter: parent.verticalCenter
            color: heroButton.primary ? Theme.accentText : Theme.text

            Text {
                anchors.centerIn: parent
                text: heroButton.glyph
                font.family: Theme.textFont
                font.pointSize: 9
                font.bold: true
                color: heroButton.primary ? Theme.accent : Theme.background
            }
        }

        Text {
            text: heroButton.text
            font: heroButton.font
            color: heroButton.primary ? Theme.accentText : Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: Theme.radius
        color: heroButton.primary ? (heroButton.hovered ? Theme.accentHover : Theme.accent)
                                  : (heroButton.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.04, 0.05, 0.07, 0.6))
        border.width: heroButton.activeFocus ? 3 : (heroButton.primary ? 0 : 1)
        border.color: heroButton.activeFocus ? Theme.text : Qt.rgba(1, 1, 1, 0.22)
    }

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
}
