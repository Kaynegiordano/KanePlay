import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import UiSound 1.0

// Side sheet to change one setting: a list of choices or a slider, with the
// settings that go with it underneath. A confirms, B cancels a slider change.
Popup {
    id: sheet

    property var setting: null
    property var catalog
    // Item to give the focus back to once closed
    property Item returnFocus: null
    // Value when opened, restored when a slider change is cancelled
    property var originalValue

    function openFor(newSetting, fromItem) {
        setting = newSetting
        returnFocus = fromItem
        originalValue = newSetting.get()
        open()
    }

    function cancel() {
        if (setting !== null && setting.type === "slider" && setting.get() !== originalValue) {
            setting.set(originalValue)
        }
        UiSound.play("back")
        close()
    }

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnPressOutside
    width: Math.min(480, parent.width - 32)
    height: parent.height - 32
    x: parent.width - width - 16
    y: 16
    padding: 32

    Overlay.modal: Rectangle {
        color: Qt.rgba(0.03, 0.035, 0.047, 0.55)
    }

    enter: Transition {
        NumberAnimation { property: "x"; from: sheet.parent.width; to: sheet.parent.width - sheet.width - 16; duration: Theme.motion ? Theme.durationAmple : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationStandard }
    }

    exit: Transition {
        NumberAnimation { property: "x"; to: sheet.parent.width; duration: Theme.motion ? Theme.durationStandard : 0; easing.type: Easing.InCubic }
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationStandard }
    }

    onOpened: {
        if (setting.type === "choice") {
            choiceList.forceActiveFocus(Qt.TabFocusReason)
        }
        else if (setting.type === "slider") {
            slider.forceActiveFocus(Qt.TabFocusReason)
        }
        else {
            boolTile.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    onClosed: {
        if (returnFocus !== null) {
            returnFocus.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    background: Rectangle {
        radius: 28
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    contentItem: FocusScope {
        focus: true

        Keys.onEscapePressed: sheet.cancel()
        Keys.onBackPressed: sheet.cancel()

        ColumnLayout {
            anchors.fill: parent
            spacing: 20
            visible: sheet.setting !== null

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                KpIcon {
                    name: sheet.setting !== null ? sheet.setting.icon : ""
                    size: 24
                    color: Theme.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: sheet.setting !== null ? sheet.setting.label : ""
                    font.family: Theme.displayFont
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                    color: Theme.text
                    elide: Text.ElideRight
                }

                KpButton {
                    round: true
                    implicitHeight: 40
                    iconName: "close"
                    iconSize: 18
                    focusPolicy: Qt.NoFocus
                    sound: ""
                    onClicked: sheet.cancel()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: sheet.setting !== null ? sheet.setting.desc : ""
                font.pixelSize: 15
                lineHeight: 1.3
                color: Theme.textSecondary
                wrapMode: Text.Wrap
            }

            // A choice: one row per option
            ListView {
                id: choiceList
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.maximumHeight: contentHeight
                visible: sheet.setting !== null && sheet.setting.type === "choice"
                clip: true
                spacing: 6
                keyNavigationEnabled: true
                highlightMoveDuration: Theme.durationFast
                boundsBehavior: Flickable.StopAtBounds
                model: sheet.setting !== null && sheet.setting.type === "choice" ? sheet.setting.options() : []

                onModelChanged: {
                    if (sheet.setting === null) {
                        return
                    }
                    var current = String(sheet.setting.get())
                    for (var i = 0; i < model.length; i++) {
                        if (String(model[i].value) === current) {
                            currentIndex = i
                            positionViewAtIndex(i, ListView.Contain)
                            return
                        }
                    }
                }

                onCurrentIndexChanged: {
                    if (activeFocus) {
                        UiSound.play("move")
                    }
                }

                function choose(index) {
                    var value = model[index].value
                    UiSound.play("select")
                    sheet.setting.set(value)
                    sheet.close()
                }

                Keys.onReturnPressed: choose(currentIndex)
                Keys.onEnterPressed: choose(currentIndex)
                Keys.onDownPressed: {
                    if (currentIndex === count - 1 && companions.count > 0) {
                        companions.itemAt(0).forceActiveFocus(Qt.TabFocusReason)
                    }
                    else {
                        incrementCurrentIndex()
                    }
                }

                delegate: ItemDelegate {
                    id: option

                    readonly property bool chosen: sheet.setting !== null && String(modelData.value) === String(sheet.setting.get())

                    width: ListView.view.width
                    height: 52
                    focusPolicy: Qt.NoFocus
                    padding: 0

                    background: Rectangle {
                        radius: 14
                        color: option.ListView.isCurrentItem && choiceList.activeFocus ? Theme.raised :
                               option.hovered ? Theme.hover : "transparent"
                        border.width: option.ListView.isCurrentItem && choiceList.activeFocus ? 2 : 0
                        border.color: Theme.accent
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14

                        // Radio mark
                        Rectangle {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            radius: 10
                            color: "transparent"
                            border.width: 2
                            border.color: option.chosen ? Theme.accent : Theme.border

                            Rectangle {
                                anchors.centerIn: parent
                                width: 10
                                height: 10
                                radius: 5
                                visible: option.chosen
                                color: Theme.accent
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            font.family: Theme.textFont
                            font.pixelSize: 16
                            font.weight: option.chosen ? Font.Bold : Font.DemiBold
                            color: Theme.text
                            elide: Text.ElideRight
                        }
                    }

                    onClicked: choiceList.choose(index)
                }
            }

            // A slider: the value large, then the slider
            ColumnLayout {
                Layout.fillWidth: true
                visible: sheet.setting !== null && sheet.setting.type === "slider"
                spacing: 16

                Text {
                    text: sheet.setting !== null && sheet.setting.type === "slider" ? sheet.setting.format(slider.value) : ""
                    font.family: Theme.displayFont
                    font.pixelSize: 52
                    font.weight: Font.Bold
                    font.letterSpacing: -2
                    color: Theme.text
                }

                Slider {
                    id: slider
                    Layout.fillWidth: true
                    from: sheet.setting !== null && sheet.setting.type === "slider" ? sheet.setting.from : 0
                    to: sheet.setting !== null && sheet.setting.type === "slider" ? sheet.setting.to() : 1
                    stepSize: sheet.setting !== null && sheet.setting.type === "slider" ? sheet.setting.step : 1
                    snapMode: Slider.SnapAlways
                    value: sheet.setting !== null && sheet.setting.type === "slider" ? sheet.setting.get() : 0

                    onMoved: sheet.setting.set(value)

                    Keys.onReturnPressed: {
                        UiSound.play("select")
                        sheet.close()
                    }
                    Keys.onEnterPressed: {
                        UiSound.play("select")
                        sheet.close()
                    }
                    Keys.onDownPressed: {
                        if (defaultButton.visible) {
                            defaultButton.forceActiveFocus(Qt.TabFocusReason)
                        }
                        else if (companions.count > 0) {
                            companions.itemAt(0).forceActiveFocus(Qt.TabFocusReason)
                        }
                    }

                    background: Rectangle {
                        x: slider.leftPadding
                        y: slider.topPadding + slider.availableHeight / 2 - height / 2
                        width: slider.availableWidth
                        height: 10
                        radius: 5
                        color: Theme.raised

                        Rectangle {
                            width: slider.visualPosition * parent.width
                            height: parent.height
                            radius: 5
                            color: Theme.accent
                        }
                    }

                    handle: Rectangle {
                        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                        y: slider.topPadding + slider.availableHeight / 2 - height / 2
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.text
                        border.width: 4
                        border.color: slider.activeFocus ? Theme.accent : Theme.textSecondary
                    }
                }

                // Back to the default value, like the bitrate that follows the resolution
                KpButton {
                    id: defaultButton
                    visible: sheet.setting !== null && sheet.setting.type === "slider" && sheet.setting.def !== undefined &&
                             catalog.isModified(sheet.setting)
                    implicitHeight: 42
                    fontSize: 14
                    text: sheet.setting !== null && sheet.setting.type === "slider" ?
                              qsTr("Default: %1").arg(sheet.setting.format(sheet.setting.def())) : ""
                    onClicked: {
                        catalog.reset(sheet.setting)
                        slider.value = sheet.setting.get()
                    }

                    KeyNavigation.up: slider
                    Keys.onDownPressed: {
                        if (companions.count > 0) {
                            companions.itemAt(0).forceActiveFocus(Qt.TabFocusReason)
                        }
                    }
                }
            }

            // On or off
            SettingTile {
                id: boolTile
                Layout.fillWidth: true
                visible: sheet.setting !== null && sheet.setting.type === "bool"
                setting: sheet.setting !== null && sheet.setting.type === "bool" ? sheet.setting : catalog.settings[0]
                catalog: sheet.catalog
                compact: true

                Keys.onDownPressed: {
                    if (companions.count > 0) {
                        companions.itemAt(0).forceActiveFocus(Qt.TabFocusReason)
                    }
                }
            }

            // Settings that go with this one
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: companions.count > 0

                Repeater {
                    id: companions
                    model: {
                        if (sheet.setting === null || sheet.setting.companions === undefined) {
                            return []
                        }
                        return sheet.setting.companions.map(function(key) { return catalog.find(key) })
                                                       .filter(function(companion) { return companion !== null && catalog.isAvailable(companion) })
                    }

                    SettingTile {
                        Layout.fillWidth: true
                        setting: modelData
                        catalog: sheet.catalog
                        compact: true
                        // Companions are simple settings changed in place
                        onOpenSheet: function(companion) { sheet.openFor(companion, sheet.returnFocus) }

                        Keys.onUpPressed: {
                            if (index > 0) {
                                companions.itemAt(index - 1).forceActiveFocus(Qt.TabFocusReason)
                            }
                            else if (sheet.setting.type === "choice") {
                                choiceList.forceActiveFocus(Qt.TabFocusReason)
                            }
                            else if (sheet.setting.type === "slider") {
                                (defaultButton.visible ? defaultButton : slider).forceActiveFocus(Qt.TabFocusReason)
                            }
                            else {
                                boolTile.forceActiveFocus(Qt.TabFocusReason)
                            }
                        }
                        Keys.onDownPressed: {
                            if (index < companions.count - 1) {
                                companions.itemAt(index + 1).forceActiveFocus(Qt.TabFocusReason)
                            }
                        }
                    }
                }
            }

            // Pushes the hints down, unless the list of choices already takes the room
            Item {
                Layout.fillHeight: !choiceList.visible
            }

            Row {
                spacing: 20

                GamepadHint {
                    visible: sheet.setting !== null && sheet.setting.type === "slider"
                    glyph: "◀ ▶"
                    label: qsTr("Adjust")
                }

                GamepadHint {
                    glyph: "A"
                    accent: true
                    label: qsTr("Confirm")
                }

                GamepadHint {
                    glyph: "B"
                    label: sheet.setting !== null && sheet.setting.type === "slider" ? qsTr("Cancel") : qsTr("Close")
                }
            }
        }
    }
}
