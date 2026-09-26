import QtQuick
import QtQuick.Controls

Dialog {
    modal: true
    anchors.centerIn: Overlay.overlay
    padding: 32

    background: Rectangle {
        radius: 28
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0.03, 0.035, 0.047, 0.72)
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationAmple; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        NumberAnimation { property: "scale"; from: Theme.motion ? 0.96 : 1; to: 1; duration: Theme.durationAmple; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    }

    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationStandard }
    }

    onClosed: {
        // We must force focus back to the last item. If we don't,
        // gamepad and keyboard navigation will break after a
        // dialog appears.
        stackView.forceActiveFocus()
    }
}
