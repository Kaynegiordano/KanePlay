import QtQuick
import QtQuick.Controls

import UiSound 1.0

// A tab of the top bar; the selected one is a light pill
Button {
    property bool selected: false

    id: pill
    activeFocusOnTab: true
    flat: true
    font.family: Theme.textFont
    font.pixelSize: 15
    font.weight: selected ? Font.Bold : Font.DemiBold
    leftPadding: 20
    rightPadding: 20
    topPadding: 0
    bottomPadding: 0
    implicitHeight: 40

    contentItem: Text {
        text: pill.text
        font: pill.font
        color: pill.selected ? Theme.background :
               pill.hovered || pill.activeFocus ? Theme.text : Theme.textSecondary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
            ColorAnimation { duration: Theme.durationStandard }
        }
    }

    background: Rectangle {
        radius: height / 2
        color: pill.selected ? Theme.text :
               pill.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        border.width: pill.visualFocus ? 2 : 0
        border.color: Theme.accent

        Behavior on color {
            ColorAnimation { duration: Theme.durationStandard }
        }
    }

    onClicked: UiSound.play("tab")

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    Keys.onRightPressed: {
        nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocus)
    }

    Keys.onLeftPressed: {
        nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
    }

    Keys.onDownPressed: {
        stackView.currentItem.forceActiveFocus(Qt.TabFocus)
    }
}
