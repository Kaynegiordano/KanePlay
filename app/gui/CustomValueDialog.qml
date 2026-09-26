import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import StreamingPreferences 1.0

// Asks for a custom resolution or frame rate
NavigableDialog {
    id: dialog

    // "resolution" or "fps"
    property string kind: "resolution"
    property var catalog

    function openFor(newKind) {
        kind = newKind
        firstField.text = kind === "resolution" ? String(StreamingPreferences.width) : String(StreamingPreferences.fps)
        secondField.text = String(StreamingPreferences.height)
        open()
    }

    function isInputValid() {
        return firstField.acceptableInput && (kind !== "resolution" || secondField.acceptableInput)
    }

    standardButtons: Dialog.Ok | Dialog.Cancel
    width: 480

    onOpened: {
        firstField.forceActiveFocus()
        firstField.selectAll()
    }

    onAccepted: {
        if (!isInputValid()) {
            return
        }

        if (kind === "resolution") {
            catalog.setResolution(parseInt(firstField.text), parseInt(secondField.text), false)
        }
        else {
            catalog.setFps(parseInt(firstField.text), false)
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: 16

        Text {
            Layout.fillWidth: true
            text: dialog.kind === "resolution" ? qsTr("Custom resolution") : qsTr("Custom frame rate")
            font.family: Theme.displayFont
            font.pixelSize: 22
            font.weight: Font.Bold
            color: Theme.text
        }

        Text {
            Layout.fillWidth: true
            text: dialog.kind === "resolution" ?
                      qsTr("The host PC doesn't change its own resolution to match: set it in the game. Values your devices don't support may cause errors.") :
                      qsTr("Frame rates your devices don't support may cause errors.")
            font.pixelSize: 14
            lineHeight: 1.3
            color: Theme.textSecondary
            wrapMode: Text.Wrap
        }

        RowLayout {
            spacing: 12

            TextField {
                id: firstField
                Layout.preferredWidth: 140
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: dialog.kind === "resolution" ? 256 : 10; top: dialog.kind === "resolution" ? 8192 : 9999 }
                font.pixelSize: 20

                Keys.onReturnPressed: dialog.accept()
                Keys.onEnterPressed: dialog.accept()
            }

            Text {
                visible: dialog.kind === "resolution"
                text: "×"
                font.pixelSize: 20
                color: Theme.textSecondary
            }

            TextField {
                id: secondField
                visible: dialog.kind === "resolution"
                Layout.preferredWidth: 140
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 256; top: 8192 }
                font.pixelSize: 20

                Keys.onReturnPressed: dialog.accept()
                Keys.onEnterPressed: dialog.accept()
            }

            Text {
                visible: dialog.kind === "fps"
                text: qsTr("FPS")
                font.pixelSize: 16
                color: Theme.textSecondary
            }
        }
    }
}
