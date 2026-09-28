pragma Singleton

import QtQuick 2.9

import SystemProperties 1.0

// Colors, fonts, sizes and motion shared by every screen of the UI (KanePlay "Élan" design).
// Embedded in KaneMode, the UI takes KaneMode's look instead, inspired by SteamOS: deep blue-black
// surfaces, KaneMode's accent color (blue by default), Segoe UI.
QtObject {
    readonly property bool kaneMode: SystemProperties.embedded
    readonly property color kaneModeAccent: SystemProperties.kaneModeAccent !== "" ? SystemProperties.kaneModeAccent : "#1A9FFF"

    // Surfaces, from the window background up
    readonly property color background: kaneMode ? "#0B0E13" : "#0E0F13"
    readonly property color surfaceAlt: kaneMode ? "#12161D" : "#14161C"
    readonly property color surface: kaneMode ? "#161B23" : "#181A21"
    readonly property color raised: kaneMode ? "#1D232D" : "#22252E"
    readonly property color hover: kaneMode ? "#252D39" : "#2A2E38"
    readonly property color border: kaneMode ? "#262D38" : "#2E323D"

    // Text
    readonly property color text: kaneMode ? "#E6E9EE" : "#F4F1EC"
    readonly property color textSecondary: kaneMode ? "#AEB6C2" : "#A9ABB4"
    readonly property color textTertiary: kaneMode ? "#8C95A3" : "#8A8D98"

    // Accent ("ember", or KaneMode's) and status colors
    readonly property color accent: kaneMode ? kaneModeAccent : "#FF6A3D"
    readonly property color accentHover: kaneMode ? Qt.lighter(kaneModeAccent, 1.18) : "#FF8A63"
    readonly property color accentText: kaneMode ? "#FFFFFF" : "#14100C"
    readonly property color accent2: kaneMode ? "#6A5CFF" : "#FFC857"
    readonly property color success: kaneMode ? "#3FCA5A" : "#5FD39A"
    readonly property color warning: "#FFC857"
    readonly property color danger: kaneMode ? "#E5484D" : "#FF7A70"

    // Unbounded for titles and key figures, Manrope for everything else.
    // Both ship with the app, see main.cpp. KaneMode uses Windows' own typeface.
    readonly property string displayFont: kaneMode ? "Segoe UI Variable Display" : "Unbounded"
    readonly property string textFont: kaneMode ? "Segoe UI Variable Text" : "Manrope"

    readonly property int radiusSmall: kaneMode ? 6 : 12
    readonly property int radius: kaneMode ? 8 : 16
    readonly property int radiusLarge: kaneMode ? 12 : 24

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
