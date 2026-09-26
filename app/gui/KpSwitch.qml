import QtQuick

// On/off switch of the design, driven by the tile that holds it
Rectangle {
    id: kpSwitch

    property bool checked: false

    implicitWidth: 52
    implicitHeight: 30
    radius: height / 2
    color: checked ? Theme.accent : Theme.raised
    border.width: checked ? 0 : 1
    border.color: Theme.border

    Behavior on color {
        ColorAnimation { duration: Theme.durationFast }
    }

    Rectangle {
        width: kpSwitch.checked ? 24 : 22
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: kpSwitch.checked ? kpSwitch.width - width - 3 : 4
        color: kpSwitch.checked ? Theme.accentText : Theme.textSecondary

        Behavior on x {
            NumberAnimation { duration: Theme.durationFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
    }
}
