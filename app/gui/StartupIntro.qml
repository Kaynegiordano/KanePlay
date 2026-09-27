import QtQuick 2.9
import QtMultimedia

import StreamingPreferences 1.0

// The KanePlay intro, played fullscreen before KanePlay shows up.
// Any key, gamepad button or click skips it.
Rectangle {
    id: intro

    signal finished()

    property bool done: false

    // The background of the video, for the bars around it
    color: "#090A0D"

    function finish()
    {
        if (done) {
            return
        }
        done = true
        fadeOut.start()
    }

    MediaPlayer {
        id: player
        source: "qrc:/res/intro.mp4"
        videoOutput: videoOutput
        audioOutput: AudioOutput {
            // As loud as the interface sounds
            volume: StreamingPreferences.uiSounds ? StreamingPreferences.uiSoundVolume / 100 : 0
        }

        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                intro.finish()
            }
        }

        onErrorOccurred: function(error, errorString) {
            console.warn("Startup intro failed:", errorString)
            intro.finish()
        }
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.BlankCursor
        onClicked: intro.finish()
    }

    Keys.onPressed: function(event) {
        event.accepted = true
        intro.finish()
    }

    // Never hide KanePlay behind a stalled video
    Timer {
        interval: 8000
        running: true
        onTriggered: intro.finish()
    }

    SequentialAnimation {
        id: fadeOut
        NumberAnimation {
            target: intro
            property: "opacity"
            to: 0
            duration: 350
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                player.stop()
                intro.finished()
            }
        }
    }

    Component.onCompleted: {
        forceActiveFocus()
        player.play()
    }
}
