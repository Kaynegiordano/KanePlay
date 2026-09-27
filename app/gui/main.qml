import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2
import QtQuick.Controls.Material 2.2

import ComputerManager 1.0
import AutoUpdateChecker 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import UiSound 1.0

ApplicationWindow {
    property bool pollingActive: false

    // Set by SettingsView to force the back operation to pop all
    // pages except the initial view. This is required when doing
    // a retranslate() because AppView breaks for some reason.
    property bool clearOnBack: false

    id: window
    title: "KanePlay"
    width: 1280
    height: 720

    color: Theme.background
    // Windows 11 UI font for every control. Other systems fall back to their default.
    font.family: Theme.textFont

    background: Rectangle {
        color: Theme.background
    }

    Material.theme: Material.Dark
    Material.accent: Theme.accent
    Material.primary: Theme.surfaceAlt
    Material.background: Theme.surface
    Material.foreground: Theme.text

    // The app library of the PC we're browsing, if any, for the top bar
    property var libraryView: null
    property int connectedGamepads: 0

    // Tabs of the top bar: 0 home, 1 library, 2 settings, -1 another page
    readonly property var homeView: stackView.depth > 0 && stackView.get(0) instanceof PcView ? stackView.get(0) : null
    readonly property int currentTab: stackView.currentItem instanceof PcView ||
                                      stackView.currentItem instanceof AddPcView ? 0 :
                                      stackView.currentItem instanceof AppView ||
                                      stackView.currentItem instanceof SessionSummaryView ? 1 :
                                      stackView.currentItem instanceof SettingsView ||
                                      stackView.currentItem instanceof AdvancedSettingsView ||
                                      stackView.currentItem instanceof AboutView ? 2 : -1
    readonly property bool canOpenLibrary: libraryView !== null || (homeView !== null && homeView.canOpenLibrary)

    function selectTab(tab)
    {
        if (tab === 0) {
            if (stackView.depth > 1) {
                stackView.pop(null)
                clearOnBack = false
            }
        }
        else if (tab === 1) {
            if (libraryView !== null) {
                if (stackView.currentItem !== libraryView) {
                    stackView.pop(libraryView)
                }
            }
            else if (homeView !== null && homeView.canOpenLibrary) {
                homeView.openLibrary()
            }
        }
        else if (tab === 2) {
            navigateTo("qrc:/gui/SettingsView.qml", SettingsView)
        }
    }

    // LB and RB (Page Up and Page Down) move between the tabs
    function switchTab(direction)
    {
        var tab = (currentTab < 0 ? 0 : currentTab) + direction
        if (tab === 1 && !canOpenLibrary) {
            tab += direction
        }
        if (tab < 0 || tab > 2 || tab === currentTab) {
            return
        }

        UiSound.play("tab")
        selectTab(tab)
    }

    Shortcut {
        sequence: "PgUp"
        onActivated: switchTab(-1)
    }

    Shortcut {
        sequence: "PgDown"
        onActivated: switchTab(1)
    }

    function openAddPc()
    {
        if (!(stackView.currentItem instanceof AddPcView)) {
            UiSound.play("select")
            stackView.push("qrc:/gui/AddPcView.qml")
        }
    }

    // Keyboard and gamepad navigation ticks softly
    onActiveFocusItemChanged: {
        if (!introLoader.active) {
            UiSound.focusMoved()
        }
    }

    function findLibraryView() {
        return stackView.find(function(item, index) {
            return item instanceof AppView
        })
    }

    // This function runs prior to creation of the initial StackView item
    function doEarlyInit() {
        SdlGamepadKeyNavigation.enable()
    }

    // Show the window according to the user's preferences
    function showWindow() {
        if (SystemProperties.hasDesktopEnvironment) {
            if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_MAXIMIZED) {
                window.showMaximized()
            }
            else if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_FULLSCREEN) {
                window.showFullScreen()
            }
            else {
                window.show()
            }
        } else {
            window.showFullScreen()
        }
    }

    Component.onCompleted: {
        // Once the intro is over, if it plays
        if (!introLoader.active) {
            showWindow()
        }

        // Display any modal dialogs for configuration warnings
        if (runConfigChecks) {
            if (SystemProperties.isWow64) {
                wow64Dialog.open()
            }

            // Hardware acceleration and unmapped gamepads are checked asynchronously
            SystemProperties.hasHardwareAccelerationChanged.connect(hasHardwareAccelerationChanged)
            SystemProperties.unmappedGamepadsChanged.connect(hasUnmappedGamepadsChanged)
            SystemProperties.startAsyncLoad()
        }
    }

    function hasHardwareAccelerationChanged() {
        if (!SystemProperties.hasHardwareAcceleration && StreamingPreferences.videoDecoderSelection !== StreamingPreferences.VDS_FORCE_SOFTWARE) {
            if (SystemProperties.isRunningXWayland) {
                xWaylandDialog.open()
            }
            else {
                noHwDecoderDialog.open()
            }
        }
    }

    function hasUnmappedGamepadsChanged() {
        if (SystemProperties.unmappedGamepads) {
            unmappedGamepadDialog.unmappedGamepads = SystemProperties.unmappedGamepads
            unmappedGamepadDialog.open()
        }
    }

    // It would be better to use TextMetrics here, but it always lays out
    // the text slightly more compactly than real Text does in ToolTip,
    // causing unexpected line breaks to be inserted
    Text {
        id: tooltipTextLayoutHelper
        visible: false
        font: ToolTip.toolTip.font
        text: ToolTip.toolTip.text
    }

    // This configures the maximum width of the singleton attached QML ToolTip. If left unconstrained,
    // it will never insert a line break and just extend on forever.
    ToolTip.toolTip.contentWidth: Math.min(tooltipTextLayoutHelper.width, 400)

    function goBack() {
        if (clearOnBack) {
            // Pop all items except the first one
            stackView.pop(null)
            clearOnBack = false
        }
        else {
            stackView.pop()
        }
    }

    StackView {
        id: stackView
        anchors.fill: parent
        focus: true

        // Pages slide in by 24 px while fading, the way tabs change in the design
        pushEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            NumberAnimation { property: "x"; from: Theme.motion ? 24 : 0; to: 0; duration: Theme.durationStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
        pushExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
        }
        popEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            NumberAnimation { property: "x"; from: Theme.motion ? -24 : 0; to: 0; duration: Theme.durationStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
        popExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
        }

        Component.onCompleted: {
            // Perform our early initialization before constructing
            // the initial view and pushing it to the StackView
            doEarlyInit()
            push(initialView)
        }

        onCurrentItemChanged: {
            // Ensure focus travels to the next view when going back
            if (currentItem) {
                currentItem.forceActiveFocus()
            }

            libraryView = findLibraryView()
        }

        Keys.onEscapePressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onBackPressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onMenuPressed: {
            settingsButton.clicked()
        }

        // This is a keypress we've reserved for letting the
        // SdlGamepadKeyNavigation object tell us to show settings
        // when Menu is consumed by a focused control.
        Keys.onHangupPressed: {
            settingsButton.clicked()
        }
    }

    // This timer keeps us polling for 5 minutes of inactivity
    // to allow the user to work with Moonlight on a second display
    // while dealing with configuration issues. This will ensure
    // machines come online even if the input focus isn't on Moonlight.
    Timer {
        id: inactivityTimer
        interval: 5 * 60000
        onTriggered: {
            if (!active && pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
    }

    onVisibleChanged: {
        // When we become invisible while streaming is going on,
        // stop polling immediately.
        if (!visible) {
            inactivityTimer.stop()

            if (pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
        else if (active) {
            // When we become visible and active again, start polling
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onActiveChanged: {
        if (active) {
            // Stop the inactivity timer
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }
        else {
            // Start the inactivity timer to stop polling
            // if focus does not return within a few minutes.
            inactivityTimer.restart()
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    function navigateTo(url, objectType)
    {
        var existingItem = stackView.find(function(item, index) {
            return item instanceof objectType
        })

        if (existingItem !== null) {
            // Pop to the existing item
            stackView.pop(existingItem)
        }
        else {
            // Create a new item
            stackView.push(url)
        }
    }

    header: Item {
        id: toolBar
        height: 76

        // Logo and name
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.pagePadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Image {
                anchors.verticalCenter: parent.verticalCenter
                source: "qrc:/res/kaneplay.svg"
                sourceSize.width: 34
                sourceSize.height: 34
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Hidden on narrow windows so the tabs keep their room
                visible: toolBar.width > 960
                text: "KanePlay"
                font.family: Theme.displayFont
                font.pixelSize: 19
                font.weight: Font.Bold
                font.letterSpacing: -0.4
                color: Theme.text
            }
        }

        // Tabs, switched with LB and RB on a gamepad
        Row {
            anchors.centerIn: parent
            spacing: 10

            GamepadGlyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: connectedGamepads > 0
                glyph: "LB"
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: tabRow.implicitWidth + 8
                height: 48
                radius: 24
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: 4

                    NavPill {
                        id: pcPill
                        text: qsTr("Home")
                        selected: currentTab === 0
                        onClicked: selectTab(0)
                    }

                    NavPill {
                        id: libraryPill
                        text: qsTr("Library")
                        enabled: canOpenLibrary
                        opacity: enabled ? 1 : 0.4
                        selected: currentTab === 1
                        onClicked: selectTab(1)
                    }

                    NavPill {
                        id: settingsButton
                        text: qsTr("Settings")
                        selected: currentTab === 2
                        onClicked: selectTab(2)

                        Shortcut {
                            id: settingsShortcut
                            sequence: StandardKey.Preferences
                            onActivated: settingsButton.clicked()
                        }
                    }
                }
            }

            GamepadGlyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: connectedGamepads > 0
                glyph: "RB"
            }
        }

        // Actions
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.pagePadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            KpButton {
                property string browserUrl: ""

                id: updateButton
                round: true
                variant: "primary"
                iconName: "download"
                implicitHeight: 44
                sound: ""

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered

                // Invisible until we get a callback notifying us that
                // an update is available
                visible: false

                onClicked: updateDialog.open()

                function updateAvailable(version, url)
                {
                    ToolTip.text = qsTr("Update available for KanePlay: version %1").arg(version)
                    updateButton.browserUrl = url
                    updateButton.visible = true
                    updateDialog.version = version
                    updateDialog.browserUrl = url
                    UiSound.play("notify")
                }

                Component.onCompleted: {
                    AutoUpdateChecker.onUpdateAvailable.connect(updateAvailable)
                    AutoUpdateChecker.start()
                }

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            KpButton {
                id: addPcButton
                visible: currentTab === 0
                round: true
                iconName: "plus"
                implicitHeight: 44

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add PC manually") + (newPcShortcut.nativeText ? (" ("+newPcShortcut.nativeText+")") : "")

                Shortcut {
                    id: newPcShortcut
                    sequence: StandardKey.New
                    onActivated: addPcButton.clicked()
                }

                onClicked: openAddPc()

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            KpButton {
                id: helpButton
                visible: SystemProperties.hasBrowser
                round: true
                iconName: "help"
                implicitHeight: 44

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Help") + (helpShortcut.nativeText ? (" ("+helpShortcut.nativeText+")") : "")

                Shortcut {
                    id: helpShortcut
                    sequence: StandardKey.HelpContents
                    onActivated: helpButton.clicked()
                }

                // TODO need to make sure browser is brought to foreground.
                onClicked: Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide");

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }
        }
    }

    // Hints of the default pages; a page can list its own in gamepadHints
    readonly property var defaultGamepadHints: [
        { glyph: "A", label: stackView.currentItem instanceof AppView ? qsTr("Play") :
                             stackView.currentItem instanceof SettingsView ? qsTr("Change") : qsTr("Select"), accent: true },
        { glyph: "X", label: qsTr("Options") },
        { glyph: "B", label: stackView.depth > 1 ? qsTr("Back") : qsTr("Quit") }
    ]

    // Gamepad button hints, shown while a gamepad is connected (always on handhelds)
    footer: Item {
        visible: connectedGamepads > 0 && hintRepeater.count > 0
        height: visible ? 52 : 0

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.pagePadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 28

            Repeater {
                id: hintRepeater
                model: stackView.currentItem && stackView.currentItem.gamepadHints !== undefined ?
                           stackView.currentItem.gamepadHints : defaultGamepadHints

                GamepadHint {
                    glyph: modelData.glyph
                    label: modelData.label
                    accent: modelData.accent === true
                }
            }
        }
    }

    // SdlGamepadKeyNavigation has no change notification, so check periodically
    Timer {
        interval: 2000
        running: window.active
        repeat: true
        triggeredOnStart: true
        onTriggered: connectedGamepads = SdlGamepadKeyNavigation.getConnectedGamepads()
    }

    ErrorMessageDialog {
        id: noHwDecoderDialog
        text: qsTr("No functioning hardware accelerated video decoder was detected by KanePlay. " +
                   "Your streaming performance may be severely degraded in this configuration.")
        helpText: qsTr("Click the Help button for more information on solving this problem.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    ErrorMessageDialog {
        id: xWaylandDialog
        text: qsTr("Hardware acceleration doesn't work on XWayland. Continuing on XWayland may result in poor streaming performance. " +
                   "Try running with QT_QPA_PLATFORM=wayland or switch to X11.")
        helpText: qsTr("Click the Help button for more information.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    NavigableMessageDialog {
        id: wow64Dialog
        standardButtons: Dialog.Ok | Dialog.Cancel
        text: qsTr("This version of KanePlay isn't optimized for your PC. Please download the '%1' version of KanePlay for the best streaming performance.").arg(SystemProperties.friendlyNativeArchName)
        onAccepted: {
            Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-qt/releases");
        }
    }

    ErrorMessageDialog {
        id: unmappedGamepadDialog
        property string unmappedGamepads : ""
        text: qsTr("KanePlay detected gamepads without a mapping:") + "\n" + unmappedGamepads
        helpTextSeparator: "\n\n"
        helpText: qsTr("Click the Help button for information on how to map your gamepads.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Gamepad-Mapping"
    }

    // This dialog appears when quitting via keyboard or gamepad button
    NavigableMessageDialog {
        id: quitConfirmationDialog
        standardButtons: Dialog.Yes | Dialog.No
        text: qsTr("Are you sure you want to quit?")
        // For keyboard/gamepad navigation
        onAccepted: Qt.quit()
    }

    // HACK: This belongs in StreamSegue but keeping a dialog around after the parent
    // dies can trigger bugs in Qt 5.12 that cause the app to crash. For now, we will
    // host this dialog in a QML component that is never destroyed.
    //
    // To repro: Start a stream, cut the network connection to trigger the "Connection
    // terminated" dialog, wait until the app grid times out back to the PC grid, then
    // try to dismiss the dialog.
    ErrorMessageDialog {
        id: streamSegueErrorDialog

        property bool quitAfter: false

        onClosed: {
            if (quitAfter) {
                Qt.quit()
            }

            // StreamSegue assumes its dialog will be re-created each time we
            // start streaming, so fake it by wiping out the text each time.
            text = ""
        }
    }

    UpdateDialog {
        id: updateDialog
    }

    // The intro plays on its own, fullscreen, before KanePlay shows up, the way
    // Steam's Big Picture opens. Not for launches that stream or pair straight away.
    Loader {
        id: introLoader
        active: runConfigChecks && StreamingPreferences.startupIntro

        sourceComponent: Window {
            title: "KanePlay"
            flags: Qt.FramelessWindowHint
            color: "#090A0D"

            // Gamepad buttons reach the focused window, this one for now
            onActiveChanged: {
                if (active) {
                    SdlGamepadKeyNavigation.notifyWindowFocus(true)
                }
            }

            StartupIntro {
                anchors.fill: parent
                onFinished: {
                    window.showWindow()
                    introLoader.active = false
                }
            }

            Component.onCompleted: showFullScreen()
        }
    }
}
