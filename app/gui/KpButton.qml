import QtQuick
import QtQuick.Controls

import UiSound 1.0

// Buttons of the design: "primary" (ember), "secondary" (raised), "ghost" (outline) or "danger"
AbstractButton {
    id: button

    property string variant: "secondary"
    property string iconName: ""
    property bool iconFilled: false
    property real iconSize: 20
    // Primary buttons use the display face, like the design's "Jouer"
    property bool displayFont: variant === "primary"
    property int fontSize: displayFont ? 17 : 15
    property string sound: "select"
    // Circular icon button, like the actions of the top bar
    property bool round: false

    // KaneMode: a focused secondary, ghost or danger button turns white (primary keeps its accent)
    readonly property bool whiteFocus: Theme.whiteFocus && visualFocus && variant !== "primary"
    readonly property color foreground: whiteFocus ? Theme.focusText :
                                        variant === "primary" ? Theme.primaryText :
                                        variant === "danger" ? Theme.danger : Theme.text

    implicitHeight: 56
    implicitWidth: Math.max(implicitHeight, contentRow.implicitWidth + leftPadding + rightPadding)
    leftPadding: text !== "" ? 24 : 0
    rightPadding: leftPadding
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.4

    contentItem: Item {
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 10

            KpIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.iconName !== ""
                name: button.iconName
                size: button.iconSize
                filled: button.iconFilled
                color: button.foreground
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: button.text
                font.family: button.displayFont ? Theme.displayFont : Theme.textFont
                font.pixelSize: button.fontSize
                font.weight: Font.Bold
                color: button.foreground
            }
        }
    }

    background: Rectangle {
        radius: button.round ? height / 2 : Theme.radius
        color: button.whiteFocus ? Theme.focusFill :
               button.variant === "primary" ? (button.hovered ? Theme.primaryHover : Theme.primary) :
               button.variant === "ghost" ? (button.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent") :
               (button.hovered ? Theme.hover : Theme.raised)
        // KaneMode's play button: green gradient
        gradient: button.variant === "primary" && !button.hovered && Theme.kaneMode ? playGradient : null
        border.width: button.variant === "primary" ? 0 : 1
        border.color: Theme.border

        Behavior on color {
            ColorAnimation { duration: Theme.durationFast }
        }

        // Focus ring for keyboard and gamepad navigation
        Rectangle {
            anchors.fill: parent
            anchors.margins: -5
            radius: parent.radius + 5
            color: "transparent"
            border.width: Theme.whiteFocus ? 3 : 2
            border.color: button.variant === "primary" ? Theme.text : Theme.accent
            opacity: button.visualFocus && !button.whiteFocus ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.durationFast }
            }
        }
    }

    Gradient {
        id: playGradient
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Theme.primary }
        GradientStop { position: 1; color: Theme.primaryEnd }
    }

    // A wide button grows by a few pixels only, so it never covers its neighbors
    scale: pressed && Theme.motion ? 0.97 : visualFocus ? Math.min(Theme.focusScale, 1 + 12 / Math.max(width, 1)) : 1

    Behavior on scale {
        NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic }
    }

    onClicked: {
        if (sound !== "") {
            UiSound.play(sound)
        }
    }

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
}
