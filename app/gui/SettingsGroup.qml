import QtQuick 2.9
import QtQuick.Controls 2.2

// A section of the settings page, drawn as a rounded card with a large heading
GroupBox {
    id: group
    padding: 28
    topPadding: 28 + label.implicitHeight + 12
    font.pointSize: 12

    label: Text {
        x: group.leftPadding
        y: 26
        text: group.title
        font.family: Theme.displayFont
        font.pointSize: 18
        font.weight: Font.Bold
        color: Theme.text
    }

    background: Rectangle {
        y: 0
        width: group.width
        height: group.height
        radius: Theme.radiusLarge
        color: Theme.surface
    }
}
