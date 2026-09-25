import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Window 2.2

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

Item {
    property Session session
    property string appName
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

    id: streamSegue

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1...").arg(stage)
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
        hintText.visible = false

        streamStartTime = Date.now()

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
            content.visible = true
            hintText.visible = false
            window.visible = true
            return
        }

        if (portTestResult !== 0 && portTestResult !== -1 && streamSegueErrorDialog.text) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

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
            reconnectTimer.start()
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
        interval: 2000
        onTriggered: {
            reconnecting = false
            isResume = true
            session = createSession()
            connectSession()

            // Run the same startup sequence again
            streamLoader.active = false
            streamLoader.active = true
        }
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
            hintText.text = qsTr("Tip:") + " " + qsTr("Press %1 to disconnect your session").arg(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ?
                                                  qsTr("Start+Select+L1+R1") : qsTr("Ctrl+Alt+Shift+Q"))
            hintText.visible = true

            // Stop GUI gamepad usage now
            SdlGamepadKeyNavigation.disable()

            // Initialize the session and probe for host/client capabilities
            if (!session.initialize(window)) {
                sessionFinished(0);
                sessionReadyForDeletion();
                return;
            }

            // This spinner is shown only after session.initialize() has completed
            // to prevent active animations from running during decoder probing,
            // which causes re-entrant event loop livelocks with libdecor-gtk.
            stageSpinner.visible = true

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

    Column {
        id: content
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.pagePadding, 900)
        spacing: 18

        Image {
            source: "qrc:/res/moon.svg"
            sourceSize.width: 56
            sourceSize.height: 56
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            width: parent.width
            text: appName
            font.family: Theme.displayFont
            font.pointSize: 34
            font.weight: Font.Black
            color: Theme.text
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Row {
            spacing: 14
            anchors.horizontalCenter: parent.horizontalCenter

            BusyIndicator {
                id: stageSpinner
                running: visible
                visible: false
                implicitWidth: 40
                implicitHeight: 40
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: stageLabel
                text: stageText
                font.family: Theme.textFont
                font.pointSize: 15
                color: reconnecting || reconnectAttempt > 0 ? Theme.warning : Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Text {
        id: hintText
        visible: false
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 2 * Theme.pagePadding
        font.family: Theme.textFont
        font.pointSize: 13
        color: Theme.textTertiary
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }
}
