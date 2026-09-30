import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import UiSound 1.0

// The list of streaming profiles, dropping down from the profile bar of the
// settings: the user's profiles, the built-in ones, and a new profile made from
// the current settings. A applies a profile, X deletes one of the user's.
Popup {
    id: picker

    property var catalog
    // Key of the profile the current settings match, "" for none
    property string currentKey: ""
    // Item to give the focus back to once closed
    property Item returnFocus: null
    // Row waiting for a second press to be deleted, -1 for none
    property int confirmDelete: -1

    // The user wants a new profile made from the current settings
    signal createRequested()

    // Rows: section titles, profiles and the "new profile" action
    readonly property var rows: {
        var list = []
        var profiles = catalog.allProfiles
        var custom = profiles.filter(function(profile) { return profile.custom === true })
        if (custom.length > 0) {
            list.push({ type: "title", text: qsTr("My profiles") })
            custom.forEach(function(profile) { list.push({ type: "profile", profile: profile }) })
        }
        list.push({ type: "title", text: qsTr("%1 profiles").arg(embedded ? qsTr("Streaming") : "KanePlay") })
        profiles.filter(function(profile) { return profile.custom !== true })
                .forEach(function(profile) { list.push({ type: "profile", profile: profile }) })
        list.push({ type: "create" })
        return list
    }

    function openFrom(item) {
        returnFocus = item
        var position = item.mapToItem(parent, 0, item.height + 8)
        x = position.x
        y = position.y
        width = Math.min(600, item.width)
        confirmDelete = -1
        open()
    }

    function isSelectable(index) {
        return index >= 0 && index < rows.length && rows[index].type !== "title"
    }

    function step(direction) {
        confirmDelete = -1
        for (var index = list.currentIndex + direction; index >= 0 && index < rows.length; index += direction) {
            if (isSelectable(index)) {
                list.currentIndex = index
                UiSound.play("move")
                return
            }
        }
    }

    function activate(index) {
        var row = rows[index]
        if (row.type === "create") {
            UiSound.play("select")
            close()
            createRequested()
        }
        else if (confirmDelete === index) {
            UiSound.play("off")
            confirmDelete = -1
            catalog.removeCustomProfile(row.profile.index)
            list.currentIndex = Math.min(list.currentIndex, rows.length - 1)
            if (!isSelectable(list.currentIndex)) {
                step(1)
            }
        }
        else {
            UiSound.play("on")
            row.profile.apply()
            close()
        }
    }

    function askDelete(index) {
        var row = rows[index]
        if (row.type === "profile" && row.profile.custom === true) {
            UiSound.play("error")
            confirmDelete = index
        }
    }

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnPressOutside
    padding: 10
    height: Math.min(list.contentHeight + hints.height + topPadding + bottomPadding + 12, parent.height - y - 16)

    Overlay.modal: Rectangle {
        color: Qt.rgba(0.03, 0.035, 0.047, 0.45)
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        NumberAnimation { property: "scale"; from: Theme.motion ? 0.97 : 1; to: 1; duration: Theme.durationStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    }

    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast }
    }

    transformOrigin: Item.Top

    onOpened: {
        var index = -1
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].type === "profile" && rows[i].profile.key === currentKey) {
                index = i
            }
        }
        if (index < 0) {
            // Nothing matches: saving the current settings is the likely next step
            index = rows.length - 1
        }
        list.currentIndex = index
        list.positionViewAtIndex(index, ListView.Contain)
        list.forceActiveFocus(Qt.TabFocusReason)
    }

    onClosed: {
        if (returnFocus !== null) {
            returnFocus.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    background: Rectangle {
        radius: 24
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    contentItem: ColumnLayout {
        spacing: 6

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: picker.rows
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: Theme.durationFast
            keyNavigationEnabled: false

            Keys.onUpPressed: picker.step(-1)
            Keys.onDownPressed: picker.step(1)
            Keys.onReturnPressed: picker.activate(currentIndex)
            Keys.onEnterPressed: picker.activate(currentIndex)
            // X on a gamepad
            Keys.onMenuPressed: picker.askDelete(currentIndex)
            Keys.onDeletePressed: picker.askDelete(currentIndex)
            Keys.onEscapePressed: {
                if (picker.confirmDelete >= 0) {
                    picker.confirmDelete = -1
                }
                else {
                    UiSound.play("back")
                    picker.close()
                }
            }
            Keys.onBackPressed: picker.close()

            delegate: Item {
                id: row

                readonly property var entry: modelData
                readonly property bool current: ListView.isCurrentItem && list.activeFocus
                readonly property bool deleting: picker.confirmDelete === index
                // KaneMode: white when selected with the gamepad, dark text
                readonly property bool whiteFocus: Theme.whiteFocus && current && !deleting
                readonly property color tint: entry.type === "profile" ? entry.profile.color : Theme.accent2

                width: ListView.view.width
                height: entry.type === "title" ? 34 : 64

                // Section title
                Text {
                    visible: row.entry.type === "title"
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: row.entry.type === "title" ? row.entry.text.toUpperCase() : ""
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                    color: Theme.textTertiary
                }

                Rectangle {
                    visible: row.entry.type !== "title"
                    anchors.fill: parent
                    radius: 16
                    color: row.deleting ? Qt.rgba(1, 0.48, 0.44, 0.14) :
                           row.whiteFocus ? Theme.focusFill :
                           row.current ? Theme.raised : (mouseArea.containsMouse ? Theme.hover : "transparent")
                    border.width: row.current && !row.whiteFocus ? 2 : 0
                    border.color: row.deleting ? Theme.danger : row.tint

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            list.currentIndex = index
                            picker.activate(index)
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 16
                        spacing: 14

                        // Colored mark of the profile, or a plus to make one
                        Rectangle {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: 12
                            color: row.entry.type === "create" ? "transparent" : Qt.rgba(row.tint.r, row.tint.g, row.tint.b, 0.18)
                            border.width: row.entry.type === "create" ? 2 : 0
                            border.color: Theme.border

                            KpIcon {
                                anchors.centerIn: parent
                                name: row.entry.type === "create" ? "plus" : row.entry.type === "profile" ? row.entry.profile.icon : ""
                                size: 20
                                color: row.entry.type === "create" ? Theme.text : row.tint
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: row.entry.type === "create" ? qsTr("New profile from the current settings") :
                                      row.entry.type !== "profile" ? "" :
                                      row.deleting ? qsTr("Delete “%1”?").arg(row.entry.profile.label) : row.entry.profile.label
                                font.family: Theme.textFont
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: row.deleting ? Theme.danger : row.whiteFocus ? Theme.focusText : Theme.text
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.entry.type === "create" ? qsTr("Saved on this device, with a name and a color") :
                                      row.entry.type !== "profile" ? "" :
                                      row.deleting ? qsTr("A to delete, B to keep it") : row.entry.profile.summary
                                font.family: Theme.textFont
                                font.pixelSize: 13
                                color: row.whiteFocus ? Theme.focusMuted : Theme.textSecondary
                                elide: Text.ElideRight
                            }
                        }

                        // The profile in use
                        Rectangle {
                            visible: row.entry.type === "profile" && row.entry.profile.key === picker.currentKey && !row.deleting
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 12
                            color: row.tint

                            KpIcon {
                                anchors.centerIn: parent
                                name: "check"
                                size: 14
                                strokeWidth: 3
                                color: Theme.accentText
                            }
                        }

                        KpIcon {
                            visible: row.deleting
                            name: "trash"
                            size: 20
                            color: Theme.danger
                        }
                    }
                }
            }
        }

        Row {
            id: hints
            Layout.leftMargin: 12
            Layout.bottomMargin: 4
            spacing: 20

            GamepadHint {
                glyph: "A"
                accent: true
                label: picker.confirmDelete >= 0 ? qsTr("Delete") : qsTr("Choose")
            }

            GamepadHint {
                visible: list.currentIndex >= 0 && list.currentIndex < picker.rows.length &&
                         picker.rows[list.currentIndex].type === "profile" && picker.rows[list.currentIndex].profile.custom === true &&
                         picker.confirmDelete < 0
                glyph: "X"
                label: qsTr("Delete")
            }

            GamepadHint {
                glyph: "B"
                label: picker.confirmDelete >= 0 ? qsTr("Keep") : qsTr("Close")
            }
        }
    }
}
