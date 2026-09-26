import QtQuick
import QtQuick.Shapes

// A small circular progress indicator: an ember arc turning on a faint track
Item {
    id: spinner

    property real size: 32
    property real lineWidth: 3
    property color color: Theme.accent
    property bool running: visible

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: spinner.lineWidth
        border.color: Theme.raised
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: spinner.color
            strokeWidth: spinner.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: spinner.size / 2
                centerY: spinner.size / 2
                radiusX: (spinner.size - spinner.lineWidth) / 2
                radiusY: (spinner.size - spinner.lineWidth) / 2
                startAngle: -90
                sweepAngle: 110
            }
        }

        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: spinner.running
        }
    }
}
