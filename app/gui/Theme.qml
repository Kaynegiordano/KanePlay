pragma Singleton

import QtQuick 2.9

import SystemProperties 1.0

// Colors, fonts, sizes and motion shared by every screen of the UI (KanePlay "Élan" design)
QtObject {
    // Surfaces, from the window background up
    readonly property color background: "#0E0F13"
    readonly property color surfaceAlt: "#14161C"
    readonly property color surface: "#181A21"
    readonly property color raised: "#22252E"
    readonly property color hover: "#2A2E38"
    readonly property color border: "#2E323D"

    // Text
    readonly property color text: "#F4F1EC"
    readonly property color textSecondary: "#A9ABB4"
    readonly property color textTertiary: "#8A8D98"

    // Accent ("ember") and status colors
    readonly property color accent: "#FF6A3D"
    readonly property color accentHover: "#FF8A63"
    readonly property color accentText: "#14100C"
    readonly property color accent2: "#FFC857"
    readonly property color success: "#5FD39A"
    readonly property color warning: "#FFC857"
    readonly property color danger: "#FF7A70"

    // Unbounded for titles and key figures, Manrope for everything else.
    // Both ship with the app, see main.cpp.
    readonly property string displayFont: "Unbounded"
    readonly property string textFont: "Manrope"

    readonly property int radiusSmall: 12
    readonly property int radius: 16
    readonly property int radiusLarge: 24

    readonly property int pagePadding: 40

    // Motion: everything moves fast and settles softly. With reduced motion
    // (an accessibility setting of the OS), only fades remain.
    readonly property bool motion: !SystemProperties.reducedMotion
    readonly property int durationFast: 120
    readonly property int durationStandard: 200
    readonly property int durationAmple: 320
    readonly property int durationLaunch: 480
    // cubic-bezier(0.2, 0.8, 0.2, 1), for Easing.BezierSpline
    readonly property var easeOut: [0.2, 0.8, 0.2, 1, 1, 1]
}
