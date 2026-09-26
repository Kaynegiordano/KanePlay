import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

import AppModel 1.0
import ComputerManager 1.0
import StreamingPreferences 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import UiSound 1.0

// Library of one PC: its apps as a grid of covers, the selected one detailed on the right
FocusScope {
    property int computerIndex
    property AppModel appModel : createModel()
    property bool activated
    property bool showHiddenGames
    property bool showGames

    // Set once the user moved the selection, so a running app
    // reported later doesn't steal it back
    property bool userSelected: false

    // App to start as soon as the library opens, for the Play and Desktop
    // buttons of the home screen (by ID, else by name)
    property int autoLaunchAppId: 0
    property string autoLaunchAppName: ""

    property bool favoritesOnly: false
    property int favoriteCount: 0

    // Summary of the last stream from this PC, see StreamHealthMonitor
    property var lastSession: ({})

    readonly property var selectedApp: grid.currentItem

    readonly property var gamepadHints: [
        { glyph: "A", label: selectedApp !== null && selectedApp.running ? qsTr("Resume") : qsTr("Play"), accent: true },
        { glyph: "X", label: qsTr("Options") },
        { glyph: "B", label: qsTr("Back") }
    ]

    id: appView
    focus: true

    function tryAutoLaunch()
    {
        if (autoLaunchAppId === 0 && autoLaunchAppName === "") {
            return
        }

        var appIndex = appModel.findApp(autoLaunchAppId, autoLaunchAppName)
        if (appIndex >= 0) {
            autoLaunchAppId = 0
            autoLaunchAppName = ""
            grid.currentIndex = appIndex
            grid.forceLayout()
            grid.currentItem.launchOrResumeSelectedApp(true)
        }
    }

    function refreshStatus()
    {
        lastSession = StreamingPreferences.getLastSession(appModel.getComputerUuid())
        favoriteCount = appModel.getFavoriteCount()
    }

    function computerLost()
    {
        // Go back to the PC view on PC loss
        stackView.pop()
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

    function streamProfile()
    {
        var parts = []
        parts.push(StreamingPreferences.autoResolution ? qsTr("Auto") : StreamingPreferences.height + "p")
        parts.push(StreamingPreferences.autoFps ? qsTr("Automatic FPS") : qsTr("%1 FPS").arg(StreamingPreferences.fps))
        return parts.join(" · ")
    }

    function setFavoritesOnly(only)
    {
        if (favoritesOnly !== only) {
            favoritesOnly = only
            userSelected = false
            appModel.setFavoritesOnly(only)
            grid.currentIndex = 0
        }
    }

    function toggleFavorite()
    {
        if (selectedApp !== null) {
            appModel.setAppFavorite(grid.currentIndex, !selectedApp.favorite)
            UiSound.play(selectedApp !== null && selectedApp.favorite ? "on" : "off")
            favoriteCount = appModel.getFavoriteCount()
        }
    }

    StackView.onActivated: {
        appModel.computerLost.connect(computerLost)
        activated = true
        refreshStatus()

        grid.forceActiveFocus(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ? Qt.TabFocusReason : Qt.OtherFocusReason)

        if (autoLaunchAppId !== 0 || autoLaunchAppName !== "") {
            // The app list may still be loading, see onCountChanged of the grid
            showGames = true
            tryAutoLaunch()
        }
        else if (!showGames && !showHiddenGames) {
            // Check if there's a direct launch app
            var directLaunchAppIndex = appModel.getDirectLaunchAppIndex();
            if (directLaunchAppIndex >= 0) {
                // Start the direct launch app if nothing else is running
                grid.currentIndex = directLaunchAppIndex
                grid.forceLayout()
                grid.currentItem.launchOrResumeSelectedApp(false)

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

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding
        anchors.topMargin: 8
        anchors.bottomMargin: 24
        spacing: 24

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // The PC we're browsing, back to the home screen when clicked
                KpButton {
                    implicitHeight: 38
                    leftPadding: 14
                    rightPadding: 16
                    fontSize: 14
                    iconName: "monitor"
                    iconSize: 16
                    text: appView.objectName
                    sound: "back"
                    onClicked: stackView.pop(null)

                    KeyNavigation.right: allChip
                    KeyNavigation.down: grid
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 24
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    color: Theme.border
                }

                FilterChip {
                    id: allChip
                    text: qsTr("All")
                    selected: !favoritesOnly
                    onClicked: setFavoritesOnly(false)

                    KeyNavigation.right: favoritesChip
                    KeyNavigation.down: grid
                }

                FilterChip {
                    id: favoritesChip
                    text: favoriteCount > 0 ? qsTr("Favorites · %1").arg(favoriteCount) : qsTr("Favorites")
                    selected: favoritesOnly
                    onClicked: setFavoritesOnly(true)

                    KeyNavigation.left: allChip
                    KeyNavigation.down: grid
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: qsTr("%n app(s)", "", grid.count)
                    font.pixelSize: 14
                    color: Theme.textTertiary
                }
            }

            GridView {
                id: grid

                readonly property int columns: Math.max(3, Math.floor((width + 16) / 190))

                Layout.fillWidth: true
                Layout.fillHeight: true
                // Room for the focus ring and the lift of the selected cover
                topMargin: 14
                bottomMargin: 14
                leftMargin: 14
                rightMargin: 0
                clip: true
                cellWidth: Math.floor((width - leftMargin) / columns)
                cellHeight: Math.floor((cellWidth - 16) * 4 / 3) + 16
                model: appModel
                focus: true
                keyNavigationEnabled: false
                highlightMoveDuration: Theme.durationStandard
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 1000

                onCountChanged: tryAutoLaunch()

                Keys.onLeftPressed: {
                    userSelected = true
                    moveCurrentIndexLeft()
                }
                Keys.onDownPressed: {
                    userSelected = true
                    moveCurrentIndexDown()
                }
                Keys.onRightPressed: {
                    // Past the last column, move on to the Play button
                    if ((currentIndex + 1) % columns === 0 || currentIndex === count - 1) {
                        playButton.forceActiveFocus(Qt.TabFocusReason)
                    }
                    else {
                        userSelected = true
                        moveCurrentIndexRight()
                    }
                }
                Keys.onUpPressed: {
                    if (currentIndex < columns) {
                        (favoritesOnly ? favoritesChip : allChip).forceActiveFocus(Qt.TabFocusReason)
                    }
                    else {
                        userSelected = true
                        moveCurrentIndexUp()
                    }
                }
                Keys.onReturnPressed: {
                    if (currentItem !== null) {
                        currentItem.launchOrResumeSelectedApp(true)
                    }
                }
                Keys.onEnterPressed: {
                    if (currentItem !== null) {
                        currentItem.launchOrResumeSelectedApp(true)
                    }
                }
                Keys.onMenuPressed: appOptionsMenu.open()

                delegate: ItemDelegate {
                    id: card

                    readonly property bool isCurrent: GridView.isCurrentItem
                    readonly property string appName: model.name
                    readonly property int appId: model.appid
                    readonly property bool running: model.running
                    readonly property bool hidden: model.hidden
                    readonly property bool directLaunch: model.directLaunch
                    readonly property bool favorite: model.favorite
                    readonly property string boxArt: model.boxart
                    property bool isPlaceholder: false

                    width: grid.cellWidth - 16
                    height: grid.cellHeight - 16
                    padding: 0
                    focusPolicy: Qt.NoFocus

                    // Dim the app if it's hidden
                    opacity: hidden ? 0.4 : 1.0

                    // The selected cover grows a little
                    scale: isCurrent && grid.activeFocus && Theme.motion ? 1.05 : 1.0
                    z: isCurrent ? 1 : 0

                    Behavior on scale {
                        NumberAnimation { duration: Theme.durationStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                    }

                    Component.onCompleted: {
                        // Start on the running app unless the user picked something else.
                        // Later, since the grid resets its selection while it fills.
                        if (model.running) {
                            Qt.callLater(function() {
                                if (!userSelected) {
                                    grid.currentIndex = index
                                }
                            })
                        }
                    }

                    onRunningChanged: {
                        if (running && !userSelected) {
                            grid.currentIndex = index
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radius
                        color: Theme.raised

                        // Focus ring around the selected cover
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -5
                            radius: parent.radius + 5
                            color: "transparent"
                            border.width: 3
                            border.color: Theme.accent
                            // Fainter while the focus is on the detail panel
                            opacity: card.isCurrent ? (grid.activeFocus ? 1 : 0.35) : 0

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.durationStandard }
                            }
                        }
                    }

                    contentItem: Item {
                        Image {
                            id: art
                            anchors.fill: parent
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
                            radius: Theme.radius
                            visible: false
                            layer.enabled: true
                        }

                        MultiEffect {
                            anchors.fill: art
                            source: art
                            maskEnabled: true
                            maskSource: artMask
                            visible: !card.isPlaceholder && art.status === Image.Ready
                        }

                        // No box art: a large icon instead
                        KpIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height * 0.3
                            visible: card.isPlaceholder || art.status !== Image.Ready
                            name: card.appName.toLowerCase() === "desktop" ? "desktop" : "gamepad"
                            size: 44
                            strokeWidth: 1.6
                            color: Qt.rgba(1, 1, 1, 0.5)
                        }

                        // Name of the app
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: nameText.implicitHeight + 24
                            bottomLeftRadius: Theme.radius
                            bottomRightRadius: Theme.radius
                            color: Qt.rgba(0.04, 0.043, 0.055, 0.78)

                            Text {
                                id: nameText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                text: card.appName
                                font.family: Theme.textFont
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: Theme.text
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            visible: card.running
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 10
                            implicitWidth: runningText.implicitWidth + 20
                            implicitHeight: 24
                            radius: 12
                            color: Theme.success

                            Text {
                                id: runningText
                                anchors.centerIn: parent
                                text: qsTr("Running")
                                font.family: Theme.textFont
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#0B1A12"
                            }
                        }

                        Rectangle {
                            visible: card.favorite
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 10
                            width: 28
                            height: 28
                            radius: 14
                            color: Qt.rgba(0.04, 0.043, 0.055, 0.78)

                            KpIcon {
                                anchors.centerIn: parent
                                name: "star"
                                size: 16
                                filled: true
                                color: Theme.accent2
                            }
                        }
                    }

                    // Display a tooltip with the full name
                    ToolTip.text: model.name
                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered

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

                        UiSound.play("launch")

                        var appIndex = index
                        var component = Qt.createComponent("StreamSegue.qml")
                        var segue = component.createObject(stackView, {
                                                               "appName": model.name,
                                                               "hostName": appView.objectName,
                                                               "hostUuid": appModel.getComputerUuid(),
                                                               "session": appModel.createSessionForApp(index),
                                                               "isResume": runningId === model.appid,
                                                               // Lets the segue start the same app again after a network drop
                                                               "createSession": function() { return appModel.createSessionForApp(appIndex) }
                                                           })
                        stackView.push(segue)
                    }

                    function doQuitGame() {
                        quitAppDialog.appName = appModel.getRunningAppName()
                        quitAppDialog.segueToStream = false
                        quitAppDialog.open()
                    }

                    onClicked: {
                        // The first click selects the app, the next one launches it
                        if (!isCurrent) {
                            userSelected = true
                            UiSound.play("move")
                            grid.currentIndex = index
                            grid.forceActiveFocus()
                        }
                        else {
                            launchOrResumeSelectedApp(true)
                        }
                    }

                    onPressAndHold: {
                        grid.currentIndex = index
                        appOptionsMenu.popup()
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: parent.pressAndHold()
                    }
                }
            }
        }

        // The selected app, detailed
        Rectangle {
            Layout.preferredWidth: 340
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            visible: selectedApp !== null

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 160

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: Theme.raised
                    }

                    Image {
                        id: detailArt
                        anchors.fill: parent
                        source: selectedApp !== null ? selectedApp.boxArt : ""
                        sourceSize.width: 600
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }

                    Rectangle {
                        id: detailArtMask
                        anchors.fill: parent
                        radius: Theme.radius
                        visible: false
                        layer.enabled: true
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: detailArt
                        maskEnabled: true
                        maskSource: detailArtMask
                        visible: selectedApp !== null && !selectedApp.isPlaceholder && detailArt.status === Image.Ready
                    }

                    KpIcon {
                        anchors.centerIn: parent
                        visible: selectedApp !== null && (selectedApp.isPlaceholder || detailArt.status !== Image.Ready)
                        name: selectedApp !== null && selectedApp.appName.toLowerCase() === "desktop" ? "desktop" : "gamepad"
                        size: 56
                        strokeWidth: 1.5
                        color: Qt.rgba(1, 1, 1, 0.5)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: selectedApp !== null ? selectedApp.appName : ""
                        font.family: Theme.displayFont
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        font.letterSpacing: -0.5
                        color: Theme.text
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: selectedApp !== null && selectedApp.running ? Theme.success : Theme.textTertiary
                        }

                        Text {
                            text: selectedApp !== null && selectedApp.running ? qsTr("Running on %1").arg(appView.objectName) :
                                                                                qsTr("Ready to launch")
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: selectedApp !== null && selectedApp.running ? Theme.success : Theme.textSecondary
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        visible: selectedApp !== null && lastSession && lastSession.endTime !== undefined &&
                                 lastSession.appName === selectedApp.appName

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Last session")
                            font.pixelSize: 14
                            color: Theme.textSecondary
                        }

                        Text {
                            text: lastSession && lastSession.endTime ? formatTimeAgo(lastSession.endTime) : ""
                            font.pixelSize: 14
                            color: Theme.text
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Profile")
                            font.pixelSize: 14
                            color: Theme.textSecondary
                        }

                        Text {
                            text: streamProfile()
                            font.pixelSize: 14
                            color: Theme.text
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                KpButton {
                    id: playButton
                    Layout.fillWidth: true
                    variant: "primary"
                    iconName: "play"
                    iconFilled: true
                    text: selectedApp !== null && selectedApp.running ? qsTr("Resume") : qsTr("Play")
                    sound: ""
                    onClicked: selectedApp.launchOrResumeSelectedApp(true)

                    Keys.onLeftPressed: grid.forceActiveFocus(Qt.TabFocusReason)
                    KeyNavigation.down: favoriteButton
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    KpButton {
                        id: favoriteButton
                        Layout.fillWidth: true
                        implicitHeight: 46
                        fontSize: 14
                        iconName: "star"
                        iconSize: 18
                        iconFilled: selectedApp !== null && selectedApp.favorite
                        text: selectedApp !== null && selectedApp.favorite ? qsTr("Favorite") : qsTr("Add to favorites")
                        sound: ""
                        onClicked: toggleFavorite()

                        Keys.onLeftPressed: grid.forceActiveFocus(Qt.TabFocusReason)
                        KeyNavigation.up: playButton
                        KeyNavigation.right: quitButton.visible ? quitButton : null
                    }

                    KpButton {
                        id: quitButton
                        Layout.fillWidth: true
                        implicitHeight: 46
                        visible: selectedApp !== null && selectedApp.running
                        variant: "danger"
                        fontSize: 14
                        iconName: "power"
                        iconSize: 18
                        text: qsTr("Quit")
                        onClicked: selectedApp.doQuitGame()

                        KeyNavigation.left: favoriteButton
                        KeyNavigation.up: playButton
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.pagePadding
        visible: grid.count === 0
        text: favoritesOnly ? qsTr("No favorites yet. Press X on a game to add it.") :
                              qsTr("This computer doesn't seem to have any applications or some applications are hidden")
        font.pixelSize: 20
        color: Theme.textSecondary
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    NavigableMenu {
        id: appOptionsMenu
        initiator: grid
        x: grid.currentItem !== null ? grid.currentItem.x + Theme.pagePadding + 20 : 0
        y: grid.currentItem !== null ? grid.currentItem.y - grid.contentY + 120 : 0

        NavigableMenuItem {
            text: selectedApp !== null && selectedApp.running ? qsTr("Resume Game") : qsTr("Launch Game")
            onTriggered: selectedApp.launchOrResumeSelectedApp(true)
        }
        NavigableMenuItem {
            text: qsTr("Quit Game")
            onTriggered: selectedApp.doQuitGame()
            visible: selectedApp !== null && selectedApp.running
        }
        NavigableMenuItem {
            checkable: true
            checked: selectedApp !== null && selectedApp.favorite
            text: qsTr("Favorite")
            onTriggered: toggleFavorite()
        }
        NavigableMenuItem {
            checkable: true
            checked: selectedApp !== null && selectedApp.directLaunch
            text: qsTr("Direct Launch")
            onTriggered: appModel.setAppDirectLaunch(grid.currentIndex, !selectedApp.directLaunch)
            enabled: selectedApp !== null && !selectedApp.hidden

            ToolTip.text: qsTr("Launch this app immediately when the host is selected, bypassing the app selection grid.")
            ToolTip.delay: 1000
            ToolTip.timeout: 3000
            ToolTip.visible: hovered
        }
        NavigableMenuItem {
            checkable: true
            checked: selectedApp !== null && selectedApp.hidden
            text: qsTr("Hide Game")
            onTriggered: appModel.setAppHidden(grid.currentIndex, !selectedApp.hidden)
            enabled: selectedApp !== null && (selectedApp.hidden || (!selectedApp.running && !selectedApp.directLaunch))

            ToolTip.text: qsTr("Hide this game from the app grid. To access hidden games, right-click on the host and choose %1.").arg(qsTr("View All Apps"))
            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
        }
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
