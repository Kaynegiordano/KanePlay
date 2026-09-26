import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import UiSound 1.0

// Shown while a stream starts: the steps of the connection next to the KanePlay mark.
// Also shown when the connection drops, while we try to reconnect.
Item {
    property Session session
    property string appName
    // PC the app runs on, when known
    property string hostName
    property string hostUuid
    // The stream ended normally: show its summary once the session is cleaned up
    property bool pendingSummary: false
    property string stageText : isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false

    // Creates a new Session for the same app, used to reconnect after a network drop.
    // Streams started without it (command line, after quitting another app) don't reconnect.
    property var createSession: null
    property int reconnectAttempt: 0
    property bool reconnecting: false
    readonly property int maxReconnectAttempts: 3
    // A stream that ran this long starts counting reconnection attempts from scratch
    readonly property int stableStreamMs: 60000
    property double streamStartTime: 0

    // Steps of the connection: 0 preparing this device, 1 negotiating with the PC, 2 starting the stream
    property int step: 0
    property string stageDetail: ""
    // Set once the decoders are probed; nothing animates before that (see streamLoader)
    property bool initialized: false
    property int reconnectCountdown: 0
    // Tip about the disconnect shortcut, shown until the stream starts
    property bool showHint: false

    readonly property var gamepadHints: reconnecting ? [
        { glyph: "A", label: qsTr("Retry now"), accent: true },
        { glyph: "B", label: qsTr("Home") }
    ] : []

    id: streamSegue

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1...").arg(stage)
        stageDetail = stage

        // The last stages bring up the video, audio and input streams
        step = /establishment|video stream|input stream/i.test(stage) ? 2 : 1
    }

    function stageFailed(stage, errorCode, failingPorts)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = qsTr("Starting %1 failed: Error %2").arg(stage).arg(errorCode)

        if (failingPorts) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts)
        }
    }

    function connectionStarted()
    {
        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        content.visible = false
        showHint = false

        streamStartTime = Date.now()
        UiSound.play("connected")

        // Hide the window now that streaming has begun
        window.visible = false
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = text
        console.error(text)
    }

    function quitStarting()
    {
        // Avoid the push transition animation
        var component = Qt.createComponent("QuitSegue.qml")
        stackView.replace(stackView.currentItem, component.createObject(stackView, {"appName": appName}), StackView.Immediate)

        // Show the Qt window again to show quit segue
        window.visible = true
    }

    function shouldReconnect()
    {
        if (quitAfter || createSession === null || !StreamingPreferences.autoReconnect ||
                session === null || !session.isReconnectable()) {
            return false
        }

        // A stream that worked for a while gets a fresh set of attempts
        if (streamStartTime !== 0 && Date.now() - streamStartTime > stableStreamMs) {
            reconnectAttempt = 0
        }

        return reconnectAttempt < maxReconnectAttempts
    }

    function sessionFinished(portTestResult)
    {
        if (shouldReconnect()) {
            // Reconnect once the old session is fully cleaned up (see sessionReadyForDeletion)
            reconnecting = true
            reconnectAttempt++
            streamSegueErrorDialog.text = ""
            stageText = qsTr("Connection lost. Reconnecting (%1/%2)...").arg(reconnectAttempt).arg(maxReconnectAttempts)
            content.visible = false
            showHint = false
            window.visible = true
            UiSound.play("error")

            // The buttons of the connection lost card work with the gamepad too
            SdlGamepadKeyNavigation.enable()
            retryButton.forceActiveFocus(Qt.TabFocusReason)
            return
        }

        if (portTestResult !== 0 && portTestResult !== -1 && streamSegueErrorDialog.text) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking KanePlay. Streaming over the Internet may not work while connected to this network.")
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // A stream that ran ends on its summary, saved while the session is cleaned up
        if (!quitAfter && !streamSegueErrorDialog.text && streamStartTime !== 0 && hostUuid !== "") {
            pendingSummary = true
            window.visible = true
            return
        }

        // Pop the StreamSegue off the stack if this is a GUI-based app launch
        if (!quitAfter) {
            stackView.pop()
        }

        if (quitAfter && !streamSegueErrorDialog.text) {
            // If this was a CLI launch without errors, exit now
            Qt.quit()
        }
        else {
            // Show the Qt window again after streaming
            window.visible = true

            // Display any launch errors. We do this after
            // the Qt UI is visible again to prevent losing
            // focus on the dialog which would impact gamepad
            // users.
            if (streamSegueErrorDialog.text) {
                UiSound.play("error")
                streamSegueErrorDialog.quitAfter = quitAfter
                streamSegueErrorDialog.open()
            }
        }
    }

    function sessionReadyForDeletion()
    {
        // Garbage collect the Session object since it's pretty heavyweight
        // and keeps other libraries (like SDL_TTF) around until it is deleted.
        session = null
        gc()

        if (reconnecting) {
            reconnectCountdown = Math.round(reconnectTimer.interval / 1000)
            reconnectTimer.start()
        }
        else if (pendingSummary) {
            pendingSummary = false

            // Too short sessions have no summary, see StreamHealthMonitor
            var summary = StreamingPreferences.getLastSession(hostUuid)
            if (summary.endTime !== undefined && Date.now() - summary.endTime.getTime() < 60000) {
                var component = Qt.createComponent("SessionSummaryView.qml")
                stackView.replace(streamSegue, component.createObject(stackView, {
                                                                          "appName": appName,
                                                                          "hostName": hostName,
                                                                          "hostUuid": hostUuid,
                                                                          "createSession": createSession,
                                                                          "summary": summary
                                                                      }))
            }
            else {
                stackView.pop()
            }
        }
    }

    function connectSession()
    {
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.readyForDeletion.connect(sessionReadyForDeletion)
    }

    // Retry right away instead of waiting for the countdown
    function reconnectNow()
    {
        if (reconnecting && session === null) {
            reconnectTimer.stop()
            reconnectTimer.triggered()
        }
    }

    // Give up reconnecting and go back to the library
    function abandonReconnect()
    {
        reconnectTimer.stop()
        reconnecting = false
        stackView.pop()
    }

    StackView.onDeactivating: {
        // Show the toolbar again when popped off the stack
        toolBar.visible = true

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()
    }

    StackView.onActivated: {
        // Hide the toolbar before we start loading
        toolBar.visible = false

        // Hook up our signals
        connectSession()

        // Ensure the SystemProperties async thread is finished,
        // since it may currently be using the SDL video subsystem
        SystemProperties.waitForAsyncLoad()

        // Kick off the stream
        streamLoader.active = true
    }

    // Leave the network a moment to recover before trying again
    Timer {
        id: reconnectTimer
        interval: 3000
        onTriggered: {
            reconnecting = false
            isResume = true
            step = 0
            stageDetail = ""
            initialized = false
            content.visible = true
            session = createSession()
            connectSession()

            // Run the same startup sequence again
            streamLoader.active = false
            streamLoader.active = true
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: reconnectTimer.running
        onTriggered: reconnectCountdown = Math.max(0, reconnectCountdown - 1)
    }

    Timer {
        id: startSessionTimer
        onTriggered: {
            // Garbage collect QML stuff before we start streaming,
            // since we'll probably be streaming for a while and we
            // won't be able to GC during the stream.
            gc()

            // Run the streaming session to completion
            session.start()
        }
    }

    Loader {
        id: streamLoader
        active: false
        asynchronous: true

        onLoaded: {
            // Set the hint text. We do this here rather than
            // in the hintText control itself to synchronize
            // with Session.exec() which requires no concurrent
            // gamepad usage.
            hintText.text = SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ?
                        qsTr("Start+Select opens the menu, LB+RB+Select+Y disconnects") :
                        qsTr("Press %1 to disconnect your session").arg(qsTr("Ctrl+Alt+Shift+Q"))
            showHint = true

            // Stop GUI gamepad usage now
            SdlGamepadKeyNavigation.disable()

            // Initialize the session and probe for host/client capabilities
            if (!session.initialize(window)) {
                sessionFinished(0);
                sessionReadyForDeletion();
                return;
            }

            // The animations start only after session.initialize() has completed
            // to prevent active animations from running during decoder probing,
            // which causes re-entrant event loop livelocks with libdecor-gtk.
            initialized = true
            if (step === 0) {
                step = 1
            }

            // Don't wait unless we have toasts to display
            startSessionTimer.interval = 0

            // Display the toasts together in a vertical centered arrangement
            var yOffset = 0
            for (var i = 0; i < session.launchWarnings.length; i++) {
                var text = session.launchWarnings[i]
                console.warn(text)

                // Show the tooltip for 3 seconds
                var toast = Qt.createQmlObject('import QtQuick.Controls 2.2; ToolTip {}', parent, '')
                toast.timeout = 3000
                toast.text = text
                toast.y += yOffset
                toast.visible = true

                // Offset the next toast below the previous one
                yOffset = toast.y + toast.padding + toast.height

                // Allow an extra 500 ms for the tooltip's fade-out animation to finish
                startSessionTimer.interval = toast.timeout + 500;
            }

            // Start the timer to wait for toasts (or start the session immediately)
            startSessionTimer.start()
        }

        sourceComponent: Item {}
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    // One step of the connection, done, in progress or to come
    component ConnectionStep: RowLayout {
        property string title
        property string detail
        // 0 to come, 1 in progress, 2 done
        property int stepState
        property bool spinning

        spacing: 16

        Item {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            Rectangle {
                anchors.fill: parent
                radius: 16
                visible: stepState === 2
                color: Theme.success

                KpIcon {
                    anchors.centerIn: parent
                    name: "check"
                    size: 18
                    strokeWidth: 2.6
                    color: "#0B1A12"
                }
            }

            ArcSpinner {
                anchors.fill: parent
                size: 32
                visible: stepState === 1
                running: visible && spinning
            }

            Rectangle {
                anchors.fill: parent
                radius: 16
                visible: stepState === 0
                color: "transparent"
                border.width: 2
                border.color: Theme.border
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: title
                font.pixelSize: 17
                font.weight: Font.Bold
                color: stepState === 1 ? Theme.text : stepState === 2 ? Theme.textSecondary : Theme.textTertiary
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: detail
                font.pixelSize: 13
                color: stepState === 0 ? Theme.textTertiary : Theme.textSecondary
                elide: Text.ElideRight
            }
        }
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 88

        LogoRing {
            size: 260
            running: initialized
        }

        ColumnLayout {
            Layout.preferredWidth: 460
            spacing: 28

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: (reconnectAttempt > 0 ? qsTr("Reconnecting (%1/%2)").arg(reconnectAttempt).arg(maxReconnectAttempts) :
                                                  isResume ? qsTr("Resuming") : qsTr("Connecting")).toUpperCase()
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1.3
                    color: reconnectAttempt > 0 ? Theme.warning : Theme.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: appName
                    font.family: Theme.displayFont
                    font.pixelSize: 36
                    font.weight: Font.Bold
                    font.letterSpacing: -1
                    color: Theme.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    visible: hostName !== ""
                    text: qsTr("on %1").arg(hostName)
                    font.pixelSize: 16
                    color: Theme.textSecondary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 18

                ConnectionStep {
                    Layout.fillWidth: true
                    title: step > 0 ? qsTr("Device ready") : qsTr("Preparing this device")
                    detail: step > 0 ? qsTr("Video decoder checked") : qsTr("Checking the video decoder…")
                    stepState: step > 0 ? 2 : 1
                    spinning: initialized
                }

                ConnectionStep {
                    Layout.fillWidth: true
                    title: step > 1 ? qsTr("Session negotiated") : qsTr("Negotiating the session")
                    detail: step === 1 ? stageDetail : ""
                    stepState: step > 1 ? 2 : step === 1 ? 1 : 0
                    spinning: initialized
                }

                ConnectionStep {
                    Layout.fillWidth: true
                    title: qsTr("Starting the stream")
                    detail: step === 2 ? qsTr("Receiving the first frames…") : ""
                    stepState: step === 2 ? 1 : 0
                    spinning: initialized
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: tipRow.implicitHeight + 32
                visible: showHint
                radius: Theme.radius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                RowLayout {
                    id: tipRow
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
                        font.pixelSize: 14
                        lineHeight: 1.3
                        color: Theme.textSecondary
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // The connection dropped: we try again on our own, a few times
    Rectangle {
        anchors.centerIn: parent
        width: 560
        implicitHeight: lostColumn.implicitHeight + 72
        visible: reconnecting
        radius: 28
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            id: lostColumn
            anchors.fill: parent
            anchors.margins: 36
            spacing: 22

            Rectangle {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                radius: 20
                color: Theme.raised

                KpIcon {
                    anchors.centerIn: parent
                    name: "wifioff"
                    size: 32
                    color: Theme.accent2
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: qsTr("Connection lost")
                    font.family: Theme.displayFont
                    font.pixelSize: 28
                    font.weight: Font.Bold
                    font.letterSpacing: -0.6
                    color: Theme.text
                }

                Text {
                    Layout.fillWidth: true
                    text: (hostName !== "" ? qsTr("%1 is no longer responding.").arg(hostName) : qsTr("The PC is no longer responding.")) +
                          " " + qsTr("The game keeps running on the PC.")
                    font.pixelSize: 16
                    lineHeight: 1.3
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: session === null ? qsTr("Trying again in %n s", "", reconnectCountdown) : qsTr("Cleaning up…")
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: Theme.text
                    }

                    Text {
                        text: qsTr("attempt %1 of %2").arg(reconnectAttempt).arg(maxReconnectAttempts)
                        font.pixelSize: 14
                        color: Theme.textSecondary
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: 4
                    color: Theme.raised

                    Rectangle {
                        id: countdownBar
                        height: parent.height
                        radius: 4
                        color: Theme.accent
                        width: 0

                        // Fills up until the next attempt
                        NumberAnimation on width {
                            id: countdownAnimation
                            running: reconnectTimer.running
                            from: 0
                            to: countdownBar.parent.width
                            duration: reconnectTimer.interval
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                KpButton {
                    id: retryButton
                    Layout.fillWidth: true
                    variant: "primary"
                    iconName: "refresh"
                    text: qsTr("Retry now")
                    enabled: session === null
                    onClicked: reconnectNow()

                    KeyNavigation.right: homeButton
                }

                KpButton {
                    id: homeButton
                    iconName: "home"
                    text: qsTr("Home")
                    sound: "back"
                    // The old session must be gone before we leave
                    enabled: session === null
                    onClicked: abandonReconnect()

                    KeyNavigation.left: retryButton
                }
            }
        }
    }

    // B leaves the connection lost card
    Keys.onEscapePressed: {
        if (reconnecting && session === null) {
            abandonReconnect()
        }
    }
}
