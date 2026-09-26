import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

import StreamingPreferences 1.0
import SdlGamepadKeyNavigation 1.0
import UiSound 1.0

// Shown when a stream ends: how long it lasted and how well it went, with the
// latency over the session. Play again starts the same app.
FocusScope {
    id: summaryView
    objectName: qsTr("Session ended")

    property string appName
    property string hostName
    property string hostUuid
    // Starts the same app again, like the reconnection of StreamSegue
    property var createSession: null
    // Summary saved by StreamHealthMonitor, see StreamingPreferences.getLastSession()
    property var summary: ({})

    readonly property var series: summary.rttSeries !== undefined ? summary.rttSeries : []
    readonly property int peakIndex: {
        var peak = 0
        for (var i = 1; i < series.length; i++) {
            if (series[i] > series[peak]) {
                peak = i
            }
        }
        return peak
    }

    readonly property var gamepadHints: [
        { glyph: "A", label: qsTr("Play again"), accent: true },
        { glyph: "B", label: qsTr("Back") }
    ]

    function formatDuration(secs) {
        var minutes = Math.max(1, Math.round(secs / 60))
        if (minutes < 60) {
            return qsTr("%1 min").arg(minutes)
        }
        return qsTr("%1 h %2").arg(Math.floor(minutes / 60)).arg(("0" + (minutes % 60)).slice(-2))
    }

    function playAgain() {
        if (createSession === null) {
            return
        }

        UiSound.play("launch")
        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": appName,
                                               "hostName": hostName,
                                               "hostUuid": hostUuid,
                                               "session": createSession(),
                                               "createSession": createSession
                                           })
        stackView.replace(summaryView, segue)
    }

    StackView.onActivated: {
        playButton.forceActiveFocus(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ? Qt.TabFocusReason : Qt.OtherFocusReason)
    }

    // One figure of the session
    component SummaryStat: Rectangle {
        property string label
        property string value
        property string unit
        property string note
        property color noteColor: Theme.textSecondary

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 118
        radius: 18
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 6

            Text {
                text: label.toUpperCase()
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 0.9
                color: Theme.textSecondary
            }

            RowLayout {
                spacing: 6

                Text {
                    Layout.alignment: Qt.AlignBaseline
                    text: value
                    font.family: Theme.displayFont
                    font.pixelSize: 30
                    font.weight: Font.Bold
                    font.letterSpacing: -0.6
                    color: Theme.text
                }

                Text {
                    Layout.alignment: Qt.AlignBaseline
                    text: unit
                    font.pixelSize: 14
                    color: Theme.textSecondary
                }
            }

            Text {
                visible: text !== ""
                text: note
                font.pixelSize: 13
                color: noteColor
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 48
        anchors.rightMargin: 48
        anchors.topMargin: 36
        anchors.bottomMargin: 28
        spacing: 24

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: qsTr("Session ended").toUpperCase()
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1.3
                    color: Theme.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: summaryView.appName
                    font.family: Theme.displayFont
                    font.pixelSize: 38
                    font.weight: Font.Bold
                    font.letterSpacing: -1
                    color: Theme.text
                    elide: Text.ElideRight
                }

                Text {
                    visible: text !== ""
                    text: {
                        var parts = []
                        if (hostName !== "") {
                            parts.push(hostName)
                        }
                        if (summary.endTime !== undefined) {
                            var end = summary.endTime
                            var start = new Date(end.getTime() - summary.durationSecs * 1000)
                            parts.push(qsTr("%1 → %2").arg(start.toLocaleTimeString(Qt.locale(), "HH:mm"))
                                                      .arg(end.toLocaleTimeString(Qt.locale(), "HH:mm")))
                        }
                        return parts.join(" · ")
                    }
                    font.pixelSize: 16
                    color: Theme.textSecondary
                }
            }

            KpButton {
                id: playButton
                variant: "primary"
                iconName: "play"
                iconFilled: true
                text: qsTr("Play again")
                sound: ""
                visible: summaryView.createSession !== null
                onClicked: summaryView.playAgain()

                KeyNavigation.right: homeButton
            }

            KpButton {
                id: homeButton
                iconName: "home"
                text: qsTr("Home")
                sound: "back"
                onClicked: stackView.pop(null)

                KeyNavigation.left: playButton
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 14

            SummaryStat {
                label: qsTr("Duration")
                value: summary.durationSecs !== undefined ? summaryView.formatDuration(summary.durationSecs) : "—"
            }

            SummaryStat {
                label: qsTr("Frame rate")
                value: summary.avgFps !== undefined ? Math.round(summary.avgFps) : "—"
                unit: qsTr("FPS avg.")
            }

            SummaryStat {
                label: qsTr("Latency")
                value: summary.avgRttMs ? Math.round(summary.avgRttMs) : "—"
                unit: summary.avgRttMs ? qsTr("ms avg.") : ""
                note: !summary.avgRttMs ? "" : summary.avgRttMs < 15 ? qsTr("Excellent") : summary.avgRttMs < 40 ? qsTr("Good") : qsTr("High")
                noteColor: !summary.avgRttMs ? Theme.textSecondary : summary.avgRttMs < 15 ? Theme.success : summary.avgRttMs < 40 ? Theme.accent2 : Theme.danger
            }

            SummaryStat {
                label: qsTr("Bitrate")
                value: summary.avgMbps !== undefined ? Math.round(summary.avgMbps) : "—"
                unit: qsTr("Mb/s avg.")
                note: summary.learnedPercent !== undefined && summary.learnedPercent < 100 ?
                          qsTr("Next stream at %1% of the bitrate").arg(summary.learnedPercent) :
                          summary.lossPercent !== undefined ? qsTr("%1% of frames lost").arg(Number(summary.lossPercent).toLocaleString(Qt.locale(), 'f', 1)) : ""
            }
        }

        // Latency over the session
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 210
            radius: 20
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            visible: summaryView.series.length > 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 28

                ColumnLayout {
                    Layout.preferredWidth: 220
                    Layout.maximumWidth: 220
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 8

                    Text {
                        text: qsTr("Latency during the session")
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: Theme.text
                    }

                    Text {
                        Layout.fillWidth: true
                        text: summaryView.series.length > 1 ?
                                  qsTr("Peak of %1 ms around minute %2.")
                                    .arg(summaryView.series[summaryView.peakIndex])
                                    .arg(Math.max(1, Math.round(summaryView.peakIndex / (summaryView.series.length - 1) * summary.durationSecs / 60))) : ""
                        font.pixelSize: 13
                        lineHeight: 1.3
                        color: Theme.textSecondary
                        wrapMode: Text.Wrap
                    }
                }

                Item {
                    id: chart
                    Layout.fillWidth: true
                    Layout.preferredWidth: 600
                    Layout.fillHeight: true

                    readonly property real maxValue: {
                        var max = 1
                        for (var i = 0; i < summaryView.series.length; i++) {
                            max = Math.max(max, summaryView.series[i])
                        }
                        return max * 1.15
                    }

                    // Middle guide with its value
                    Rectangle {
                        width: parent.width
                        height: 1
                        y: parent.height / 2
                        color: Theme.border
                    }

                    Text {
                        anchors.right: parent.right
                        y: parent.height / 2 - height - 2
                        text: qsTr("%1 ms").arg(Math.round(chart.maxValue / 2))
                        font.pixelSize: 11
                        color: Theme.textTertiary
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        anchors.bottom: parent.bottom
                        color: Theme.border
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: Theme.accent
                            strokeWidth: 2.5
                            fillColor: "transparent"
                            joinStyle: ShapePath.RoundJoin
                            capStyle: ShapePath.RoundCap

                            PathPolyline {
                                path: {
                                    var points = []
                                    var count = summaryView.series.length
                                    for (var i = 0; i < count; i++) {
                                        points.push(Qt.point(i / Math.max(1, count - 1) * chart.width,
                                                             chart.height - summaryView.series[i] / chart.maxValue * chart.height))
                                    }
                                    return points
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
