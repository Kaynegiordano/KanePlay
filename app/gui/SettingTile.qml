import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import UiSound 1.0

// One setting of the advanced settings (or of a side sheet): its name, what it does,
// and its switch or value. A changes it, X puts it back to its default value.
AbstractButton {
    id: tile

    property var setting
    property var catalog
    // Shorter tiles, for the settings listed under another one in its side sheet
    property bool compact: false

    // Asks the view to open the side sheet of this setting
    signal openSheet(var setting)

    readonly property bool isEnabled: catalog.isEnabled(setting)
    readonly property bool modified: catalog.isModified(setting)
    readonly property bool cycles: setting.type === "choice" && !setting.sheet && setting.options().length <= 4

    implicitHeight: compact ? 68 : 80
    leftPadding: 14
    rightPadding: 14
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true
    hoverEnabled: true

    function activate() {
        if (!isEnabled) {
            if (setting.unlock === undefined) {
                UiSound.play("error")
                return
            }
            setting.unlock()
            if (!catalog.isEnabled(setting)) {
                UiSound.play("error")
                return
            }
        }

        if (setting.type === "action") {
            UiSound.play(setting.run() ? "select" : "error")
        }
        else if (setting.type === "bool") {
            setting.set(!setting.get())
            UiSound.play(setting.get() ? "on" : "off")
        }
        else if (cycles) {
            catalog.cycle(setting, 1)
            UiSound.play("select")
        }
        else {
            UiSound.play("select")
            openSheet(setting)
        }
    }

    function resetToDefault() {
        if (isEnabled && modified) {
            catalog.reset(setting)
            UiSound.play("off")
        }
    }

    onClicked: activate()
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()
    Keys.onMenuPressed: resetToDefault()

    // KaneMode: the focused tile is white, like its settings rows
    readonly property bool whiteFocus: Theme.whiteFocus && activeFocus

    background: Rectangle {
        radius: Theme.radius
        color: tile.whiteFocus ? Theme.focusFill : tile.activeFocus ? Theme.raised : (tile.hovered ? Theme.hover : Theme.surface)
        border.width: 2
        border.color: tile.activeFocus && !tile.whiteFocus ? Theme.accent : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.durationFast }
        }
    }

    contentItem: RowLayout {
        spacing: 14
        opacity: tile.isEnabled ? 1 : 0.6

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: !tile.modified
                    text: tile.setting.label
                    font.family: Theme.textFont
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: tile.whiteFocus ? Theme.focusText : Theme.text
                    elide: Text.ElideRight
                }

                // Changed from its default value
                Rectangle {
                    visible: tile.modified
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.accent2
                }

                Item {
                    visible: tile.modified
                    Layout.fillWidth: true
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: !tile.isEnabled && catalog.lockReason(tile.setting) !== "" ? catalog.lockReason(tile.setting) : tile.setting.desc
                font.family: Theme.textFont
                font.pixelSize: 13
                color: tile.whiteFocus ? Theme.focusMuted : !tile.isEnabled && tile.activeFocus ? Theme.accent2 : Theme.textSecondary
                // The reason a setting is off, and how to turn it on, may take two lines
                wrapMode: tile.isEnabled ? Text.NoWrap : Text.Wrap
                maximumLineCount: tile.isEnabled ? 1 : 2
                lineHeight: 0.95
                elide: Text.ElideRight
            }
        }

        KpIcon {
            visible: !tile.isEnabled
            name: "lock"
            size: 16
            color: Theme.textTertiary
        }

        KpSwitch {
            visible: tile.setting.type === "bool"
            checked: tile.setting.type === "bool" && tile.setting.get()
        }

        ValuePill {
            visible: tile.cycles
            text: tile.setting.type === "choice" ? catalog.valueText(tile.setting) : ""
            onPrevious: {
                if (tile.isEnabled) {
                    catalog.cycle(tile.setting, -1)
                    UiSound.play("select")
                }
            }
            onNext: {
                if (tile.isEnabled) {
                    catalog.cycle(tile.setting, 1)
                    UiSound.play("select")
                }
            }
        }

        // Opens another app
        Row {
            visible: tile.setting.type === "action"
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tile.setting.actionLabel !== undefined ? tile.setting.actionLabel : qsTr("Open")
                font.family: Theme.textFont
                font.pixelSize: 14
                font.weight: Font.Bold
                color: Theme.accent
            }

            KpIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "right"
                size: 16
                color: Theme.accent
            }
        }

        // Values chosen in the side sheet
        Row {
            visible: tile.setting.type === "slider" || (tile.setting.type === "choice" && !tile.cycles)
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tile.setting.type === "slider" || tile.setting.type === "choice" ? catalog.valueText(tile.setting) : ""
                font.family: Theme.textFont
                font.pixelSize: 14
                font.weight: Font.Bold
                color: tile.whiteFocus ? Theme.focusText : Theme.text
            }

            KpIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "right"
                size: 16
                color: tile.whiteFocus ? Theme.focusMuted : Theme.textTertiary
            }
        }
    }
}
