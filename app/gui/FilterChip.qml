import QtQuick
import QtQuick.Controls

import UiSound 1.0

// A filter of a list, like "All" or "Favorites"; the selected one is light
Button {
    id: chip

    property bool selected: false

    flat: true
    implicitHeight: 38
    leftPadding: 16
    rightPadding: 16
    topPadding: 0
    bottomPadding: 0
    font.family: Theme.textFont
    font.pixelSize: 14
    font.weight: Font.Bold

    contentItem: Text {
        text: chip.text
        font: chip.font
        color: chip.selected ? Theme.background : (chip.hovered ? Theme.text : Theme.textSecondary)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: height / 2
        color: chip.selected ? Theme.text : (chip.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        border.width: chip.visualFocus ? 2 : 1
        border.color: chip.visualFocus ? Theme.accent : (chip.selected ? Theme.text : Theme.border)

        Behavior on color {
            ColorAnimation { duration: Theme.durationStandard }
        }
    }

    onClicked: UiSound.play("tab")

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
}
