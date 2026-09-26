import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import UiSound 1.0

// Saves the current settings as a streaming profile of the user, with a name and a color.
// With a gamepad: ◀ ▶ pick the color, A saves (the name can be changed with a keyboard).
NavigableDialog {
    id: dialog

    property var catalog
    property int colorIndex: 0

    // The profile is saved
    signal created()

    function openNew() {
        var count = catalog.customProfiles().length
        nameField.text = catalog.newProfileName()
        colorIndex = (count + 1) % catalog.profileColors.length
        open()
    }

    function save() {
        var name = nameField.text.trim()
        if (name === "") {
            name = catalog.newProfileName()
        }
        catalog.addCustomProfile(name, catalog.profileColors[colorIndex])
        UiSound.play("on")
        created()
        close()
    }

    width: 520

    onOpened: swatches.forceActiveFocus(Qt.TabFocusReason)

    ColumnLayout {
        width: parent.width
        spacing: 18

        Text {
            Layout.fillWidth: true
            text: qsTr("New profile")
            font.family: Theme.displayFont
            font.pixelSize: 22
            font.weight: Font.Bold
            color: Theme.text
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Saves the resolution, frame rate, frame doubler, bitrate, codec, V-Sync and audio as they are now.")
            font.pixelSize: 14
            lineHeight: 1.3
            color: Theme.textSecondary
            wrapMode: Text.Wrap
        }

        TextField {
            id: nameField
            Layout.fillWidth: true
            implicitHeight: 48
            leftPadding: 16
            rightPadding: 16
            topPadding: 0
            bottomPadding: 0
            maximumLength: 32
            color: Theme.text
            font.family: Theme.textFont
            font.pixelSize: 17
            font.weight: Font.Bold
            verticalAlignment: TextInput.AlignVCenter

            background: Rectangle {
                radius: 14
                color: Theme.background
                border.width: nameField.activeFocus ? 2 : 1
                border.color: nameField.activeFocus ? Theme.accent : Theme.border
            }

            Keys.onDownPressed: swatches.forceActiveFocus(Qt.TabFocusReason)
            Keys.onReturnPressed: dialog.save()
            Keys.onEnterPressed: dialog.save()
        }

        // Colors, picked with the arrows
        FocusScope {
            id: swatches
            Layout.fillWidth: true
            implicitHeight: 52

            Keys.onLeftPressed: {
                dialog.colorIndex = (dialog.colorIndex + catalog.profileColors.length - 1) % catalog.profileColors.length
                UiSound.play("move")
            }
            Keys.onRightPressed: {
                dialog.colorIndex = (dialog.colorIndex + 1) % catalog.profileColors.length
                UiSound.play("move")
            }
            Keys.onUpPressed: nameField.forceActiveFocus(Qt.TabFocusReason)
            Keys.onDownPressed: saveButton.forceActiveFocus(Qt.TabFocusReason)
            Keys.onReturnPressed: dialog.save()
            Keys.onEnterPressed: dialog.save()

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Repeater {
                    model: catalog.profileColors

                    Rectangle {
                        readonly property bool chosen: index === dialog.colorIndex

                        width: 44
                        height: 44
                        radius: 22
                        color: "transparent"
                        border.width: chosen ? 3 : 0
                        border.color: swatches.activeFocus ? Theme.text : Theme.textSecondary

                        Rectangle {
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            radius: 16
                            color: modelData

                            KpIcon {
                                anchors.centerIn: parent
                                visible: parent.parent.chosen
                                name: "check"
                                size: 16
                                strokeWidth: 3
                                color: Theme.accentText
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: dialog.colorIndex = index
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                Layout.fillWidth: true
            }

            KpButton {
                id: cancelButton
                variant: "ghost"
                text: qsTr("Cancel")
                sound: "back"
                onClicked: dialog.close()

                Keys.onUpPressed: swatches.forceActiveFocus(Qt.TabFocusReason)
                Keys.onRightPressed: saveButton.forceActiveFocus(Qt.TabFocusReason)
            }

            KpButton {
                id: saveButton
                variant: "primary"
                text: qsTr("Save the profile")
                iconName: "check"
                sound: ""
                onClicked: dialog.save()

                Keys.onUpPressed: swatches.forceActiveFocus(Qt.TabFocusReason)
                Keys.onLeftPressed: cancelButton.forceActiveFocus(Qt.TabFocusReason)
            }
        }
    }
}
