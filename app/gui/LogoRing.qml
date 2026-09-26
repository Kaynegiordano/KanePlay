import QtQuick
import QtQuick.Shapes

// The KanePlay mark inside two rings, with an ember arc going around while we wait
Item {
    id: ring

    property real size: 260
    property bool running: true
    property color arcColor: Theme.accent

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.border
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: ring.size * 0.1
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.raised
    }

    Shape {
        id: arc
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: ring.running

        ShapePath {
            strokeColor: ring.arcColor
            strokeWidth: 4
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.size / 2
                centerY: ring.size / 2
                radiusX: ring.size / 2 - 2
                radiusY: ring.size / 2 - 2
                startAngle: -90
                sweepAngle: 90
            }
        }

        // With reduced motion, the arc breathes in place instead of turning
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 1200
            loops: Animation.Infinite
            running: ring.running && ring.visible && Theme.motion
        }

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: ring.running && ring.visible && !Theme.motion
            NumberAnimation { from: 1; to: 0.3; duration: 900 }
            NumberAnimation { from: 0.3; to: 1; duration: 900 }
        }
    }

    Image {
        anchors.centerIn: parent
        source: "qrc:/res/kaneplay.svg"
        sourceSize.width: ring.size * 0.46
        sourceSize.height: ring.size * 0.46
    }
}
