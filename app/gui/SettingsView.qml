import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import StreamingPreferences 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import UiSound 1.0

import "SpatialNav.js" as SpatialNav

// Settings: a streaming profile to start from, then the settings that matter most
// as tiles showing their value. A tile opens its side sheet; the rest of the
// settings are in the advanced settings.
FocusScope {
    id: settingsView
    objectName: qsTr("Settings")

    readonly property var gamepadHints: [
        { glyph: "A", label: qsTr("Change"), accent: true },
        { glyph: "Y", label: qsTr("Advanced settings") },
        { glyph: "B", label: qsTr("Back") }
    ]

    // The profile the current settings match, if any: the user's first
    readonly property var currentProfile: {
        var profiles = settingsCatalog.allProfiles
        for (var i = 0; i < profiles.length; i++) {
            if (profiles[i].matches()) {
                return profiles[i]
            }
        }
        return null
    }

    // Items that the arrows move between
    property var navItems: []

    // Where the window is, to find its display (see SettingsCatalog)
    readonly property real screenX: Screen.virtualX
    readonly property real screenY: Screen.virtualY

    function move(direction) {
        var next = SpatialNav.nearest(navItems, Window.activeFocusItem, direction, settingsView)
        if (next !== null) {
            next.forceActiveFocus(Qt.TabFocusReason)
        }
        else if (direction === "up") {
            settingsButton.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    function openAdvanced() {
        UiSound.play("select")
        stackView.push("qrc:/gui/AdvancedSettingsView.qml")
    }

    function openSheet(key, fromItem) {
        UiSound.play("select")
        sheet.openFor(settingsCatalog.find(key), fromItem)
    }

    Keys.onUpPressed: move("up")
    Keys.onDownPressed: move("down")
    Keys.onLeftPressed: move("left")
    Keys.onRightPressed: move("right")
    // Y on a gamepad
    Keys.onHangupPressed: openAdvanced()

    StackView.onActivated: {
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            profileBar.forceActiveFocus(Qt.TabFocusReason)
        }
        else {
            forceActiveFocus()
        }
    }

    StackView.onDeactivating: {
        // Save the prefs so the Session can observe the changes
        StreamingPreferences.save()
    }

    Component.onDestruction: {
        // Also save preferences on destruction, since we won't get a
        // deactivating callback if the user just closes KanePlay
        StreamingPreferences.save()
    }

    SettingsCatalog {
        id: settingsCatalog
        screenX: settingsView.screenX
        screenY: settingsView.screenY
        onCustomRequested: function(key) { customDialog.openFor(key) }
    }

    // The streaming profile in use, in its color. It opens the list of profiles.
    component ProfileBar: AbstractButton {
        id: bar

        property var profile: null
        readonly property color tint: profile !== null ? profile.color : Theme.accent2

        Layout.fillWidth: true
        implicitHeight: 96
        leftPadding: 20
        rightPadding: 24
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true

        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()

        scale: pressed && Theme.motion ? 0.99 : 1

        Behavior on scale {
            NumberAnimation { duration: Theme.durationFast }
        }

        // KaneMode: white when selected with the gamepad, dark text
        readonly property bool whiteFocus: Theme.whiteFocus && activeFocus

        background: Rectangle {
            radius: Theme.kaneMode ? Theme.radiusLarge : 22
            color: bar.whiteFocus ? Theme.focusFill : bar.hovered || bar.activeFocus ? Theme.raised : Theme.surface
            border.width: 2
            border.color: bar.whiteFocus ? Theme.focusFill : bar.activeFocus ? bar.tint : Qt.rgba(bar.tint.r, bar.tint.g, bar.tint.b, 0.35)

            Behavior on color {
                ColorAnimation { duration: Theme.durationStandard }
            }
            Behavior on border.color {
                ColorAnimation { duration: Theme.durationStandard }
            }

            // A wash of the profile color from the left
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 20
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(bar.tint.r, bar.tint.g, bar.tint.b, 0.22) }
                    GradientStop { position: 0.55; color: Qt.rgba(bar.tint.r, bar.tint.g, bar.tint.b, 0) }
                }
            }
        }

        contentItem: RowLayout {
            spacing: 18

            Rectangle {
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                radius: 16
                color: Qt.rgba(bar.tint.r, bar.tint.g, bar.tint.b, 0.2)

                KpIcon {
                    anchors.centerIn: parent
                    name: bar.profile !== null ? bar.profile.icon : "sliders"
                    size: 26
                    color: bar.tint
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    spacing: 10

                    Text {
                        text: bar.profile !== null ? bar.profile.label : qsTr("Custom settings")
                        font.family: Theme.displayFont
                        font.pixelSize: 21
                        font.weight: Font.Bold
                        font.letterSpacing: -0.4
                        color: Theme.text
                    }

                    Chip {
                        visible: bar.profile !== null && bar.profile.custom === true
                        text: qsTr("My profile")
                        textColor: bar.tint
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: bar.profile !== null ? bar.profile.summary : qsTr("They match no profile: A to save them as one")
                    font.family: Theme.textFont
                    font.pixelSize: 14
                    color: Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            Text {
                text: qsTr("Change profile")
                font.family: Theme.textFont
                font.pixelSize: 15
                font.weight: Font.Bold
                color: bar.whiteFocus ? Theme.focusText : bar.activeFocus ? Theme.text : Theme.textSecondary
            }

            KpIcon {
                name: "chevron"
                size: 20
                color: bar.whiteFocus ? Theme.focusMuted : bar.activeFocus ? bar.tint : Theme.textSecondary
            }
        }
    }

    // One of the main settings, its value shown large
    component ValueTile: AbstractButton {
        id: valueTile

        property string settingKey
        property string iconName
        property string label
        property string value
        property string sub
        property color subColor: Theme.textSecondary
        // Fill of the small gauge, -1 for none
        property real gauge: -1

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 148
        padding: 18
        topPadding: 16
        bottomPadding: 16
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true

        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()

        scale: pressed && Theme.motion ? 0.98 : 1

        Behavior on scale {
            NumberAnimation { duration: Theme.durationFast }
        }

        // KaneMode: white when selected with the gamepad, dark text
        readonly property bool whiteFocus: Theme.whiteFocus && activeFocus

        background: Rectangle {
            radius: Theme.kaneMode ? Theme.radiusLarge : 20
            color: valueTile.whiteFocus ? Theme.focusFill : valueTile.activeFocus ? Theme.raised : (valueTile.hovered ? Theme.hover : Theme.surface)
            border.width: 2
            border.color: valueTile.activeFocus && !valueTile.whiteFocus ? Theme.accent : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.durationFast }
            }
        }

        contentItem: ColumnLayout {
            spacing: 10

            RowLayout {
                spacing: 10

                KpIcon {
                    name: valueTile.iconName
                    size: 18
                    color: valueTile.whiteFocus ? Theme.focusMuted : Theme.textSecondary
                }

                Text {
                    Layout.fillWidth: true
                    text: valueTile.label.toUpperCase()
                    font.family: Theme.textFont
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.letterSpacing: 0.9
                    color: valueTile.whiteFocus ? Theme.focusMuted : Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.fillWidth: true
                text: valueTile.value
                font.family: Theme.displayFont
                font.pixelSize: 24
                font.weight: Font.DemiBold
                font.letterSpacing: -0.5
                color: valueTile.whiteFocus ? Theme.focusText : Theme.text
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 16
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                visible: valueTile.gauge >= 0
                implicitHeight: 6
                radius: 3
                color: Theme.background

                Rectangle {
                    width: parent.width * Math.max(0.02, Math.min(1, valueTile.gauge))
                    height: parent.height
                    radius: 3
                    color: Theme.accent

                    Behavior on width {
                        NumberAnimation { duration: Theme.durationStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }

            Text {
                Layout.fillWidth: true
                text: valueTile.sub
                font.family: Theme.textFont
                font.pixelSize: 13
                color: valueTile.subColor
                elide: Text.ElideRight
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding
        anchors.topMargin: 4
        anchors.bottomMargin: 20
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: qsTr("Streaming profile").toUpperCase()
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.3
                color: Theme.textSecondary
            }

            Item {
                Layout.fillWidth: true
            }

            KpButton {
                id: aboutButton
                variant: "ghost"
                implicitHeight: 38
                leftPadding: 16
                rightPadding: 16
                fontSize: 14
                text: qsTr("About")
                iconName: "info"
                iconSize: 16
                onClicked: stackView.push("qrc:/gui/AboutView.qml")

                Component.onCompleted: settingsView.navItems.push(aboutButton)
            }

            KpButton {
                id: advancedButton
                variant: "ghost"
                implicitHeight: 38
                leftPadding: 16
                rightPadding: 16
                fontSize: 14
                text: qsTr("Advanced settings")
                iconName: "sliders"
                iconSize: 16
                onClicked: settingsView.openAdvanced()

                Component.onCompleted: settingsView.navItems.push(advancedButton)
            }
        }

        ProfileBar {
            id: profileBar
            profile: settingsView.currentProfile
            onClicked: {
                UiSound.play("select")
                profilePicker.openFrom(profileBar)
            }

            Component.onCompleted: settingsView.navItems.push(profileBar)
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
                id: tileRepeater
                model: 8
                onItemAdded: function(index, item) { settingsView.navItems.push(item) }

                ValueTile {
                    id: valueTileItem

                    readonly property var tiles: [
                        {
                            key: "resolution", icon: "monitor", label: qsTr("Resolution"),
                            value: StreamingPreferences.autoResolution ? qsTr("Auto") : StreamingPreferences.height + "p",
                            sub: StreamingPreferences.autoResolution ? qsTr("%1p on this display").arg(StreamingPreferences.height)
                                                                     : StreamingPreferences.width + " × " + StreamingPreferences.height
                        },
                        {
                            key: "fps", icon: "layers", label: qsTr("Frame rate"),
                            value: StreamingPreferences.autoFps ? qsTr("Auto") : qsTr("%1 FPS").arg(StreamingPreferences.fps),
                            sub: StreamingPreferences.autoFps ? qsTr("Follows the display") : qsTr("Set by hand")
                        },
                        {
                            key: "bitrate", icon: "gauge", label: qsTr("Bitrate"),
                            value: qsTr("%1 Mb/s").arg(Math.round(StreamingPreferences.bitrateKbps / 100) / 10),
                            sub: StreamingPreferences.autoAdjustBitrate ? qsTr("Follows the resolution") : qsTr("Set by hand"),
                            gauge: StreamingPreferences.bitrateKbps / StreamingPreferences.getMaxBitrate(StreamingPreferences.unlockBitrate)
                        },
                        {
                            key: "codec", icon: "image", label: qsTr("Codec"),
                            value: settingsCatalog.valueText(settingsCatalog.find("codec")),
                            sub: StreamingPreferences.videoCodecConfig === StreamingPreferences.VCC_AUTO ? qsTr("The best one available") : qsTr("Forced")
                        },
                        {
                            key: "hdr", icon: "sliders", label: qsTr("HDR"),
                            value: SystemProperties.supportsHdr && StreamingPreferences.enableHdr ? qsTr("On") : qsTr("Off"),
                            sub: SystemProperties.supportsHdr ? qsTr("Needs an HDR display") : qsTr("Not supported here")
                        },
                        {
                            key: "vsync", icon: "check", label: qsTr("V-Sync"),
                            value: StreamingPreferences.enableVsync ? qsTr("On") : qsTr("Off"),
                            sub: !StreamingPreferences.enableVsync ? qsTr("Lowest latency") :
                                 StreamingPreferences.enableVrr ? qsTr("With VRR") :
                                 StreamingPreferences.framePacing ? qsTr("With frame pacing") : qsTr("No tearing")
                        },
                        {
                            key: "audio", icon: "volume", label: qsTr("Audio"),
                            value: settingsCatalog.valueText(settingsCatalog.find("audio")),
                            sub: StreamingPreferences.playAudioOnHost ? qsTr("Also on the host PC") : qsTr("Host PC muted")
                        },
                        {
                            key: "gamepadLayout", icon: "gamepad", label: qsTr("Gamepad"),
                            value: StreamingPreferences.swapFaceButtons ? "Nintendo" : "Xbox",
                            sub: StreamingPreferences.gamepadMouse ? qsTr("Mouse with Start") : qsTr("No mouse mode")
                        }
                    ]

                    onClicked: settingsView.openSheet(settingKey, valueTileItem)

                    settingKey: tiles[index].key
                    iconName: tiles[index].icon
                    label: tiles[index].label
                    value: tiles[index].value
                    sub: tiles[index].sub
                    subColor: tiles[index].subColor !== undefined ? tiles[index].subColor : Theme.textSecondary
                    gauge: tiles[index].gauge !== undefined ? tiles[index].gauge : -1
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }

    SettingSheet {
        id: sheet
        catalog: settingsCatalog
    }

    ProfilePicker {
        id: profilePicker
        catalog: settingsCatalog
        currentKey: settingsView.currentProfile !== null ? settingsView.currentProfile.key : ""
        onCreateRequested: profileDialog.openNew()
    }

    ProfileDialog {
        id: profileDialog
        catalog: settingsCatalog
        onClosed: Qt.callLater(function() { profileBar.forceActiveFocus(Qt.TabFocusReason) })
    }

    CustomValueDialog {
        id: customDialog
        catalog: settingsCatalog
    }
}
