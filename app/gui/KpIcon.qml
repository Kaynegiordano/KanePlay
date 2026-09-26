import QtQuick
import QtQuick.Shapes

import "Icons.js" as Icons

// A stroke icon of the design (see Icons.js), drawn sharp at any size and color
Item {
    id: icon

    property string name
    property color color: Theme.text
    property real size: 22
    property real strokeWidth: 2
    property bool filled: false

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        scale: icon.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: icon.color
            strokeWidth: icon.strokeWidth
            fillColor: icon.filled ? icon.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: Icons.paths[icon.name] || ""
            }
        }
    }
}
