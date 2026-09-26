import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import UiSound 1.0

import "SpatialNav.js" as SpatialNav

// Adds a PC by its address. A keypad lets gamepad users type an IP address.
FocusScope {
    id: addPcView
    objectName: qsTr("Add a PC")

    property bool searching: false
    property string errorText: ""

    // Items that the arrows move between
    property var navItems: []

    readonly property var gamepadHints: [
        { glyph: "A", label: qsTr("Press"), accent: true },
        { glyph: "Y", label: qsTr("Add"), },
        { glyph: "B", label: qsTr("Back") }
    ]

    function type(text) {
        addressField.insert(addressField.cursorPosition, text)
        errorText = ""
    }

    function add() {
        var address = addressField.text.trim()
        if (address === "" || searching) {
            return
        }

        searching = true
        errorText = ""
        UiSound.play("select")
        ComputerManager.addNewHostManually(address)
    }

    function addComplete(success, detectedPortBlocking) {
        searching = false

        if (success) {
            UiSound.play("connected")
            stackView.pop()
        }
        else {
            UiSound.play("error")
            errorText = detectedPortBlocking ?
                        qsTr("This network is blocking KanePlay. Streaming over the Internet may not work from here.") :
                        qsTr("No PC answered at this address. Check that it is on, that Sunshine runs on it, and the address.")
        }
    }

    function move(direction) {
        var next = SpatialNav.nearest(navItems, Window.activeFocusItem, direction, addPcView)
        if (next !== null) {
            next.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    Keys.onUpPressed: move("up")
    Keys.onDownPressed: move("down")
    Keys.onLeftPressed: move("left")
    Keys.onRightPressed: move("right")
    // Y on a gamepad
    Keys.onHangupPressed: add()

    StackView.onActivated: {
        ComputerManager.computerAddCompleted.connect(addComplete)
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            keypadRepeater.itemAt(0).forceActiveFocus(Qt.TabFocusReason)
        }
        else {
            addressField.forceActiveFocus()
        }
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding
        anchors.topMargin: 4
        anchors.bottomMargin: 24
        spacing: 28

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            RowLayout {
                spacing: 14

                KpButton {
                    id: backButton
                    round: true
                    implicitHeight: 44
                    iconName: "arrowLeft"
                    sound: "back"
                    onClicked: stackView.pop()

                    Component.onCompleted: addPcView.navItems.push(backButton)
                }

                Text {
                    text: qsTr("Add a PC")
                    font.family: Theme.displayFont
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    font.letterSpacing: -0.5
                    color: Theme.text
                }
            }

            Text {
                text: qsTr("PC address").toUpperCase()
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.3
                color: Theme.textSecondary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                TextField {
                    id: addressField
                    Layout.fillWidth: true
                    implicitHeight: 72
                    leftPadding: 24
                    rightPadding: 24
                    topPadding: 0
                    bottomPadding: 0
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.family: Theme.displayFont
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                    onTextChanged: addPcView.errorText = ""

                    Component.onCompleted: addPcView.navItems.push(addressField)

                    background: Rectangle {
                        radius: 20
                        color: Theme.surface
                        border.width: 2
                        border.color: addressField.activeFocus ? Theme.accent : Theme.border

                        // Example address, shown while the field is empty
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.verticalCenter: parent.verticalCenter
                            visible: addressField.text === ""
                            text: "192.168.1.20"
                            font: addressField.font
                            color: Theme.textTertiary
                        }
                    }

                    Keys.onReturnPressed: addPcView.add()
                    Keys.onEnterPressed: addPcView.add()
                }

                KpButton {
                    id: addButton
                    implicitHeight: 72
                    variant: "primary"
                    iconName: "plus"
                    text: qsTr("Add")
                    sound: ""
                    enabled: addressField.text.trim() !== "" && !addPcView.searching
                    onClicked: addPcView.add()

                    Component.onCompleted: addPcView.navItems.push(addButton)
                }
            }

            // Searching, or why it failed
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statusRow.implicitHeight + 28
                visible: addPcView.searching || addPcView.errorText !== ""
                radius: Theme.radius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                RowLayout {
                    id: statusRow
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    ArcSpinner {
                        size: 24
                        visible: addPcView.searching
                    }

                    KpIcon {
                        visible: !addPcView.searching
                        Layout.alignment: Qt.AlignTop
                        name: "info"
                        size: 20
                        color: Theme.danger
                    }

                    Text {
                        Layout.fillWidth: true
                        text: addPcView.searching ? qsTr("Looking for the PC…") : addPcView.errorText
                        font.pixelSize: 15
                        lineHeight: 1.3
                        color: addPcView.searching ? Theme.textSecondary : Theme.text
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Keypad for gamepads: an address is mostly digits and dots
            GridLayout {
                Layout.fillWidth: true
                columns: 5
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    id: keypadRepeater
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ".", ":", ".local", "⌫", qsTr("Clear")]
                    onItemAdded: function(index, item) { addPcView.navItems.push(item) }

                    KpButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 48
                        fontSize: 18
                        displayFont: true
                        text: modelData
                        sound: "move"
                        onClicked: {
                            if (modelData === "⌫") {
                                if (addressField.cursorPosition > 0) {
                                    addressField.remove(addressField.cursorPosition - 1, addressField.cursorPosition)
                                }
                            }
                            else if (index === 14) {
                                addressField.clear()
                            }
                            else {
                                addPcView.type(modelData)
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }

        // Where to find the address
        Rectangle {
            Layout.preferredWidth: 380
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 60
            implicitHeight: helpColumn.implicitHeight + 52
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                id: helpColumn
                anchors.fill: parent
                anchors.margins: 26
                spacing: 16

                Text {
                    text: qsTr("Where to find the address?")
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    color: Theme.text
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("1. On the PC, open the Sunshine web page.") + "\n" +
                          qsTr("2. The address is in the address bar of the browser, before :47990.")
                    font.pixelSize: 15
                    lineHeight: 1.4
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.border
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    KpIcon {
                        Layout.alignment: Qt.AlignTop
                        name: "wifi"
                        size: 20
                        color: Theme.accent2
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Away from home: use the Tailscale or ZeroTier address of the PC, or its domain name.")
                        font.pixelSize: 14
                        lineHeight: 1.4
                        color: Theme.textSecondary
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
