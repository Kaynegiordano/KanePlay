import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The PIN to enter in Sunshine to pair a PC, shown large
NavigableDialog {
    id: dialog

    property string pin: "0000"
    property string pcName

    // Pairing can't be interrupted, it ends when the PC answers
    closePolicy: Popup.CloseOnEscape
    width: 580

    onOpened: cancelButton.forceActiveFocus(Qt.TabFocus)

    ColumnLayout {
        width: parent.width
        spacing: 24

        RowLayout {
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 14
                color: Theme.raised

                KpIcon {
                    anchors.centerIn: parent
                    name: "lock"
                    size: 24
                    color: Theme.accent
                }
            }

            ColumnLayout {
                spacing: 2

                Text {
                    text: qsTr("Pair %1").arg(dialog.pcName)
                    font.family: Theme.displayFont
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: Theme.text
                }

                Text {
                    text: qsTr("Only once per PC")
                    font.pixelSize: 14
                    color: Theme.textSecondary
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Repeater {
                model: dialog.pin.split("")

                Rectangle {
                    width: 72
                    height: 88
                    radius: 18
                    color: Theme.background
                    border.width: 2
                    border.color: Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.family: Theme.displayFont
                        font.pixelSize: 40
                        font.weight: Font.Bold
                        color: Theme.text
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("1. On %1, open the Sunshine web page, PIN tab.").arg(dialog.pcName) + "\n" +
                  qsTr("2. Enter this code, then give this device a name.")
            font.pixelSize: 15
            lineHeight: 1.4
            color: Theme.textSecondary
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            BusyIndicator {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                running: dialog.visible
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Waiting for the PC…")
                font.pixelSize: 14
                color: Theme.textSecondary
            }

            KpButton {
                id: cancelButton
                implicitHeight: 44
                text: qsTr("Cancel")
                sound: "back"
                onClicked: dialog.reject()
            }
        }
    }
}
