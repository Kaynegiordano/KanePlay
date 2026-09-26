import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import AutoUpdateChecker 1.0
import SystemProperties 1.0
import UiSound 1.0

// A new version is available: what's new, then download, check and install it.
// KanePlay closes for the installer and starts again once it's done.
NavigableDialog {
    id: dialog

    property string version
    property string notes
    property string browserUrl
    property bool downloading: false
    property real progress: 0
    property real receivedMb: 0
    property real totalMb: 0
    property string errorText

    width: 580
    // Long notes scroll, so the buttons always stay on screen
    readonly property real notesMaxHeight: Math.max(140, (Overlay.overlay ? Overlay.overlay.height : 720) - 420)
    closePolicy: downloading ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

    function install() {
        if (!AutoUpdateChecker.canInstallUpdate()) {
            // No installer in the channel, let the browser take it from there
            if (SystemProperties.hasBrowser && browserUrl !== "") {
                Qt.openUrlExternally(browserUrl)
            }
            close()
            return
        }

        errorText = ""
        progress = 0
        downloading = true
        UiSound.play("select")
        AutoUpdateChecker.installUpdate()
    }

    // Up and down on the gamepad scroll the notes
    function scrollNotes(delta) {
        var maxY = Math.max(0, notesFlickable.contentHeight - notesFlickable.height)
        notesFlickable.contentY = Math.min(maxY, Math.max(0, notesFlickable.contentY + delta))
    }

    function cancel() {
        if (downloading) {
            AutoUpdateChecker.cancelUpdate()
            downloading = false
        }
        close()
    }

    Connections {
        target: AutoUpdateChecker

        function onUpdateNotesAvailable(newNotes) {
            dialog.notes = newNotes
        }

        function onUpdateDownloadProgress(received, total) {
            dialog.receivedMb = received / 1048576
            dialog.totalMb = total / 1048576
            dialog.progress = total > 0 ? received / total : 0
        }

        function onUpdateDownloadFailed(error) {
            dialog.downloading = false
            dialog.errorText = error
            UiSound.play("error")
        }

        function onUpdateInstallerStarted() {
            Qt.quit()
        }
    }

    onOpened: installButton.forceActiveFocus(Qt.TabFocusReason)

    ColumnLayout {
        width: parent.width
        spacing: 22

        RowLayout {
            spacing: 16

            Image {
                source: "qrc:/res/kaneplay.svg"
                sourceSize.width: 56
                sourceSize.height: 56
            }

            ColumnLayout {
                spacing: 4

                Text {
                    text: qsTr("Update available")
                    font.family: Theme.displayFont
                    font.pixelSize: 24
                    font.weight: Font.Bold
                    font.letterSpacing: -0.5
                    color: Theme.text
                }

                Text {
                    text: qsTr("KanePlay %1").arg(dialog.version)
                    font.pixelSize: 15
                    color: Theme.textSecondary
                }
            }
        }

        // What's new, one line each
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(notesColumn.implicitHeight + 36, dialog.notesMaxHeight)
            visible: dialog.notes !== ""
            radius: 18
            color: Theme.background

            Flickable {
                id: notesFlickable
                anchors.fill: parent
                anchors.margins: 18
                contentHeight: notesColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: notesFlickable.contentHeight > notesFlickable.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                }

            ColumnLayout {
                id: notesColumn
                width: notesFlickable.width - 12
                spacing: 10

                Repeater {
                    model: dialog.notes.split("\n").filter(function(line) { return line.trim() !== "" })

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        KpIcon {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 2
                            name: "check"
                            size: 16
                            strokeWidth: 2.6
                            color: Theme.accent
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.replace(/^[-•*]\s*/, "")
                            font.pixelSize: 15
                            lineHeight: 1.3
                            color: Theme.text
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                visible: dialog.downloading

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Downloading…")
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: Theme.text
                }

                Text {
                    visible: dialog.totalMb > 0
                    text: qsTr("%1 MB of %2").arg(Math.round(dialog.receivedMb)).arg(Math.round(dialog.totalMb))
                    font.pixelSize: 14
                    color: Theme.textSecondary
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: dialog.downloading
                implicitHeight: 8
                radius: 4
                color: Theme.raised

                Rectangle {
                    width: parent.width * dialog.progress
                    height: parent.height
                    radius: 4
                    color: Theme.accent

                    Behavior on width {
                        NumberAnimation { duration: Theme.durationStandard }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: dialog.errorText !== "" ? qsTr("The update failed: %1").arg(dialog.errorText) :
                      qsTr("The file is checked, then KanePlay closes, installs the update and starts again.")
                font.pixelSize: 13
                lineHeight: 1.3
                color: dialog.errorText !== "" ? Theme.danger : Theme.textSecondary
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            KpButton {
                id: installButton
                Layout.fillWidth: true
                variant: "primary"
                iconName: "download"
                text: dialog.errorText !== "" ? qsTr("Try again") : qsTr("Install")
                enabled: !dialog.downloading
                sound: ""
                onClicked: dialog.install()

                KeyNavigation.right: laterButton
                Keys.onUpPressed: dialog.scrollNotes(-80)
                Keys.onDownPressed: dialog.scrollNotes(80)
            }

            KpButton {
                id: laterButton
                text: dialog.downloading ? qsTr("Cancel") : qsTr("Later")
                sound: "back"
                onClicked: dialog.cancel()

                KeyNavigation.left: installButton
                Keys.onUpPressed: dialog.scrollNotes(-80)
                Keys.onDownPressed: dialog.scrollNotes(80)
            }
        }
    }
}
