import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import StreamingPreferences 1.0
import SdlGamepadKeyNavigation 1.0
import UiSound 1.0

import "SpatialNav.js" as SpatialNav

// Every setting, as tiles grouped by category. The categories filter the grid
// (LT and RT on a gamepad) and the search field finds a setting by name.
FocusScope {
    id: advancedView
    objectName: qsTr("Advanced settings")

    property string filter: "all"
    property string search: ""

    // Items that the arrows move between
    property var navItems: []

    readonly property real screenX: Screen.virtualX
    readonly property real screenY: Screen.virtualY
    readonly property var hostWindow: Window.window

    function isInGrid(item) {
        for (var parentItem = item; parentItem !== null; parentItem = parentItem.parent) {
            if (parentItem === sections) {
                return true
            }
        }
        return false
    }

    readonly property var gamepadHints: [
        { glyph: "A", label: qsTr("Change"), accent: true },
        { glyph: "X", label: qsTr("Reset") },
        { glyph: "LT RT", label: qsTr("Category") },
        { glyph: "B", label: qsTr("Back") }
    ]

    readonly property int modifiedCount: settingsCatalog.settings.filter(function(setting) {
        return settingsCatalog.isAvailable(setting) && settingsCatalog.isModified(setting)
    }).length

    function matches(setting) {
        if (!settingsCatalog.isAvailable(setting) || (filter !== "all" && setting.category !== filter)) {
            return false
        }
        if (search === "") {
            return true
        }
        var needle = search.toLowerCase()
        return setting.label.toLowerCase().indexOf(needle) >= 0 || setting.desc.toLowerCase().indexOf(needle) >= 0
    }

    function sectionCount(category) {
        return settingsCatalog.settings.filter(function(setting) {
            return setting.category === category && matches(setting)
        }).length
    }

    function switchFilter(direction) {
        var index = 0
        for (var i = 0; i < settingsCatalog.categories.length; i++) {
            if (settingsCatalog.categories[i].key === filter) {
                index = i
            }
        }
        index = Math.max(0, Math.min(settingsCatalog.categories.length - 1, index + direction))
        if (settingsCatalog.categories[index].key !== filter) {
            UiSound.play("tab")
            filter = settingsCatalog.categories[index].key
            flick.contentY = 0
        }
    }

    function move(direction) {
        var next = SpatialNav.nearest(navItems, Window.activeFocusItem, direction, advancedView)
        if (next !== null) {
            next.forceActiveFocus(Qt.TabFocusReason)
        }
        else if (direction === "up") {
            settingsButton.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    function firstTile() {
        for (var i = 0; i < navItems.length; i++) {
            if (navItems[i].setting !== undefined && navItems[i].visible) {
                return navItems[i]
            }
        }
        return null
    }

    Keys.onUpPressed: move("up")
    Keys.onDownPressed: move("down")
    Keys.onLeftPressed: move("left")
    Keys.onRightPressed: move("right")
    // LT and RT on a gamepad
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_BracketLeft) {
            switchFilter(-1)
            event.accepted = true
        }
        else if (event.key === Qt.Key_BracketRight) {
            switchFilter(1)
            event.accepted = true
        }
    }

    StackView.onActivated: {
        var tile = firstTile()
        if (tile !== null && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            tile.forceActiveFocus(Qt.TabFocusReason)
        }
        else {
            forceActiveFocus()
        }
    }

    StackView.onDeactivating: {
        // Save the prefs so the Session can observe the changes
        StreamingPreferences.save()
    }

    Component.onDestruction: StreamingPreferences.save()

    SettingsCatalog {
        id: settingsCatalog
        screenX: advancedView.screenX
        screenY: advancedView.screenY
        onCustomRequested: function(key) { customDialog.openFor(key) }
    }

    // Keep the focused tile in view
    Connections {
        target: advancedView.hostWindow
        function onActiveFocusItemChanged() {
            var item = advancedView.hostWindow.activeFocusItem
            if (item === null || !advancedView.isInGrid(item)) {
                return
            }

            var top = item.mapToItem(flick.contentItem, 0, 0).y
            var margin = 24
            if (top - margin < flick.contentY) {
                scrollAnimation.to = Math.max(0, top - margin)
                scrollAnimation.restart()
            }
            else if (top + item.height + margin > flick.contentY + flick.height) {
                scrollAnimation.to = Math.min(flick.contentHeight - flick.height, top + item.height + margin - flick.height)
                scrollAnimation.restart()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding
        anchors.topMargin: 4
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            KpButton {
                id: backButton
                round: true
                implicitHeight: 44
                iconName: "arrowLeft"
                sound: "back"
                onClicked: stackView.pop()

                Component.onCompleted: advancedView.navItems.push(backButton)
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Advanced settings")
                font.family: Theme.displayFont
                font.pixelSize: 26
                font.weight: Font.Bold
                font.letterSpacing: -0.5
                color: Theme.text
                elide: Text.ElideRight
            }

            TextField {
                id: searchField
                Layout.preferredWidth: 340
                implicitHeight: 44
                leftPadding: 44
                rightPadding: 16
                topPadding: 0
                bottomPadding: 0
                color: Theme.text
                font.family: Theme.textFont
                font.pixelSize: 15
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: advancedView.search = text.trim()

                Component.onCompleted: advancedView.navItems.push(searchField)

                background: Rectangle {
                    radius: 22
                    color: Theme.surface
                    border.width: searchField.activeFocus ? 2 : 1
                    border.color: searchField.activeFocus ? Theme.accent : Theme.border

                    KpIcon {
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        size: 18
                        color: Theme.textSecondary
                    }

                    Text {
                        x: 44
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchField.text === ""
                        text: qsTr("Search for a setting")
                        font: searchField.font
                        color: Theme.textTertiary
                    }
                }

                // Down goes to the results, the other arrows move the cursor
                Keys.onDownPressed: {
                    var tile = advancedView.firstTile()
                    if (tile !== null) {
                        tile.forceActiveFocus(Qt.TabFocusReason)
                    }
                }
                Keys.onReturnPressed: {
                    var tile = advancedView.firstTile()
                    if (tile !== null) {
                        tile.forceActiveFocus(Qt.TabFocusReason)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            GamepadGlyph {
                glyph: "LT"
                visible: SdlGamepadKeyNavigation.getConnectedGamepads() > 0
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: settingsCatalog.categories
                    onItemAdded: function(index, item) { advancedView.navItems.push(item) }

                    FilterChip {
                        text: modelData.label
                        selected: advancedView.filter === modelData.key
                        onClicked: {
                            advancedView.filter = modelData.key
                            flick.contentY = 0
                        }
                    }
                }
            }

            GamepadGlyph {
                glyph: "RT"
                visible: SdlGamepadKeyNavigation.getConnectedGamepads() > 0
            }

            Row {
                visible: advancedView.modifiedCount > 0
                spacing: 8
                Layout.leftMargin: 12

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.accent2
                }

                Text {
                    text: qsTr("%n changed", "", advancedView.modifiedCount)
                    font.pixelSize: 13
                    color: Theme.textSecondary
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: sections.implicitHeight + 40
                boundsBehavior: Flickable.StopAtBounds

                NumberAnimation on contentY {
                    id: scrollAnimation
                    duration: Theme.durationStandard
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.easeOut
                }

                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: sections
                    width: flick.width - 12
                    spacing: 22

                    Repeater {
                        model: settingsCatalog.categories.slice(1)

                        ColumnLayout {
                            readonly property string category: modelData.key

                            Layout.fillWidth: true
                            spacing: 10
                            visible: advancedView.sectionCount(category) > 0

                            RowLayout {
                                spacing: 10

                                KpIcon {
                                    name: settingsCatalog.categoryIcons[modelData.key]
                                    size: 18
                                    color: Theme.accent
                                }

                                Text {
                                    text: modelData.label.toUpperCase()
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.3
                                    color: Theme.textSecondary
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: advancedView.width > 1100 ? 3 : 2
                                columnSpacing: 12
                                rowSpacing: 12

                                Repeater {
                                    model: settingsCatalog.settings.filter(function(setting) { return setting.category === modelData.key })
                                    onItemAdded: function(index, item) { advancedView.navItems.push(item) }

                                    SettingTile {
                                        id: settingTile
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        setting: modelData
                                        catalog: settingsCatalog
                                        visible: advancedView.matches(modelData)
                                        onOpenSheet: function(setting) { sheet.openFor(setting, settingTile) }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: sections.implicitHeight < 10
                text: qsTr("No setting matches “%1”.").arg(advancedView.search)
                font.pixelSize: 18
                color: Theme.textSecondary
            }

            // The list goes on below
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 56
                visible: flick.contentY + flick.height < flick.contentHeight - 8
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.055, 0.059, 0.075, 0) }
                    GradientStop { position: 1.0; color: Theme.background }
                }
            }
        }
    }

    SettingSheet {
        id: sheet
        catalog: settingsCatalog
    }

    CustomValueDialog {
        id: customDialog
        catalog: settingsCatalog
    }
}
