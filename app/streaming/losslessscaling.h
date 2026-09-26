#pragma once

#include <QString>

// Lossless Scaling (a Steam app) generates frames for any window. KanePlay
// starts it and turns it on for the stream window with its own hotkey, since
// it has no other interface. Everything returns false on other platforms.
namespace LosslessScaling
{
    // Its Steam app ID
    constexpr const char* k_SteamAppId = "993090";

    // LosslessScaling.exe when it's installed, or an empty string
    QString installedExe();

    bool isRunning();

    // Starts it from its install, without Steam
    bool launch();

    // Presses its scaling hotkey, as set in its settings (Ctrl+Alt+S by
    // default). It scales the foreground window.
    bool pressHotkey();
}
