import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import AutoUpdateChecker 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import UiSound 1.0

import "SpatialNav.js" as SpatialNav

// About KanePlay: its version, where it comes from, and the licenses of what it's made of
FocusScope {
    id: aboutView
    objectName: qsTr("About")

    // "", "checking", "uptodate", "available" or "failed"
    property string updateStatus: ""
    property var navItems: []

    readonly property var gamepadHints: [
        { glyph: "A", label: qsTr("Open"), accent: true },
        { glyph: "B", label: qsTr("Back") }
    ]

    // Components and their license. `file` is the full text shipped with the app, if any.
    readonly property var licenses: [
        { name: "KanePlay", license: "GPL v3", file: "qrc:/res/licenses/GPL-3.0.txt" },
        { name: "Moonlight (moonlight-qt, moonlight-common-c)", license: "GPL v3", file: "qrc:/res/licenses/GPL-3.0.txt" },
        { name: "Qt", license: "LGPL v3", file: "qrc:/res/licenses/LGPL-3.0.txt" },
        { name: "FFmpeg, libplacebo", license: "LGPL 2.1+", file: "qrc:/res/licenses/LGPL-2.1.txt" },
        { name: "SDL, SDL_ttf", license: "zlib", file: "qrc:/res/licenses/SDL-zlib.txt" },
        { name: "OpenSSL", license: "Apache 2.0", file: "qrc:/res/licenses/Apache-2.0.txt" },
        { name: "Opus, dav1d", license: "BSD", url: "https://opensource.org/license/bsd-3-clause" },
        { name: "AMD AMF SDK", license: "MIT", file: "qrc:/res/licenses/AMF-MIT.txt" },
        { name: "Unbounded", license: "OFL 1.1", file: "qrc:/res/fonts/OFL-Unbounded.txt" },
        { name: "Manrope", license: "OFL 1.1", file: "qrc:/res/fonts/OFL-Manrope.txt" }
    ]

    function move(direction) {
        var next = SpatialNav.nearest(navItems, Window.activeFocusItem, direction, aboutView)
        if (next !== null) {
            next.forceActiveFocus(Qt.TabFocusReason)
        }
        else if (direction === "up") {
            settingsButton.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    function openLicense(entry) {
        UiSound.play("select")
        if (entry.file !== undefined) {
            licenseDialog.show(entry.name + " · " + entry.license, entry.file)
        }
        else if (SystemProperties.hasBrowser) {
            Qt.openUrlExternally(entry.url)
        }
    }

    function checkForUpdate() {
        updateStatus = "checking"
        AutoUpdateChecker.start()
    }

    Keys.onUpPressed: move("up")
    Keys.onDownPressed: move("down")
    Keys.onLeftPressed: move("left")
    Keys.onRightPressed: move("right")

    StackView.onActivated: {
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            updateButton.forceActiveFocus(Qt.TabFocusReason)
        }
        else {
            forceActiveFocus()
        }
    }

    Connections {
        target: AutoUpdateChecker

        function onUpdateCheckFinished(available, failed) {
            if (aboutView.updateStatus === "checking") {
                aboutView.updateStatus = failed ? "failed" : available ? "available" : "uptodate"

                // Asked for by hand: show the update right away
                if (available) {
                    updateDialog.open()
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding
        anchors.topMargin: 8
        anchors.bottomMargin: 24
        spacing: 28

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 22

                RowLayout {
                    spacing: 20

                    AppLogo {
                        size: 84
                    }

                    ColumnLayout {
                        spacing: 6

                        Text {
                            text: "KanePlay"
                            font.family: Theme.displayFont
                            font.pixelSize: 36
                            font.weight: Font.Bold
                            font.letterSpacing: -1
                            color: Theme.text
                        }

                        Text {
                            text: "Can play."
                            font.family: Theme.displayFont
                            font.pixelSize: 16
                            color: Theme.accent
                        }
                    }
                }

                Text {
                    text: qsTr("Version %1").arg(SystemProperties.versionString)
                    font.pixelSize: 15
                    color: Theme.textSecondary
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("KanePlay is free game streaming software, <b>based on Moonlight</b>. It is an independent project, affiliated with neither the Moonlight project nor NVIDIA.")
                    textFormat: Text.StyledText
                    font.pixelSize: 16
                    lineHeight: 1.5
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                }

                Item {
                    Layout.fillHeight: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: aboutView.updateStatus !== "" && aboutView.updateStatus !== "checking"
                    text: aboutView.updateStatus === "uptodate" ? qsTr("KanePlay is up to date.") :
                          aboutView.updateStatus === "available" ? qsTr("An update is available.") :
                          qsTr("Unable to check for updates right now.")
                    font.pixelSize: 14
                    color: aboutView.updateStatus === "uptodate" ? Theme.success :
                           aboutView.updateStatus === "available" ? Theme.accent2 : Theme.danger
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    KpButton {
                        id: sourceButton
                        Layout.fillWidth: true
                        iconName: "code"
                        text: qsTr("Source code")
                        visible: SystemProperties.hasBrowser
                        onClicked: Qt.openUrlExternally("https://github.com/Kaynegiordano/KanePlay")

                        Component.onCompleted: aboutView.navItems.push(sourceButton)
                    }

                    KpButton {
                        id: updateButton
                        Layout.fillWidth: true
                        iconName: "refresh"
                        text: aboutView.updateStatus === "checking" ? qsTr("Checking…") : qsTr("Check for updates")
                        enabled: aboutView.updateStatus !== "checking"
                        onClicked: aboutView.checkForUpdate()

                        Component.onCompleted: aboutView.navItems.push(updateButton)
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 500
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                anchors.topMargin: 24
                spacing: 4

                Text {
                    Layout.leftMargin: 14
                    Layout.bottomMargin: 8
                    text: qsTr("Licenses").toUpperCase()
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1.3
                    color: Theme.textSecondary
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: aboutView.licenses

                    delegate: AbstractButton {
                        id: licenseRow

                        width: ListView.view.width
                        height: 46
                        focusPolicy: Qt.StrongFocus
                        hoverEnabled: true
                        leftPadding: 14
                        rightPadding: 14

                        Component.onCompleted: aboutView.navItems.push(licenseRow)

                        onClicked: aboutView.openLicense(modelData)
                        Keys.onReturnPressed: clicked()
                        Keys.onEnterPressed: clicked()

                        onActiveFocusChanged: {
                            if (activeFocus) {
                                ListView.view.positionViewAtIndex(index, ListView.Contain)
                            }
                        }

                        background: Rectangle {
                            radius: 12
                            // KaneMode: white when selected with the gamepad, dark text
                            color: Theme.whiteFocus && licenseRow.activeFocus ? Theme.tileFill : licenseRow.activeFocus ? Theme.raised : (licenseRow.hovered ? Theme.hover : "transparent")
                            border.width: licenseRow.activeFocus && !Theme.whiteFocus ? 2 : 0
                            border.color: Theme.accent
                        }

                        contentItem: RowLayout {
                            spacing: 12

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                color: Theme.whiteFocus && licenseRow.activeFocus ? Theme.tileText : Theme.text
                                elide: Text.ElideRight
                            }

                            Text {
                                text: modelData.license
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: Theme.textSecondary
                            }

                            KpIcon {
                                name: modelData.file !== undefined ? "right" : "globe"
                                size: 16
                                color: Theme.textTertiary
                            }
                        }
                    }
                }
            }
        }
    }

    // Full text of a license shipped with the app
    NavigableDialog {
        id: licenseDialog

        property string licenseTitle
        property string licenseText

        function show(newTitle, file) {
            licenseTitle = newTitle
            licenseText = ""
            var request = new XMLHttpRequest()
            request.onreadystatechange = function() {
                if (request.readyState === XMLHttpRequest.DONE) {
                    licenseDialog.licenseText = request.responseText
                }
            }
            request.open("GET", file)
            request.send()
            open()
        }

        width: Math.min(820, aboutView.width - 80)
        height: aboutView.height - 40
        standardButtons: Dialog.Close

        onOpened: licenseScroll.forceActiveFocus()

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: licenseDialog.licenseTitle
                font.family: Theme.displayFont
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Theme.text
                elide: Text.ElideRight
            }

            ScrollView {
                id: licenseScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                focus: true

                Keys.onUpPressed: ScrollBar.vertical.decrease()
                Keys.onDownPressed: ScrollBar.vertical.increase()

                TextArea {
                    readOnly: true
                    wrapMode: TextArea.Wrap
                    text: licenseDialog.licenseText
                    font.family: "Consolas"
                    font.pixelSize: 13
                    color: Theme.textSecondary
                    background: null
                }
            }
        }
    }
}
