import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import UiSound 1.0

// Home: the selected PC shown large with its Play button, and the list of PCs beside it
FocusScope {
    id: pcView
    objectName: qsTr("Home")
    focus: true

    property ComputerModel computerModel : createModel()

    // The PC shown in the hero card
    readonly property var pc: pcList.currentItem
    readonly property bool canOpenLibrary: pc !== null && pc.online && pc.paired
    property var lastSession: ({})

    // First launch: no PC known yet, we help finding and pairing one
    property bool showWelcome: false

    readonly property var gamepadHints: showWelcome ? [
        { glyph: "A", label: qsTr("Pair"), accent: true },
        { glyph: "Y", label: qsTr("Enter an address") },
        { glyph: "B", label: qsTr("Later") }
    ] : [
        { glyph: "A", label: primaryLabel(), accent: true },
        { glyph: "X", label: qsTr("PC options") },
        { glyph: "Y", label: qsTr("Settings") },
        { glyph: "B", label: embedded ? "KaneMode" : qsTr("Quit") }
    ]

    // Remembers the last PC played on, to show it first next time
    property string lastPcUuid: StreamingPreferences.lastPcUuid

    Component.onCompleted: {
        showWelcome = !StreamingPreferences.onboardingDone && pcList.count === 0
        restoreSelection()
    }

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        // Setup signals on CM
        ComputerManager.computerAddCompleted.connect(addComplete)
        refreshLastSession()

        // Show the focus ring right away when navigating with a gamepad
        if (showWelcome) {
            if (welcomeRows.count > 0) {
                welcomeRows.itemAt(0).children[0].children[2].forceActiveFocus(Qt.TabFocusReason)
            }
            else {
                welcomeAddButton.forceActiveFocus(Qt.TabFocusReason)
            }
            return
        }
        primaryButton.forceActiveFocus(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ? Qt.TabFocusReason : Qt.OtherFocusReason)
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
    }

    function restoreSelection()
    {
        for (var i = 0; i < pcList.count; i++) {
            var item = pcList.itemAtIndex(i)
            if (item !== null && item.uuid === lastPcUuid) {
                pcList.currentIndex = i
                return
            }
        }
    }

    function refreshLastSession()
    {
        lastSession = pc !== null ? StreamingPreferences.getLastSession(pc.uuid) : ({})
    }

    onPcChanged: refreshLastSession()

    function primaryLabel()
    {
        if (pc === null || pc.statusUnknown) {
            return qsTr("Searching…")
        }
        else if (!pc.online) {
            return pc.wakeable ? qsTr("Wake up") : qsTr("Offline")
        }
        else if (!pc.paired) {
            return qsTr("Pair")
        }
        else if (pc.busy) {
            return qsTr("Resume")
        }
        return qsTr("Play")
    }

    function statusText(item)
    {
        return item.statusUnknown ? qsTr("Checking…") :
               !item.online ? qsTr("Offline") :
               !item.paired ? qsTr("Online · not paired") :
               item.busy ? qsTr("Playing %1").arg(item.runningGame) : qsTr("Online")
    }

    function statusColor(item)
    {
        return item.statusUnknown ? Theme.textTertiary :
               !item.online ? Theme.textTertiary :
               !item.paired ? Theme.warning : Theme.success
    }

    function formatDuration(secs)
    {
        var minutes = Math.max(1, Math.round(secs / 60))
        if (minutes < 60) {
            return qsTr("%1 min").arg(minutes)
        }
        return qsTr("%1 h %2").arg(Math.floor(minutes / 60)).arg(("0" + (minutes % 60)).slice(-2))
    }

    function formatTimeAgo(date)
    {
        var minutes = Math.floor((Date.now() - date.getTime()) / 60000)
        if (minutes < 1) {
            return qsTr("just now")
        }
        else if (minutes < 60) {
            return qsTr("%1 min ago").arg(minutes)
        }
        else if (minutes < 24 * 60) {
            return qsTr("%1 h ago").arg(Math.floor(minutes / 60))
        }
        else if (minutes < 48 * 60) {
            return qsTr("yesterday")
        }
        return qsTr("%1 days ago").arg(Math.floor(minutes / (24 * 60)))
    }

    function openLibrary(appId, appName)
    {
        if (!canOpenLibrary) {
            return
        }

        StreamingPreferences.lastPcUuid = pc.uuid
        StreamingPreferences.save()

        var component = Qt.createComponent("AppView.qml")
        var appView = component.createObject(stackView, {
                                                 "computerIndex": pcList.currentIndex,
                                                 "objectName": pc.pcName,
                                                 "autoLaunchAppId": appId !== undefined ? appId : 0,
                                                 "autoLaunchAppName": appName !== undefined ? appName : ""
                                             })
        stackView.push(appView)
    }

    // KaneMode asked for a game of one of our PCs (KaneModeBridge): its library opens
    // and plays or resumes it. False while the PC isn't found, online and paired yet.
    function openPcLibrary(uuid, appId, appName)
    {
        for (var i = 0; i < pcList.count; i++) {
            var item = pcList.itemAtIndex(i)
            if (item !== null && item.uuid === uuid) {
                pcList.currentIndex = i
                if (!canOpenLibrary) {
                    return false
                }
                openLibrary(appId, appName)
                return true
            }
        }
        return false
    }
    function startPairing()
    {
        var pin = computerModel.generatePinString()

        // Kick off pairing in the background
        computerModel.pairComputer(pcList.currentIndex, pin)

        // Display the pairing dialog
        pairDialog.pin = pin
        pairDialog.pcName = pc.pcName
        pairDialog.open()
    }

    // What the Play button does for the selected PC
    function primaryAction()
    {
        if (pc === null || pc.statusUnknown) {
            return
        }

        if (!pc.online) {
            if (pc.wakeable) {
                computerModel.wakeComputer(pcList.currentIndex)
            }
        }
        else if (!pc.serverSupported) {
            errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of KanePlay. You must update KanePlay to stream from %1.").arg(pc.pcName)
            errorDialog.helpText = ""
            errorDialog.open()
        }
        else if (!pc.paired) {
            startPairing()
        }
        else if (pc.busy) {
            openLibrary(0, pc.runningGame)
        }
        else if (lastSession && lastSession.appName) {
            openLibrary(lastSession.appId, lastSession.appName)
        }
        else {
            openLibrary()
        }
    }

    function pairingComplete(error)
    {
        // Close the PIN dialog
        pairDialog.close()

        // Display a failed dialog if we got an error
        if (error !== undefined) {
            UiSound.play("error")
            errorDialog.text = error
            errorDialog.helpText = ""
            errorDialog.open()
        }
        else {
            UiSound.play("connected")
            finishWelcome()
        }
    }

    function addComplete(success, detectedPortBlocking)
    {
        if (!success) {
            UiSound.play("error")
            errorDialog.text = qsTr("Unable to connect to the specified PC.")

            if (detectedPortBlocking) {
                errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking %1. Streaming over the Internet may not work while connected to this network.").arg(appName)
            }
            else {
                errorDialog.helpText = qsTr("Click the Help button for possible solutions.")
            }

            errorDialog.open()
        }
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', parent, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    function openOptions()
    {
        if (pc !== null) {
            pcOptionsMenu.open()
        }
    }

    Keys.onMenuPressed: openOptions()

    function finishWelcome()
    {
        if (showWelcome) {
            showWelcome = false
            StreamingPreferences.onboardingDone = true
            StreamingPreferences.save()
            primaryButton.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    // During the first launch, B skips it and Y types an address
    Keys.onEscapePressed: function(event) {
        if (showWelcome) {
            UiSound.play("back")
            finishWelcome()
        }
        else {
            event.accepted = false
        }
    }
    Keys.onHangupPressed: function(event) {
        if (showWelcome) {
            openAddPc()
        }
        else {
            event.accepted = false
        }
    }

    // First launch
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 56
        anchors.rightMargin: 56
        anchors.topMargin: 24
        anchors.bottomMargin: 32
        spacing: 56
        visible: showWelcome

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 28

            AppLogo {
                size: 88
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    text: embedded ? qsTr("Welcome to local streaming") : qsTr("Welcome to KanePlay")
                    font.family: Theme.displayFont
                    font.pixelSize: 42
                    font.weight: Font.Bold
                    font.letterSpacing: -1.2
                    color: Theme.text
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 480
                    text: qsTr("Play the games of your PC on this device, from the couch or from the other side of the world.")
                    font.pixelSize: 18
                    lineHeight: 1.4
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                }
            }

            Row {
                spacing: 12

                Repeater {
                    model: [qsTr("Find your PCs"), qsTr("Pair"), qsTr("Play")]

                    Row {
                        spacing: 12

                        Rectangle {
                            visible: index > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 2
                            color: Theme.border
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: index === 0 ? Theme.accent : "transparent"
                            border.width: 2
                            border.color: index === 0 ? Theme.accent : Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: index + 1
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: index === 0 ? Theme.accentText : Theme.textTertiary
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: index === 0 ? Theme.text : Theme.textTertiary
                        }
                    }
                }
            }
        }

        // PCs found so far
        Rectangle {
            Layout.preferredWidth: 520
            Layout.fillHeight: true
            radius: 26
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("PCs found on your network")
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        color: Theme.text
                    }

                    ArcSpinner {
                        size: 18
                        lineWidth: 3
                        visible: StreamingPreferences.enableMdns
                    }

                    Text {
                        visible: StreamingPreferences.enableMdns
                        text: qsTr("Searching…")
                        font.pixelSize: 13
                        color: Theme.textSecondary
                    }
                }

                Repeater {
                    id: welcomeRows
                    model: computerModel

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 80
                        radius: 18
                        color: Theme.raised
                        border.width: 2
                        border.color: welcomeButton.activeFocus ? (Theme.whiteFocus ? Theme.focusFill : Theme.accent) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 14

                            Rectangle {
                                Layout.preferredWidth: 46
                                Layout.preferredHeight: 46
                                radius: 14
                                color: Theme.background

                                KpIcon {
                                    anchors.centerIn: parent
                                    name: "monitor"
                                    size: 22
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: model.name
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: model.statusUnknown ? qsTr("Checking…") : !model.online ? qsTr("Offline") :
                                          model.paired ? qsTr("Paired") : qsTr("Ready to pair")
                                    font.pixelSize: 13
                                    color: Theme.textSecondary
                                }
                            }

                            KpButton {
                                id: welcomeButton
                                implicitHeight: 44
                                leftPadding: 18
                                rightPadding: 18
                                fontSize: 14
                                variant: index === 0 ? "primary" : "secondary"
                                text: model.paired ? qsTr("Play") : qsTr("Pair")
                                enabled: model.online && model.serverSupported
                                onClicked: {
                                    pcList.currentIndex = index
                                    if (model.paired) {
                                        finishWelcome()
                                    }
                                    else {
                                        startPairing()
                                    }
                                }

                                Keys.onUpPressed: {
                                    if (index > 0) {
                                        welcomeRows.itemAt(index - 1).children[0].children[2].forceActiveFocus(Qt.TabFocusReason)
                                    }
                                }
                                Keys.onDownPressed: {
                                    if (index < welcomeRows.count - 1) {
                                        welcomeRows.itemAt(index + 1).children[0].children[2].forceActiveFocus(Qt.TabFocusReason)
                                    }
                                    else {
                                        welcomeAddButton.forceActiveFocus(Qt.TabFocusReason)
                                    }
                                }
                            }
                        }

                        Component.onCompleted: {
                            // The first PC found gets the focus
                            if (index === 0 && showWelcome) {
                                welcomeButton.forceActiveFocus(Qt.TabFocusReason)
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: welcomeHelp.implicitHeight + 28
                    radius: 16
                    color: Theme.background

                    ColumnLayout {
                        id: welcomeHelp
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            KpIcon {
                                Layout.alignment: Qt.AlignTop
                                name: "info"
                                size: 20
                                color: Theme.accent2
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Your PC isn't listed? It must be on, with Sunshine installed.")
                                font.pixelSize: 14
                                lineHeight: 1.3
                                color: Theme.textSecondary
                                wrapMode: Text.Wrap
                            }
                        }

                        KpButton {
                            id: welcomeAddButton
                            variant: "ghost"
                            implicitHeight: 40
                            leftPadding: 16
                            rightPadding: 16
                            fontSize: 14
                            iconName: "plus"
                            iconSize: 16
                            text: qsTr("Enter its address")
                            onClicked: openAddPc()

                            Keys.onUpPressed: {
                                if (welcomeRows.count > 0) {
                                    welcomeRows.itemAt(welcomeRows.count - 1).children[0].children[2].forceActiveFocus(Qt.TabFocusReason)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding
        anchors.topMargin: 8
        anchors.bottomMargin: 28
        spacing: 24
        visible: !showWelcome

        // The selected PC, shown large
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            // No PC yet: we're looking for them on the network
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 64
                visible: pcList.count === 0
                spacing: 20

                AppLogo {
                    Layout.alignment: Qt.AlignHCenter
                    size: 88
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: StreamingPreferences.enableMdns ? qsTr("Looking for your PCs…") : qsTr("Add your PC")
                    font.family: Theme.displayFont
                    font.pixelSize: 30
                    font.weight: Font.Bold
                    color: Theme.text
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: StreamingPreferences.enableMdns ?
                              qsTr("Your PC must be on, with Sunshine installed, on the same network as this device.") :
                              qsTr("Automatic PC discovery is disabled. Add your PC with its address.")
                    font.pixelSize: 16
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                }

                KpButton {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Add a PC")
                    iconName: "plus"
                    onClicked: openAddPc()
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 32
                visible: pc !== null
                spacing: 20

                Text {
                    text: (pc !== null && pc.busy ? qsTr("Playing now") :
                           lastSession && lastSession.endTime ? qsTr("Resume") : qsTr("Your PC")).toUpperCase()
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1.3
                    color: Theme.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: pc !== null ? pc.pcName : ""
                    font.family: Theme.displayFont
                    font.pixelSize: 44
                    font.weight: Font.Bold
                    font.letterSpacing: -1.2
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 26
                    color: Theme.text
                    elide: Text.ElideRight
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Chip {
                        dotColor: pc !== null ? statusColor(pc) : "transparent"
                        text: pc !== null ? statusText(pc) : ""
                        textColor: Theme.text
                    }

                    Chip {
                        text: StreamingPreferences.autoResolution ? qsTr("Automatic resolution") :
                                                                    StreamingPreferences.height + "p"
                    }

                    Chip {
                        text: StreamingPreferences.autoFps ? qsTr("Automatic FPS") : qsTr("%1 FPS").arg(StreamingPreferences.fps)
                    }
                }

                // What to do before playing on this PC
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: hintText.implicitHeight + 32
                    radius: Theme.radius
                    color: Theme.background
                    visible: pc !== null && !pc.statusUnknown && (!pc.online || !pc.paired)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        KpIcon {
                            Layout.alignment: Qt.AlignTop
                            name: "info"
                            size: 20
                            color: Theme.accent2
                        }

                        Text {
                            id: hintText
                            Layout.fillWidth: true
                            text: pc === null ? "" :
                                  !pc.online ? (pc.wakeable ? qsTr("This PC is asleep or turned off. %1 can wake it up if it is plugged into the network.").arg(appName)
                                                            : qsTr("This PC is offline. Turn it on, then wait for it to show up here.")) :
                                  qsTr("Pair this PC once to play on it: a code to enter in Sunshine will be shown.")
                            font.pixelSize: 15
                            lineHeight: 1.3
                            color: Theme.textSecondary
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // The last game played on this PC, or the one running on it
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 108
                    radius: Theme.radius
                    color: Theme.raised
                    visible: pc !== null && (pc.busy || (lastSession && lastSession.appName !== undefined && lastSession.appName !== ""))

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 16

                        Rectangle {
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: 80
                            radius: Theme.radius
                            // KaneMode: discreet tile, the accent only on the icon
                            color: Theme.kaneMode ? Theme.raised : Theme.accent

                            KpIcon {
                                anchors.centerIn: parent
                                name: "gamepad"
                                size: 26
                                color: Theme.kaneMode ? Theme.accent : Theme.accentText
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: pc !== null && pc.busy ? qsTr("Running on the PC") : qsTr("Last game")
                                font.pixelSize: 13
                                color: Theme.textSecondary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: pc !== null && pc.busy ? pc.runningGame : (lastSession.appName || "")
                                font.pixelSize: 18
                                font.weight: Font.Bold
                                color: Theme.text
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: text !== ""
                                text: lastSession && lastSession.endTime && !(pc !== null && pc.busy) ?
                                          qsTr("%1 · %2 session").arg(formatTimeAgo(lastSession.endTime)).arg(formatDuration(lastSession.durationSecs)) : ""
                                font.pixelSize: 13
                                color: Theme.textSecondary
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    KpButton {
                        id: primaryButton
                        Layout.fillWidth: true
                        implicitHeight: 60
                        variant: "primary"
                        fontSize: 19
                        iconName: pc !== null && pc.online && pc.paired ? "play" :
                                  pc !== null && !pc.online ? "wake" : "lock"
                        iconFilled: iconName === "play"
                        text: primaryLabel()
                        enabled: pc !== null && !pc.statusUnknown && (pc.online || pc.wakeable)
                        sound: pc !== null && pc.online && pc.paired ? "launch" : "select"
                        onClicked: primaryAction()

                        KeyNavigation.right: libraryButton.enabled ? libraryButton : pcList
                    }

                    KpButton {
                        id: libraryButton
                        implicitHeight: 60
                        iconName: "image"
                        text: qsTr("Library")
                        enabled: canOpenLibrary
                        onClicked: openLibrary()

                        KeyNavigation.left: primaryButton
                        KeyNavigation.right: desktopButton.enabled ? desktopButton : pcList
                    }

                    KpButton {
                        id: desktopButton
                        implicitHeight: 60
                        iconName: "desktop"
                        text: qsTr("Desktop")
                        enabled: canOpenLibrary
                        onClicked: openLibrary(0, "Desktop")

                        KeyNavigation.left: libraryButton
                        KeyNavigation.right: pcList
                    }
                }

                // Figures of the last session on this PC
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: lastSession && lastSession.endTime !== undefined

                    StatTile {
                        label: qsTr("Bitrate")
                        value: Math.round(StreamingPreferences.bitrateKbps / 1000 * (lastSession.learnedPercent || 100) / 100)
                        unit: qsTr("Mb/s")
                    }

                    StatTile {
                        label: qsTr("Latency")
                        value: lastSession.avgRttMs ? Math.round(lastSession.avgRttMs) : "—"
                        unit: lastSession.avgRttMs ? qsTr("ms") : ""
                    }

                    StatTile {
                        label: qsTr("Frames lost")
                        value: lastSession.lossPercent !== undefined ? Number(lastSession.lossPercent).toLocaleString(Qt.locale(), 'f', 1) : "—"
                        unit: "%"
                    }
                }
            }
        }

        // All the PCs
        ColumnLayout {
            Layout.preferredWidth: 400
            Layout.maximumWidth: 400
            Layout.fillHeight: true
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4

                Text {
                    Layout.fillWidth: true
                    text: qsTr("My PCs").toUpperCase()
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                    color: Theme.textSecondary
                }

                Text {
                    text: pcList.count > 0 ? qsTr("%n PC(s)", "", pcList.count) : ""
                    font.pixelSize: 13
                    color: Theme.textTertiary
                }
            }

            ListView {
                id: pcList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 12
                model: computerModel
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: Theme.durationStandard
                activeFocusOnTab: true
                keyNavigationEnabled: true

                onCountChanged: {
                    if (lastPcUuid !== "") {
                        restoreSelection()
                    }
                }

                Keys.onLeftPressed: primaryButton.enabled ? primaryButton.forceActiveFocus(Qt.TabFocus) : null
                Keys.onReturnPressed: primaryAction()
                Keys.onEnterPressed: primaryAction()
                Keys.onMenuPressed: openOptions()
                Keys.onDeletePressed: {
                    deletePcDialog.pcIndex = currentIndex
                    deletePcDialog.pcName = pc.pcName
                    deletePcDialog.open()
                }

                footer: Item {
                    width: ListView.view.width
                    height: 76

                    KpButton {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        implicitHeight: 64
                        variant: "ghost"
                        iconName: "plus"
                        text: qsTr("Add a PC")
                        focusPolicy: Qt.NoFocus
                        onClicked: openAddPc()
                    }
                }

                delegate: ItemDelegate {
                    id: pcRow

                    // Read by the hero card through pcList.currentItem
                    readonly property string pcName: model.name
                    readonly property bool online: model.online
                    readonly property bool paired: model.paired
                    readonly property bool busy: model.busy
                    readonly property bool wakeable: model.wakeable
                    readonly property bool statusUnknown: model.statusUnknown
                    readonly property bool serverSupported: model.serverSupported
                    readonly property string details: model.details
                    readonly property string uuid: model.uuid
                    readonly property string runningGame: model.runningGame

                    readonly property bool isCurrent: ListView.isCurrentItem

                    width: ListView.view.width
                    height: 72
                    padding: 0
                    focusPolicy: Qt.NoFocus

                    // KaneMode: white when selected with the gamepad, dark text
                    readonly property bool whiteFocus: Theme.whiteFocus && isCurrent && pcList.activeFocus

                    background: Rectangle {
                        radius: Theme.radius
                        color: pcRow.whiteFocus ? Theme.focusFill : pcRow.isCurrent ? Theme.raised : (pcRow.hovered ? Theme.hover : Theme.surface)
                        border.width: 2
                        border.color: pcRow.whiteFocus ? "transparent" : pcRow.isCurrent && pcList.activeFocus ? Theme.accent :
                                      pcRow.isCurrent ? Theme.border : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Theme.durationStandard }
                        }
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14

                        Rectangle {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            radius: 12
                            color: Theme.background

                            KpIcon {
                                anchors.centerIn: parent
                                name: "monitor"
                                size: 20
                                color: pcRow.online ? Theme.text : Theme.textTertiary
                            }

                            BusyIndicator {
                                anchors.centerIn: parent
                                width: 40
                                height: 40
                                visible: pcRow.statusUnknown
                                running: visible
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: pcRow.pcName
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: pcRow.whiteFocus ? Theme.focusText : pcRow.online ? Theme.text : Theme.textSecondary
                                elide: Text.ElideRight
                            }

                            Row {
                                spacing: 6

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: statusColor(pcRow)
                                }

                                Text {
                                    text: statusText(pcRow)
                                    font.pixelSize: 13
                                    color: pcRow.whiteFocus ? Theme.focusMuted : Theme.textSecondary
                                }
                            }
                        }

                        KpIcon {
                            name: "right"
                            size: 18
                            color: Theme.textTertiary
                        }
                    }

                    onClicked: {
                        if (!isCurrent) {
                            UiSound.play("move")
                        }
                        pcList.currentIndex = index
                    }
                    onDoubleClicked: primaryAction()
                    onPressAndHold: {
                        pcList.currentIndex = index
                        openOptions()
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: pcRow.pressAndHold()
                    }
                }
            }

        }
    }

    NavigableMenu {
        id: pcOptionsMenu
        initiator: pcList.activeFocus ? pcList : primaryButton
        x: pcView.width - width - Theme.pagePadding - 16
        y: 60

        MenuItem {
            text: pc !== null ? pc.pcName : ""
            font.bold: true
            enabled: false
        }
        NavigableMenuItem {
            text: qsTr("View All Apps")
            visible: canOpenLibrary
            onTriggered: {
                var component = Qt.createComponent("AppView.qml")
                var appView = component.createObject(stackView, {"computerIndex": pcList.currentIndex, "objectName": pc.pcName, "showHiddenGames": true})
                stackView.push(appView)
            }
        }
        NavigableMenuItem {
            text: qsTr("Wake PC")
            visible: pc !== null && !pc.online && pc.wakeable
            onTriggered: computerModel.wakeComputer(pcList.currentIndex)
        }
        NavigableMenuItem {
            text: qsTr("Test Network")
            onTriggered: {
                computerModel.testConnectionForComputer(pcList.currentIndex)
                testConnectionDialog.open()
            }
        }
        NavigableMenuItem {
            text: qsTr("Rename PC")
            onTriggered: {
                renamePcDialog.pcIndex = pcList.currentIndex
                renamePcDialog.originalName = pc.pcName
                renamePcDialog.open()
            }
        }
        NavigableMenuItem {
            text: qsTr("Delete PC")
            onTriggered: {
                deletePcDialog.pcIndex = pcList.currentIndex
                deletePcDialog.pcName = pc.pcName
                deletePcDialog.open()
            }
        }
        NavigableMenuItem {
            text: qsTr("View Details")
            onTriggered: {
                showPcDetailsDialog.pcDetails = pc.details
                showPcDetailsDialog.open()
            }
        }
    }

    ErrorMessageDialog {
        id: errorDialog

        // Using Setup-Guide here instead of Troubleshooting because it's likely that users
        // will arrive here by forgetting to enable GameStream or not forwarding ports.
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"
    }

    PairingDialog {
        id: pairDialog
    }

    NavigableMessageDialog {
        id: deletePcDialog
        // don't allow edits to the rest of the window while open
        property int pcIndex : -1
        property string pcName : ""
        text: qsTr("Are you sure you want to remove '%1'?").arg(pcName)
        standardButtons: Dialog.Yes | Dialog.No

        onAccepted: {
            computerModel.deleteComputer(pcIndex)
        }
    }

    NavigableMessageDialog {
        id: testConnectionDialog
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Ok

        onAboutToShow: {
            testConnectionDialog.text = qsTr("%1 is testing your network connection to determine if any required ports are blocked.").arg(appName) + "\n\n" + qsTr("This may take a few seconds…")
            showSpinner = true
        }

        function connectionTestComplete(result, blockedPorts)
        {
            if (result === -1) {
                text = qsTr("The network test could not be performed because none of the connection testing servers were reachable from this PC. Check your Internet connection or try again later.")
                imageSrc = "qrc:/res/baseline-warning-24px.svg"
            }
            else if (result === 0) {
                text = qsTr("This network does not appear to be blocking %1. If you still have trouble connecting, check your PC's firewall settings.").arg(appName)
                imageSrc = "qrc:/res/baseline-check_circle_outline-24px.svg"
            }
            else {
                text = qsTr("Your PC's current network connection seems to be blocking %1. Streaming over the Internet may not work while connected to this network.").arg(appName) + "\n\n" + qsTr("The following network ports were blocked:") + "\n"
                text += blockedPorts
                imageSrc = "qrc:/res/baseline-error_outline-24px.svg"
            }

            // Stop showing the spinner and show the image instead
            showSpinner = false
        }
    }

    NavigableDialog {
        id: renamePcDialog
        property string label: qsTr("Enter the new name for this PC:")
        property string originalName
        property int pcIndex : -1;

        standardButtons: Dialog.Ok | Dialog.Cancel

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            editText.forceActiveFocus()
        }

        onClosed: {
            editText.clear()
        }

        onAccepted: {
            if (editText.text) {
                computerModel.renameComputer(pcIndex, editText.text)
            }
        }

        ColumnLayout {
            Label {
                text: renamePcDialog.label
                font.bold: true
            }

            TextField {
                id: editText
                placeholderText: renamePcDialog.originalName
                Layout.fillWidth: true
                focus: true

                Keys.onReturnPressed: {
                    renamePcDialog.accept()
                }

                Keys.onEnterPressed: {
                    renamePcDialog.accept()
                }
            }
        }
    }

    NavigableMessageDialog {
        id: showPcDetailsDialog
        property string pcDetails : "";
        text: showPcDetailsDialog.pcDetails
        imageSrc: "qrc:/res/baseline-help_outline-24px.svg"
        standardButtons: Dialog.Ok
    }
}
