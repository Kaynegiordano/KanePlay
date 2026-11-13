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

    // KaneMode: data received, "1,24" + "GB" like streaming/datausage.cpp
    function dataValue(bytes) {
        var mb = bytes / 1000000
        if (mb < 1000) {
            return Number(mb).toLocaleString(Qt.locale(), 'f', 0)
        }
        var gb = mb / 1000
        return Number(gb).toLocaleString(Qt.locale(), 'f', gb < 100 ? 2 : 0)
    }

    function dataUnit(bytes) {
        return bytes < 1000000000 ? qsTr("MB") : qsTr("GB")
    }

    // KaneMode: what got in the way, found by StreamHealthMonitor::findIssues()
    readonly property var issues: summary.issues !== undefined ? summary.issues : []

    function hasIssue(code) {
        for (var i = 0; i < issues.length; i++) {
            if (issues[i] === code) {
                return true
            }
        }
        return false
    }

    function decimal(value, digits) {
        return Number(value).toLocaleString(Qt.locale(), 'f', digits)
    }

    // A game slower than the stream is worth knowing, but the stream itself was fine
    readonly property int problemCount: issues.length - (hasIssue("hostfps") ? 1 : 0)

    readonly property string verdictTitle: problemCount === 0 ? qsTr("Smooth session") :
                                           problemCount === 1 ? qsTr("One thing got in the way") :
                                                                qsTr("%1 things got in the way").arg(problemCount)

    readonly property color verdictColor: problemCount === 0 ? Theme.success :
                                          hasIssue("loss") ? Theme.danger : Theme.accent2

    readonly property var diagnosisLines: {
        var lines = []
        if (problemCount === 0) {
            lines.push(qsTr("The network, the PC and this device all kept up."))
        }
        if (hasIssue("loss")) {
            var lost = qsTr("The network lost frames (%1%).").arg(decimal(summary.lossPercent, 1))
            if (summary.networkWifi && summary.networkSignal >= 0 && summary.networkSignal < 50) {
                lines.push(lost + " " + qsTr("The Wi-Fi signal was weak (%1%): move closer to the router or switch to the 5 GHz band.").arg(summary.networkSignal))
            }
            else if (summary.learnedPercent !== undefined && summary.learnedPercent < 100) {
                lines.push(lost + " " + qsTr("The next stream from this network starts at %1% of the bitrate.").arg(summary.learnedPercent))
            }
            else {
                lines.push(lost)
            }
        }
        if (hasIssue("jitter")) {
            lines.push(qsTr("Latency was uneven (±%1 ms): something else was probably using the network.").arg(Math.round(summary.avgRttVarianceMs)))
        }
        if (hasIssue("latency")) {
            lines.push(summary.remote ? qsTr("Latency was high (%1 ms): the connection between this device and the PC is slow.").arg(Math.round(summary.avgRttMs))
                                      : qsTr("Latency was high (%1 ms) for a home network: check the Wi-Fi or use a cable on the PC.").arg(Math.round(summary.avgRttMs)))
        }
        if (hasIssue("host")) {
            lines.push(qsTr("The PC took %1 ms to send each frame: its graphics card was overloaded by the game.").arg(Math.round(summary.avgHostMs)))
        }
        if (hasIssue("decode")) {
            lines.push(qsTr("This device took %1 ms to decode each frame: lower the resolution or the frame rate.").arg(decimal(summary.avgDecodeMs, 1)))
        }
        if (hasIssue("pacer")) {
            lines.push(qsTr("%1% of the frames were skipped when displaying them.").arg(decimal(summary.pacerDropPercent, 1)))
        }
        if (hasIssue("hostfps")) {
            lines.push(qsTr("The game ran at about %1 FPS on the PC, below the %2 FPS of the stream.").arg(Math.round(summary.avgReceivedFps)).arg(summary.targetFps))
        }
        return lines
    }

    // What the stream started with: network, bitrate and why it was lowered
    readonly property string networkLine: {
        if (summary.bitrateKbps === undefined) {
            return ""
        }
        var parts = []
        if (summary.networkName) {
            var network = summary.networkName
            if (summary.networkWifi && summary.networkSignal >= 0) {
                network += " (" + qsTr("signal %1%").arg(summary.networkSignal) + ")"
            }
            parts.push(network)
        }
        var limits = summary.bitrateLimits !== undefined ? summary.bitrateLimits : []
        var reasons = []
        for (var i = 0; i < limits.length; i++) {
            if (limits[i] === "learned") {
                reasons.push(qsTr("learned from earlier sessions"))
            }
            else if (limits[i] === "link") {
                reasons.push(qsTr("Wi-Fi link at %1 Mb/s").arg(summary.networkLinkMbps))
            }
            else if (limits[i] === "battery") {
                reasons.push(qsTr("battery saver"))
            }
        }
        var bitrate = qsTr("%1 Mb/s").arg(decimal(summary.bitrateKbps / 1000, summary.bitrateKbps < 10000 ? 1 : 0))
        if (reasons.length > 0 && summary.wantedBitrateKbps > summary.bitrateKbps) {
            bitrate = qsTr("%1 instead of %2 (%3)").arg(bitrate)
                                                   .arg(Math.round(summary.wantedBitrateKbps / 1000))
                                                   .arg(reasons.join(", "))
        }
        parts.push(bitrate)
        if (summary.loweredMode) {
            parts.push(qsTr("picture lowered to %1 FPS for this network").arg(summary.loweredMode))
        }
        return parts.join(" · ")
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
            columns: summary.dataBytes ? 5 : 4
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

            // KaneMode: what the session used, and the month so far
            SummaryStat {
                visible: !!summary.dataBytes
                label: qsTr("Data")
                value: summary.dataBytes ? summaryView.dataValue(summary.dataBytes) : "—"
                unit: summary.dataBytes ? summaryView.dataUnit(summary.dataBytes) : ""
                note: summary.monthBytes ? qsTr("%1 %2 this month").arg(summaryView.dataValue(summary.monthBytes)).arg(summaryView.dataUnit(summary.monthBytes)) : ""
            }
        }

        // KaneMode: the session in plain words
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: diagnosis.implicitHeight + 40
            radius: 20
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            visible: summary.issues !== undefined

            ColumnLayout {
                id: diagnosis
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 6

                RowLayout {
                    spacing: 10

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: summaryView.verdictColor
                    }

                    Text {
                        text: summaryView.verdictTitle
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: Theme.text
                    }
                }

                Repeater {
                    model: summaryView.diagnosisLines

                    Text {
                        Layout.fillWidth: true
                        text: modelData
                        font.pixelSize: 14
                        lineHeight: 1.3
                        color: Theme.textSecondary
                        wrapMode: Text.Wrap
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: summaryView.networkLine
                    font.pixelSize: 13
                    lineHeight: 1.3
                    color: Theme.textTertiary
                    wrapMode: Text.Wrap
                }
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
