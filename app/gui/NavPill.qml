import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

// A pill-shaped tab of the top bar
Button {
    property bool selected: false

    id: pill
    activeFocusOnTab: true
    flat: true
    font.family: Theme.textFont
    font.pointSize: 12
    font.weight: Font.DemiBold
    leftPadding: 18
    rightPadding: 18
    topPadding: 9
    bottomPadding: 9

    contentItem: Text {
        text: pill.text
        font: pill.font
        color: pill.selected || pill.hovered || pill.activeFocus ? Theme.text : Theme.textSecondary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: height / 2
        color: pill.selected ? Qt.rgba(1, 1, 1, 0.12)
                             : (pill.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        border.width: pill.activeFocus ? 2 : 0
        border.color: Theme.accent
    }

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
