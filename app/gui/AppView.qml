import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Controls.Material 2.2
import QtQuick.Effects

import AppModel 1.0
import ComputerManager 1.0
import StreamingPreferences 1.0
import SdlGamepadKeyNavigation 1.0

// App library of one PC: the selected app is shown large at the top,
// and the apps are browsed in a horizontal carousel below it.
FocusScope {
    property int computerIndex
    property AppModel appModel : createModel()
    property bool activated
    property bool showHiddenGames
    property bool showGames

    // Set once the user moved the selection, so a running app
    // reported later doesn't steal it back
    property bool userSelected: false

    readonly property var selectedApp: carousel.currentItem
    readonly property bool compact: height < 640

    id: appView
    focus: true

    function computerLost()
    {
        // Go back to the PC view on PC loss
        stackView.pop()
    }

    StackView.onActivated: {
        appModel.computerLost.connect(computerLost)
        activated = true

        carousel.forceActiveFocus()

        if (!showGames && !showHiddenGames) {
            // Check if there's a direct launch app
            var directLaunchAppIndex = appModel.getDirectLaunchAppIndex();
            if (directLaunchAppIndex >= 0) {
                // Start the direct launch app if nothing else is running
                carousel.currentIndex = directLaunchAppIndex
                carousel.forceLayout()
                carousel.currentItem.launchOrResumeSelectedApp(false)

                // Set showGames so we will not loop when the stream ends
                showGames = true
            }
        }
    }

    StackView.onDeactivating: {
        appModel.computerLost.disconnect(computerLost)
        activated = false
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import AppModel 1.0; AppModel {}', parent, '')
        model.initialize(ComputerManager, computerIndex, showHiddenGames)
        return model
    }

    function streamSummary()
    {
        var parts = []
        parts.push(StreamingPreferences.autoResolution ? qsTr("Automatic resolution")
                                                       : StreamingPreferences.width + " × " + StreamingPreferences.height)
        parts.push(StreamingPreferences.autoFps ? qsTr("Automatic FPS")
                                                : qsTr("%1 FPS").arg(StreamingPreferences.fps))
        parts.push(qsTr("%1 Mbps").arg(StreamingPreferences.bitrateKbps / 1000.0))
        if (StreamingPreferences.enableVrr && StreamingPreferences.enableVsync) {
            parts.push("VRR")
        }
        if (StreamingPreferences.enableHdr) {
            parts.push("HDR")
        }
        return parts
    }

    // Blurred box art of the selected app fills the background
    Image {
        id: backdropArt
        anchors.fill: parent
        source: selectedApp ? selectedApp.boxArt : ""
        sourceSize.width: 160
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: backdropArt
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        opacity: backdropArt.status === Image.Ready ? 0.45 : 0

        Behavior on opacity {
            NumberAnimation { duration: 250 }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.background }
            GradientStop { position: 0.45; color: Qt.rgba(0.043, 0.051, 0.071, 0.85) }
            GradientStop { position: 1.0; color: Qt.rgba(0.043, 0.051, 0.071, 0.35) }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: carouselArea.height + 80
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Theme.background }
        }
    }

    // Selected app, shown large
    Column {
        id: hero
        anchors.left: parent.left
        anchors.leftMargin: Theme.pagePadding
        anchors.right: heroArt.visible ? heroArt.left : parent.right
        anchors.rightMargin: 40
        anchors.bottom: carouselArea.top
        anchors.bottomMargin: compact ? 16 : 36
        spacing: compact ? 10 : 16
        visible: carousel.count > 0

        Text {
            text: selectedApp && selectedApp.running ? qsTr("RUNNING ON THE HOST") : appView.objectName.toUpperCase()
            font.family: Theme.textFont
            font.pointSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.5
            color: selectedApp && selectedApp.running ? Theme.success : Theme.accent
        }

        Text {
            width: parent.width
            text: selectedApp ? selectedApp.appName : ""
            font.family: Theme.displayFont
            font.pointSize: compact ? 30 : 44
            font.weight: Font.Black
            color: Theme.text
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }

        Flow {
            width: parent.width
            spacing: 10

            Repeater {
                model: streamSummary()

                Rectangle {
                    implicitWidth: chipText.implicitWidth + 24
                    implicitHeight: chipText.implicitHeight + 14
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.08)

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData
                        font.family: Theme.textFont
                        font.pointSize: 10
                        color: "#D4D9E2"
                    }
                }
            }
        }

        Row {
            spacing: 14
            topPadding: compact ? 4 : 10

            HeroButton {
                id: playButton
                primary: true
                glyph: "A"
                text: selectedApp && selectedApp.running ? qsTr("Resume Game") : qsTr("Launch Game")
                onClicked: selectedApp.launchOrResumeSelectedApp(true)

                Keys.onDownPressed: carousel.forceActiveFocus()
                Keys.onUpPressed: libraryPill.forceActiveFocus(Qt.TabFocus)
                Keys.onRightPressed: (quitButton.visible ? quitButton : optionsButton).forceActiveFocus(Qt.TabFocus)
            }

            HeroButton {
                id: quitButton
                visible: selectedApp !== null && selectedApp.running
                text: qsTr("Quit Game")
                onClicked: selectedApp.doQuitGame()

                Keys.onDownPressed: carousel.forceActiveFocus()
                Keys.onUpPressed: libraryPill.forceActiveFocus(Qt.TabFocus)
                Keys.onLeftPressed: playButton.forceActiveFocus(Qt.TabFocus)
                Keys.onRightPressed: optionsButton.forceActiveFocus(Qt.TabFocus)
            }

            HeroButton {
                id: optionsButton
                glyph: "X"
                text: qsTr("Options")
                onClicked: selectedApp.openContextMenu()

                Keys.onDownPressed: carousel.forceActiveFocus()
                Keys.onUpPressed: libraryPill.forceActiveFocus(Qt.TabFocus)
                Keys.onLeftPressed: (quitButton.visible ? quitButton : playButton).forceActiveFocus(Qt.TabFocus)
            }
        }
    }

    // Sharp box art of the selected app, on wide enough windows
    Item {
        id: heroArt
        visible: appView.width > 1100 && selectedApp !== null && !selectedApp.isPlaceholder
        anchors.right: parent.right
        anchors.rightMargin: Theme.pagePadding
        anchors.bottom: carouselArea.top
        anchors.bottomMargin: compact ? 16 : 36
        anchors.top: parent.top
        anchors.topMargin: 24
        width: height * 3 / 4

        Image {
            id: heroArtImage
            anchors.fill: parent
            source: selectedApp ? selectedApp.boxArt : ""
            sourceSize.width: 600
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }

        Rectangle {
            id: heroArtMask
            anchors.fill: parent
            radius: Theme.radiusLarge
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: heroArtImage
            maskEnabled: true
            maskSource: heroArtMask
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 1.0
            shadowOpacity: 0.6
        }
    }

    // App carousel
    Item {
        id: carouselArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: (compact ? 230 : 290) + sectionTitle.height

        Row {
            id: sectionTitle
            x: Theme.pagePadding
            spacing: 14

            Text {
                text: qsTr("Applications")
                font.family: Theme.displayFont
                font.pointSize: 15
                font.weight: Font.Bold
                color: Theme.text
            }

            Text {
                text: carousel.count
                font.family: Theme.textFont
                font.pointSize: 11
                color: Theme.textSecondary
            }
        }

        ListView {
            id: carousel
            anchors.top: sectionTitle.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            orientation: ListView.Horizontal
            spacing: 22
            leftMargin: Theme.pagePadding
            rightMargin: Theme.pagePadding
            focus: true
            clip: false
            keyNavigationEnabled: true
            highlightMoveDuration: 180
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: Theme.pagePadding
            preferredHighlightEnd: width - Theme.pagePadding - 200
            boundsBehavior: Flickable.StopAtBounds

            model: appModel

            onCurrentIndexChanged: {
                if (activeFocus) {
                    userSelected = true
                }
            }

            delegate: ItemDelegate {
                id: card

                readonly property bool isCurrent: ListView.isCurrentItem
                readonly property string appName: model.name
                readonly property bool running: model.running
                readonly property string boxArt: model.boxart
                property bool isPlaceholder: false

                property alias appContextMenu: appContextMenuLoader.item

                width: isCurrent ? (compact ? 150 : 186) : (compact ? 126 : 156)
                height: width * 4 / 3
                // Cards grow upwards from a common baseline
                y: carousel.height - height
                padding: 0

                // Dim the app if it's hidden
                opacity: model.hidden ? 0.4 : 1.0

                Behavior on width {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                Component.onCompleted: {
                    // Start on the running app unless the user picked something else
                    if (model.running && !userSelected) {
                        carousel.currentIndex = index
                    }
                }

                onRunningChanged: {
                    if (running && !userSelected) {
                        carousel.currentIndex = index
                    }
                }

                background: Rectangle {
                    radius: Theme.radius
                    color: Theme.raised
                    border.width: card.isCurrent ? 3 : 1
                    border.color: card.isCurrent && carousel.activeFocus ? Theme.accent :
                                  card.isCurrent ? Theme.textSecondary : Theme.border
                }

                contentItem: Item {
                    Image {
                        id: art
                        anchors.fill: parent
                        anchors.margins: 3
                        source: model.boxart
                        sourceSize.width: 400
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false

                        onStatusChanged: {
                            if (status !== Image.Ready) {
                                return
                            }

                            // Nearly all of Nvidia's official box art does not match the dimensions of placeholder
                            // images, however the one known exception is Overcooked. Therefore, we only execute
                            // the image size checks if this is not an app collector game. We know the officially
                            // supported games all have box art, so this check is not required.
                            var w = implicitWidth, h = implicitHeight
                            card.isPlaceholder = !model.isAppCollectorGame &&
                                    ((w === 130 && h === 180) || // GFE 2.0 placeholder image
                                     (w === 628 && h === 888) || // GFE 3.0 placeholder image
                                     (w === 200 && h === 266))   // Our no_app_image.png
                        }
                    }

                    Rectangle {
                        id: artMask
                        anchors.fill: art
                        radius: Theme.radius - 3
                        visible: false
                        layer.enabled: true
                    }

                    MultiEffect {
                        anchors.fill: art
                        source: art
                        maskEnabled: true
                        maskSource: artMask
                        visible: !card.isPlaceholder
                    }

                    // Placeholder box art: show the name instead
                    Text {
                        visible: card.isPlaceholder || art.status !== Image.Ready
                        anchors.fill: parent
                        anchors.margins: 14
                        text: model.name
                        font.family: Theme.displayFont
                        font.pointSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.text
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignBottom
                    }

                    Rectangle {
                        visible: model.running
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 10
                        implicitWidth: runningText.implicitWidth + 14
                        implicitHeight: runningText.implicitHeight + 8
                        radius: 6
                        color: Theme.success

                        Text {
                            id: runningText
                            anchors.centerIn: parent
                            text: qsTr("RUNNING")
                            font.family: Theme.textFont
                            font.pointSize: 8
                            font.weight: Font.Black
                            font.letterSpacing: 0.8
                            color: Theme.background
                        }
                    }
                }

                // Display a tooltip with the full name
                ToolTip.text: model.name
                ToolTip.delay: 1000
                ToolTip.timeout: 5000
                ToolTip.visible: hovered && !card.isPlaceholder

                function launchOrResumeSelectedApp(quitExistingApp)
                {
                    var runningId = appModel.getRunningAppId()
                    if (runningId !== 0 && runningId !== model.appid) {
                        if (quitExistingApp) {
                            quitAppDialog.appName = appModel.getRunningAppName()
                            quitAppDialog.segueToStream = true
                            quitAppDialog.nextAppName = model.name
                            quitAppDialog.nextAppIndex = index
                            quitAppDialog.open()
                        }

                        return
                    }

                    var component = Qt.createComponent("StreamSegue.qml")
                    var segue = component.createObject(stackView, {
                                                           "appName": model.name,
                                                           "session": appModel.createSessionForApp(index),
                                                           "isResume": runningId === model.appid
                                                       })
                    stackView.push(segue)
                }

                function doQuitGame() {
                    quitAppDialog.appName = appModel.getRunningAppName()
                    quitAppDialog.segueToStream = false
                    quitAppDialog.open()
                }

                function openContextMenu() {
                    // Keyboard/gamepad driven, so use open() instead of popup()
                    if (appContextMenu) {
                        appContextMenu.open()
                    }
                }

                onClicked: {
                    // The first click selects the app, the next one launches it
                    if (!isCurrent) {
                        userSelected = true
                        carousel.currentIndex = index
                        carousel.forceActiveFocus()
                    }
                    else if (!model.running) {
                        launchOrResumeSelectedApp(true)
                    }
                    else {
                        openContextMenu()
                    }
                }

                onPressAndHold: {
                    // popup() ensures the menu appears under the mouse cursor
                    if (appContextMenu.popup) {
                        appContextMenu.popup()
                    }
                    else {
                        // Qt 5.9 doesn't have popup()
                        appContextMenu.open()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton;
                    onClicked: {
                        parent.pressAndHold()
                    }
                }

                Keys.onReturnPressed: {
                    // Running games offer to resume or quit, others start right away
                    if (model.running) {
                        openContextMenu()
                    }
                    else {
                        launchOrResumeSelectedApp(true)
                    }
                }

                Keys.onEnterPressed: {
                    if (model.running) {
                        openContextMenu()
                    }
                    else {
                        launchOrResumeSelectedApp(true)
                    }
                }

                Keys.onMenuPressed: {
                    openContextMenu()
                }

                Keys.onUpPressed: {
                    playButton.forceActiveFocus(Qt.TabFocus)
                }

                Loader {
                    id: appContextMenuLoader
                    asynchronous: true
                    sourceComponent: NavigableMenu {
                        id: appContextMenu
                        initiator: appContextMenuLoader.parent
                        NavigableMenuItem {
                            text: model.running ? qsTr("Resume Game") : qsTr("Launch Game")
                            onTriggered: launchOrResumeSelectedApp(true)
                        }
                        NavigableMenuItem {
                            text: qsTr("Quit Game")
                            onTriggered: doQuitGame()
                            visible: model.running
                        }
                        NavigableMenuItem {
                            checkable: true
                            checked: model.directLaunch
                            text: qsTr("Direct Launch")
                            onTriggered: appModel.setAppDirectLaunch(model.index, !model.directLaunch)
                            enabled: !model.hidden

                            ToolTip.text: qsTr("Launch this app immediately when the host is selected, bypassing the app selection grid.")
                            ToolTip.delay: 1000
                            ToolTip.timeout: 3000
                            ToolTip.visible: hovered
                        }
                        NavigableMenuItem {
                            checkable: true
                            checked: model.hidden
                            text: qsTr("Hide Game")
                            onTriggered: appModel.setAppHidden(model.index, !model.hidden)
                            enabled: model.hidden || (!model.running && !model.directLaunch)

                            ToolTip.text: qsTr("Hide this game from the app grid. To access hidden games, right-click on the host and choose %1.").arg(qsTr("View All Apps"))
                            ToolTip.delay: 1000
                            ToolTip.timeout: 5000
                            ToolTip.visible: hovered
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.pagePadding
        visible: carousel.count === 0
        text: qsTr("This computer doesn't seem to have any applications or some applications are hidden")
        font.family: Theme.textFont
        font.pointSize: 18
        color: Theme.textSecondary
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    NavigableMessageDialog {
        id: quitAppDialog
        property string appName : ""
        property bool segueToStream : false
        property string nextAppName: ""
        property int nextAppIndex: 0
        text:qsTr("Are you sure you want to quit %1? Any unsaved progress will be lost.").arg(appName)
        standardButtons: Dialog.Yes | Dialog.No

        function quitApp() {
            var component = Qt.createComponent("QuitSegue.qml")
            var params = {"appName": appName, "quitRunningAppFn": function() { appModel.quitRunningApp() }}
            if (segueToStream) {
                // Store the session and app name if we're going to stream after
                // successfully quitting the old app.
                params.nextAppName = nextAppName
                params.nextSession = appModel.createSessionForApp(nextAppIndex)
            }
            else {
                params.nextAppName = null
                params.nextSession = null
            }

            stackView.push(component.createObject(stackView, params))
        }

        onAccepted: quitApp()
    }
}
