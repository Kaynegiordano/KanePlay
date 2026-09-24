pragma Singleton

import QtQuick 2.9

// Colors, fonts and sizes shared by every screen of the UI
QtObject {
    // Surfaces, from the window background up
    readonly property color background: "#0B0D12"
    readonly property color surface: "#151A24"
    readonly property color surfaceAlt: "#10141C"
    readonly property color raised: "#1F2533"
    readonly property color border: "#2A3142"

    // Text
    readonly property color text: "#F2F4F7"
    readonly property color textSecondary: "#A3AAB8"
    readonly property color textTertiary: "#7F8BA3"

    // Accent and status colors
    readonly property color accent: "#8FB4FF"
    readonly property color accentHover: "#B7CEFF"
    readonly property color accentText: "#0B0D12"
    readonly property color success: "#5FD39A"
    readonly property color warning: "#F2C66D"
    readonly property color danger: "#FF8A80"

    // Windows 11 ships variable Segoe UI faces tuned for large and small text.
    // Other platforms fall back to their default UI font.
    readonly property string displayFont: "Segoe UI Variable Display"
    readonly property string textFont: "Segoe UI Variable Text"

    readonly property int radiusSmall: 10
    readonly property int radius: 14
    readonly property int radiusLarge: 18

    readonly property int pagePadding: 64
}
