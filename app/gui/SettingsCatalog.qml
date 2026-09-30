import QtQuick

import StreamingPreferences 1.0
import SystemProperties 1.0
import ComputerManager 1.0

// Every setting of the app, described once for the settings screens: its label, what it
// does, its category, how to read and change it, and its default value.
//
// A setting is an object with:
//  - key, category, icon, label, desc
//  - type: "bool", "choice" or "slider"
//  - get() and set(value); def(), the default value
//  - available() (hidden when false) and enabled() (dimmed when false)
//  - locked(): why a dimmed setting is off, and unlock(), which turns on what it
//    needs (A on the dimmed tile)
//  - choices: options(), a list of { label, value }; "custom" asks for a value (see customRequested)
//  - sliders: from, to(), step, format(value)
//  - companions: keys of settings shown under it in its side sheet
QtObject {
    id: catalog

    // Position of the window, to find the display it is on (set by the settings screens)
    property real screenX: 0
    property real screenY: 0

    // The user picked "Custom…" for a resolution or a frame rate
    signal customRequested(string key)

    readonly property var categories: [
        { key: "all", label: qsTr("All") },
        { key: "framegen", label: qsTr("Frame generation") },
        { key: "image", label: qsTr("Picture") },
        { key: "network", label: qsTr("Network") },
        { key: "audio", label: qsTr("Audio") },
        { key: "gamepad", label: qsTr("Gamepads") },
        { key: "input", label: qsTr("Mouse and keyboard") },
        { key: "system", label: qsTr("System") }
    ]

    readonly property var categoryIcons: ({
        framegen: "layers", image: "image", network: "wifi", audio: "volume",
        gamepad: "gamepad", input: "mouse", system: "sliders"
    })

    function categoryLabel(key) {
        for (var i = 0; i < categories.length; i++) {
            if (categories[i].key === key) {
                return categories[i].label
            }
        }
        return ""
    }

    readonly property var settings: build()

    function find(key) {
        for (var i = 0; i < settings.length; i++) {
            if (settings[i].key === key) {
                return settings[i]
            }
        }
        return null
    }

    function isAvailable(setting) {
        return setting.available === undefined || setting.available()
    }

    function isEnabled(setting) {
        return setting.enabled === undefined || setting.enabled()
    }

    // Settings that don't apply right now (dimmed) don't count as changed
    function isModified(setting) {
        if (setting.def === undefined || !isEnabled(setting)) {
            return false
        }
        return String(setting.get()) !== String(setting.def())
    }

    function reset(setting) {
        if (setting.def !== undefined && isModified(setting)) {
            setting.set(setting.def())
        }
    }

    function optionLabel(setting, value) {
        var options = setting.options()
        for (var i = 0; i < options.length; i++) {
            if (String(options[i].value) === String(value)) {
                return options[i].label
            }
        }
        return String(value)
    }

    // The current value, as shown on a tile
    function valueText(setting) {
        if (setting.type === "bool") {
            return setting.get() ? qsTr("On") : qsTr("Off")
        }
        else if (setting.type === "choice") {
            return optionLabel(setting, setting.get())
        }
        return setting.format(setting.get())
    }

    // Moves a choice to its next option, skipping "Custom…"
    function cycle(setting, direction) {
        var options = setting.options().filter(function(option) { return option.value !== "custom" })
        var current = String(setting.get())
        var index = 0
        for (var i = 0; i < options.length; i++) {
            if (String(options[i].value) === current) {
                index = i
                break
            }
        }
        index = (index + direction + options.length) % options.length
        setting.set(options[index].value)
    }

    function displayIndex() {
        return SystemProperties.getDisplayIndexForOrigin(screenX, screenY)
    }

    // Why a dimmed setting is off
    function lockReason(setting) {
        return setting.locked !== undefined ? setting.locked() : ""
    }

    // Frame pacing and VRR need V-Sync
    function pacingAllowed() {
        return StreamingPreferences.enableVsync
    }

    function pacingLockReason() {
        return qsTr("Needs V-Sync · A turns it on")
    }

    function unlockPacing() {
        StreamingPreferences.enableVsync = true
    }

    function defaultBitrate() {
        return StreamingPreferences.getDefaultBitrate(StreamingPreferences.width, StreamingPreferences.height,
                                                      StreamingPreferences.fps, StreamingPreferences.enableYUV444)
    }

    // The bitrate follows the resolution and frame rate until the user sets it by hand
    function updateDefaultBitrate() {
        if (StreamingPreferences.autoAdjustBitrate) {
            StreamingPreferences.bitrateKbps = defaultBitrate()
        }
    }

    function setResolution(width, height, auto) {
        StreamingPreferences.autoResolution = auto

        if (auto) {
            // The stream will match whichever display it ends up on, but save the
            // resolution of the display we're on now. It is the value we fall back
            // to if detection fails, and what the default bitrate is based on until
            // the stream starts.
            var currentRes = SystemProperties.getSafeAreaResolution(displayIndex())
            var maxPixels = SystemProperties.maximumResolution.width * SystemProperties.maximumResolution.height
            if (currentRes.width === 0 || currentRes.height === 0 ||
                    (maxPixels > 0 && currentRes.width * currentRes.height > maxPixels)) {
                // No usable display data, or the display exceeds what the decoder
                // supports, so leave the saved resolution alone
                return
            }
            width = currentRes.width
            height = currentRes.height
        }

        if (StreamingPreferences.width !== width || StreamingPreferences.height !== height) {
            StreamingPreferences.width = width
            StreamingPreferences.height = height
            updateDefaultBitrate()
        }
    }

    function setFps(fps, auto) {
        StreamingPreferences.autoFps = auto

        if (auto) {
            // Same as the resolution: save the refresh rate of the current display
            fps = SystemProperties.getRefreshRate(displayIndex())
            if (fps === 0) {
                return
            }
        }

        if (StreamingPreferences.fps !== fps) {
            StreamingPreferences.fps = fps
            updateDefaultBitrate()
        }
    }

    function resolutionOptions() {
        var options = [
            { label: qsTr("Automatic"), value: "auto" },
            { label: "720p", value: "1280x720" },
            { label: "1080p", value: "1920x1080" },
            { label: "1440p", value: "2560x1440" },
            { label: "4K", value: "3840x2160" }
        ]

        // Native resolutions of the attached displays
        SystemProperties.refreshDisplays()
        for (var displayIndex = 0; ; displayIndex++) {
            var rect = SystemProperties.getNativeResolution(displayIndex)
            if (rect.width === 0) {
                break
            }
            var value = rect.width + "x" + rect.height
            if (!options.some(function(option) { return option.value === value })) {
                options.push({ label: qsTr("Native (%1)").arg(rect.width + "×" + rect.height), value: value })
            }
        }

        // Nothing bigger than the decoder can take
        var maxPixels = SystemProperties.maximumResolution.width * SystemProperties.maximumResolution.height
        if (maxPixels > 0) {
            options = options.filter(function(option) {
                if (option.value === "auto") {
                    return true
                }
                var size = option.value.split("x")
                return parseInt(size[0]) * parseInt(size[1]) <= maxPixels
            })
        }

        // The saved resolution, if it's none of the above
        var saved = StreamingPreferences.width + "x" + StreamingPreferences.height
        if (!StreamingPreferences.autoResolution && !options.some(function(option) { return option.value === saved })) {
            options.push({ label: qsTr("Custom (%1)").arg(StreamingPreferences.width + "×" + StreamingPreferences.height), value: saved })
        }

        options.push({ label: qsTr("Custom…"), value: "custom" })
        return options
    }

    function fpsOptions() {
        var refreshRates = []
        for (var displayIndex = 0; ; displayIndex++) {
            var refreshRate = SystemProperties.getRefreshRate(displayIndex)
            if (refreshRate === 0) {
                break
            }
            refreshRates.push(refreshRate)
        }

        var options = [{ label: qsTr("Automatic"), value: "auto" }]
        var choices = StreamingPreferences.getFpsChoices(refreshRates)
        for (var i = 0; i < choices.length; i++) {
            var choice = choices[i]
            var label = choice.kind === "vrr" ? qsTr("VRR (%1 FPS)").arg(choice.video_fps) :
                        choice.kind === "low-latency-vrr" ? qsTr("Low-latency VRR (%1 FPS)").arg(choice.video_fps) :
                        choice.kind === "custom" ? qsTr("Custom (%1 FPS)").arg(choice.video_fps) :
                        qsTr("%1 FPS").arg(choice.video_fps)
            options.push({ label: label, value: String(choice.video_fps) })
        }

        var saved = String(StreamingPreferences.fps)
        if (!StreamingPreferences.autoFps && !options.some(function(option) { return option.value === saved })) {
            options.push({ label: qsTr("Custom (%1 FPS)").arg(saved), value: saved })
        }

        options.push({ label: qsTr("Custom…"), value: "custom" })
        return options
    }

    function build() {
        return [
            // Picture
            {
                key: "resolution", category: "image", icon: "monitor", type: "choice", sheet: true,
                label: qsTr("Resolution"),
                desc: qsTr("Automatic follows the display of this device when the stream starts."),
                options: resolutionOptions,
                get: function() { return StreamingPreferences.autoResolution ? "auto" : StreamingPreferences.width + "x" + StreamingPreferences.height },
                set: function(value) {
                    if (value === "custom") {
                        customRequested("resolution")
                    }
                    else if (value === "auto") {
                        setResolution(0, 0, true)
                    }
                    else {
                        var size = value.split("x")
                        setResolution(parseInt(size[0]), parseInt(size[1]), false)
                    }
                },
                def: function() { return "1280x720" }
            },
            {
                key: "fps", category: "image", icon: "layers", type: "choice", sheet: true,
                label: qsTr("Frame rate"),
                desc: qsTr("Higher is smoother, but needs more bitrate and a faster PC."),
                options: fpsOptions,
                get: function() { return StreamingPreferences.autoFps ? "auto" : String(StreamingPreferences.fps) },
                set: function(value) {
                    if (value === "custom") {
                        customRequested("fps")
                    }
                    else if (value === "auto") {
                        setFps(0, true)
                    }
                    else {
                        setFps(parseInt(value), false)
                    }
                },
                def: function() { return "60" }
            },
            {
                key: "codec", category: "image", icon: "image", type: "choice",
                label: qsTr("Video codec"),
                desc: qsTr("Automatic picks the best one both PCs support."),
                options: function() {
                    return [
                        { label: qsTr("Automatic"), value: StreamingPreferences.VCC_AUTO },
                        { label: "H.264", value: StreamingPreferences.VCC_FORCE_H264 },
                        { label: "HEVC", value: StreamingPreferences.VCC_FORCE_HEVC },
                        { label: "AV1", value: StreamingPreferences.VCC_FORCE_AV1 }
                    ]
                },
                get: function() { return StreamingPreferences.videoCodecConfig },
                set: function(value) { StreamingPreferences.videoCodecConfig = value },
                def: function() { return StreamingPreferences.VCC_AUTO }
            },
            {
                key: "hdr", category: "image", icon: "sliders", type: "bool",
                label: qsTr("HDR"),
                desc: SystemProperties.supportsHdr ? qsTr("Some games need an HDR display on the host PC too.")
                                                   : qsTr("HDR streaming is not supported on this device."),
                enabled: function() { return SystemProperties.supportsHdr },
                locked: function() { return qsTr("HDR streaming is not supported on this device.") },
                get: function() { return SystemProperties.supportsHdr && StreamingPreferences.enableHdr },
                set: function(value) { StreamingPreferences.enableHdr = value },
                def: function() { return false }
            },
            {
                key: "vsync", category: "image", icon: "check", type: "bool",
                label: qsTr("V-Sync"),
                // Static: the settings list is built once, a binding here would rebuild it
                desc: qsTr("Removes tearing. Without it, latency is a little lower."),
                get: function() { return StreamingPreferences.enableVsync },
                set: function(value) { StreamingPreferences.enableVsync = value },
                def: function() { return true },
                companions: ["framePacing", "autoFramePacing", "vrr"]
            },
            {
                key: "framePacing", category: "image", icon: "clock", type: "bool",
                label: qsTr("Frame pacing"),
                desc: qsTr("Smoother, a little more latency"),
                enabled: function() { return pacingAllowed() },
                locked: pacingLockReason,
                unlock: unlockPacing,
                get: function() { return pacingAllowed() && StreamingPreferences.framePacing },
                set: function(value) { StreamingPreferences.framePacing = value },
                def: function() { return true }
            },
            {
                key: "autoFramePacing", category: "image", icon: "clock", type: "bool",
                label: qsTr("Pacing only when needed"),
                desc: qsTr("Only while frames arrive irregularly"),
                enabled: function() { return pacingAllowed() && StreamingPreferences.framePacing },
                locked: function() { return pacingAllowed() ? qsTr("Needs frame pacing · A turns it on") : pacingLockReason() },
                unlock: function() {
                    unlockPacing()
                    if (pacingAllowed()) {
                        StreamingPreferences.framePacing = true
                    }
                },
                get: function() { return StreamingPreferences.autoFramePacing },
                set: function(value) { StreamingPreferences.autoFramePacing = value },
                def: function() { return true }
            },
            {
                key: "vrr", category: "image", icon: "monitor", type: "bool",
                label: qsTr("VRR"),
                desc: qsTr("Variable refresh rate, needs V-Sync"),
                enabled: function() { return pacingAllowed() },
                locked: pacingLockReason,
                unlock: unlockPacing,
                get: function() { return StreamingPreferences.enableVrr },
                set: function(value) { StreamingPreferences.enableVrr = value },
                def: function() { return false }
            },
            {
                key: "windowMode", category: "image", icon: "monitor", type: "choice",
                label: qsTr("Display mode"),
                desc: qsTr("Borderless works better with Alt+Tab and overlays"),
                available: function() { return SystemProperties.hasDesktopEnvironment },
                // An active VRR session always uses borderless fullscreen
                enabled: function() { return !SystemProperties.rendererAlwaysFullScreen && !(pacingAllowed() && StreamingPreferences.enableVrr) },
                locked: function() {
                    return SystemProperties.rendererAlwaysFullScreen ? qsTr("Always fullscreen on this device")
                                                                     : qsTr("VRR always uses borderless fullscreen")
                },
                options: function() {
                    var recommended = StreamingPreferences.recommendedFullScreenMode
                    function label(text, mode) { return mode === recommended ? qsTr("%1 (recommended)").arg(text) : text }
                    return [
                        { label: label(qsTr("Fullscreen"), StreamingPreferences.WM_FULLSCREEN), value: StreamingPreferences.WM_FULLSCREEN },
                        { label: label(qsTr("Borderless"), StreamingPreferences.WM_FULLSCREEN_DESKTOP), value: StreamingPreferences.WM_FULLSCREEN_DESKTOP },
                        { label: qsTr("Windowed"), value: StreamingPreferences.WM_WINDOWED }
                    ]
                },
                get: function() { return StreamingPreferences.windowMode },
                set: function(value) { StreamingPreferences.windowMode = value },
                def: function() { return StreamingPreferences.recommendedFullScreenMode }
            },
            {
                key: "decoder", category: "image", icon: "image", type: "choice",
                label: qsTr("Video decoder"),
                desc: qsTr("Hardware decoding is recommended"),
                options: function() {
                    return [
                        { label: qsTr("Automatic"), value: StreamingPreferences.VDS_AUTO },
                        { label: qsTr("Software"), value: StreamingPreferences.VDS_FORCE_SOFTWARE },
                        { label: qsTr("Hardware"), value: StreamingPreferences.VDS_FORCE_HARDWARE }
                    ]
                },
                get: function() { return StreamingPreferences.videoDecoderSelection },
                set: function(value) { StreamingPreferences.videoDecoderSelection = value },
                def: function() { return StreamingPreferences.VDS_AUTO }
            },
            {
                key: "yuv444", category: "image", icon: "image", type: "bool",
                label: qsTr("YUV 4:4:4"),
                desc: qsTr("Sharper text, more bitrate. Few GPUs decode it (not AMD ones)."),
                get: function() { return StreamingPreferences.enableYUV444 },
                set: function(value) {
                    StreamingPreferences.enableYUV444 = value
                    updateDefaultBitrate()
                },
                def: function() { return false }
            },

            // Frame generation, left to Lossless Scaling
            {
                key: "losslessScaling", category: "framegen", icon: "layers", type: "bool",
                label: qsTr("Lossless Scaling"),
                desc: qsTr("Turned on for the stream, with its frame generation"),
                available: function() { return Qt.platform.os === "windows" && SystemProperties.isLosslessScalingInstalled() },
                get: function() { return StreamingPreferences.losslessScaling },
                set: function(value) {
                    StreamingPreferences.losslessScaling = value
                    // Ready before the stream, in the tray
                    if (value) {
                        SystemProperties.startLosslessScaling()
                    }
                },
                def: function() { return false }
            },
            {
                key: "losslessScalingStore", category: "framegen", icon: "layers", type: "action",
                label: qsTr("Lossless Scaling"),
                desc: qsTr("Frame generation for any window, sold on Steam"),
                actionLabel: qsTr("Buy on Steam"),
                available: function() { return Qt.platform.os === "windows" && !SystemProperties.isLosslessScalingInstalled() },
                run: function() { return SystemProperties.openLosslessScalingStore() }
            },

            // Network
            {
                key: "bitrate", category: "network", icon: "gauge", type: "slider",
                label: qsTr("Video bitrate"),
                desc: qsTr("Higher: sharper picture, more demanding network."),
                from: 500, step: 500,
                to: function() { return StreamingPreferences.getMaxBitrate(StreamingPreferences.unlockBitrate) },
                format: function(value) { return qsTr("%1 Mb/s").arg(Math.round(value / 100) / 10) },
                get: function() { return StreamingPreferences.bitrateKbps },
                set: function(value) {
                    StreamingPreferences.bitrateKbps = value
                    StreamingPreferences.autoAdjustBitrate = value === defaultBitrate()
                },
                def: function() { return defaultBitrate() },
                companions: ["learnBitrate", "useWifiBitrate"]
            },
            {
                key: "useWifiBitrate", category: "network", icon: "wifi", type: "bool",
                label: qsTr("Separate Wi-Fi bitrate"),
                desc: qsTr("The main bitrate is then used on Ethernet only"),
                get: function() { return StreamingPreferences.useWifiBitrate },
                set: function(value) { StreamingPreferences.useWifiBitrate = value },
                def: function() { return false }
            },
            {
                key: "wifiBitrate", category: "network", icon: "wifi", type: "slider",
                label: qsTr("Wi-Fi bitrate"),
                desc: qsTr("For Wi-Fi, VPN and unknown connections"),
                enabled: function() { return StreamingPreferences.useWifiBitrate },
                locked: function() { return qsTr("Needs a separate Wi-Fi bitrate · A turns it on") },
                unlock: function() { StreamingPreferences.useWifiBitrate = true },
                from: 500, step: 500,
                to: function() { return StreamingPreferences.getMaxBitrate(StreamingPreferences.unlockBitrate) },
                format: function(value) { return qsTr("%1 Mb/s").arg(Math.round(value / 100) / 10) },
                get: function() { return StreamingPreferences.wifiBitrateKbps },
                set: function(value) { StreamingPreferences.wifiBitrateKbps = value },
                def: function() { return Math.min(StreamingPreferences.bitrateKbps, 20000) }
            },
            {
                key: "learnBitrate", category: "network", icon: "gauge", type: "bool",
                label: qsTr("Learn the bitrate of each PC"),
                desc: qsTr("Lowers it after streams that lost frames"),
                get: function() { return StreamingPreferences.learnBitrate },
                set: function(value) {
                    StreamingPreferences.learnBitrate = value
                    // Start from scratch if it's turned back on later
                    if (!value) {
                        StreamingPreferences.resetLearnedBitrates()
                    }
                },
                def: function() { return true }
            },
            {
                key: "autoReconnect", category: "network", icon: "refresh", type: "bool",
                label: qsTr("Reconnect automatically"),
                desc: qsTr("Up to 3 tries when the network drops"),
                get: function() { return StreamingPreferences.autoReconnect },
                set: function(value) { StreamingPreferences.autoReconnect = value },
                def: function() { return true }
            },
            {
                key: "unlockBitrate", category: "network", icon: "gauge", type: "bool",
                label: qsTr("Unlock bitrate limit"),
                desc: qsTr("Very high bitrates, for Ethernet only"),
                get: function() { return StreamingPreferences.unlockBitrate },
                set: function(value) {
                    StreamingPreferences.unlockBitrate = value
                    var max = StreamingPreferences.getMaxBitrate(value)
                    StreamingPreferences.bitrateKbps = Math.min(StreamingPreferences.bitrateKbps, max)
                    StreamingPreferences.wifiBitrateKbps = Math.min(StreamingPreferences.wifiBitrateKbps, max)
                },
                def: function() { return false }
            },
            {
                key: "mdns", category: "network", icon: "search", type: "bool",
                label: qsTr("Find PCs automatically"),
                desc: qsTr("Looks for PCs on the local network"),
                get: function() { return StreamingPreferences.enableMdns },
                set: function(value) {
                    StreamingPreferences.enableMdns = value
                    // Restart polling so the change takes effect
                    if (window.pollingActive) {
                        ComputerManager.stopPollingAsync()
                        ComputerManager.startPolling()
                    }
                },
                def: function() { return true }
            },
            {
                key: "detectNetworkBlocking", category: "network", icon: "network", type: "bool",
                label: qsTr("Detect blocked connections"),
                desc: qsTr("Explains failures caused by the network"),
                get: function() { return StreamingPreferences.detectNetworkBlocking },
                set: function(value) { StreamingPreferences.detectNetworkBlocking = value },
                def: function() { return true }
            },
            {
                key: "connectionWarnings", category: "network", icon: "info", type: "bool",
                label: qsTr("Connection warnings"),
                desc: qsTr("Warns while streaming when the network struggles"),
                get: function() { return StreamingPreferences.connectionWarnings },
                set: function(value) { StreamingPreferences.connectionWarnings = value },
                def: function() { return true }
            },

            // Audio
            {
                key: "audio", category: "audio", icon: "volume", type: "choice",
                label: qsTr("Audio"),
                desc: qsTr("Use surround only with a matching audio setup."),
                options: function() {
                    return [
                        { label: qsTr("Stereo"), value: StreamingPreferences.AC_STEREO },
                        { label: qsTr("5.1"), value: StreamingPreferences.AC_51_SURROUND },
                        { label: qsTr("7.1"), value: StreamingPreferences.AC_71_SURROUND }
                    ]
                },
                get: function() { return StreamingPreferences.audioConfig },
                set: function(value) { StreamingPreferences.audioConfig = value },
                def: function() { return StreamingPreferences.AC_STEREO },
                companions: ["muteHost", "muteOnFocusLoss"]
            },
            {
                key: "muteHost", category: "audio", icon: "volume", type: "bool",
                label: qsTr("Mute the host PC"),
                desc: qsTr("Its speakers stay silent while streaming"),
                get: function() { return !StreamingPreferences.playAudioOnHost },
                set: function(value) { StreamingPreferences.playAudioOnHost = !value },
                def: function() { return true }
            },
            {
                key: "muteOnFocusLoss", category: "audio", icon: "volume", type: "bool",
                label: qsTr("Mute in the background"),
                desc: qsTr("When %1 isn't the active window").arg(appName),
                available: function() { return SystemProperties.hasDesktopEnvironment },
                get: function() { return StreamingPreferences.muteOnFocusLoss },
                set: function(value) { StreamingPreferences.muteOnFocusLoss = value },
                def: function() { return false }
            },

            // Gamepads
            {
                key: "gamepadLayout", category: "gamepad", icon: "gamepad", type: "choice",
                label: qsTr("Gamepad layout"),
                desc: qsTr("Nintendo swaps A/B and X/Y."),
                options: function() {
                    return [
                        { label: "Xbox", value: false },
                        { label: "Nintendo", value: true }
                    ]
                },
                get: function() { return StreamingPreferences.swapFaceButtons },
                set: function(value) { StreamingPreferences.swapFaceButtons = value },
                def: function() { return false },
                companions: ["gamepadMouse", "singleController"]
            },
            {
                key: "gamepadMouse", category: "gamepad", icon: "mouse", type: "bool",
                label: qsTr("Mouse with the gamepad"),
                desc: qsTr("Hold Start to switch"),
                get: function() { return StreamingPreferences.gamepadMouse },
                set: function(value) { StreamingPreferences.gamepadMouse = value },
                def: function() { return true }
            },
            {
                key: "singleController", category: "gamepad", icon: "gamepad", type: "bool",
                label: qsTr("Keep gamepad 1 connected"),
                desc: qsTr("For games that miss gamepads plugged in later"),
                get: function() { return !StreamingPreferences.multiController },
                set: function(value) { StreamingPreferences.multiController = !value },
                def: function() { return false }
            },
            {
                key: "backgroundGamepad", category: "gamepad", icon: "gamepad", type: "bool",
                label: qsTr("Gamepad in the background"),
                desc: qsTr("Works even when %1 isn't focused").arg(appName),
                available: function() { return SystemProperties.hasDesktopEnvironment },
                get: function() { return StreamingPreferences.backgroundGamepad },
                set: function(value) { StreamingPreferences.backgroundGamepad = value },
                def: function() { return false }
            },

            // Mouse and keyboard
            {
                key: "absoluteMouse", category: "input", icon: "mouse", type: "bool",
                label: qsTr("Remote desktop mouse"),
                desc: qsTr("For the desktop, not for games (Ctrl+Alt+Shift+M)"),
                get: function() { return StreamingPreferences.absoluteMouseMode },
                set: function(value) { StreamingPreferences.absoluteMouseMode = value },
                def: function() { return false }
            },
            {
                key: "captureSysKeys", category: "input", icon: "keyboard", type: "choice",
                label: qsTr("System shortcuts"),
                desc: qsTr("Sends Alt+Tab and the like to the host"),
                enabled: function() { return SystemProperties.hasDesktopEnvironment },
                locked: function() { return qsTr("Not available on this device") },
                options: function() {
                    return [
                        { label: qsTr("Off"), value: StreamingPreferences.CSK_OFF },
                        { label: qsTr("Fullscreen"), value: StreamingPreferences.CSK_FULLSCREEN },
                        { label: qsTr("Always"), value: StreamingPreferences.CSK_ALWAYS }
                    ]
                },
                get: function() { return StreamingPreferences.captureSysKeysMode },
                set: function(value) { StreamingPreferences.captureSysKeysMode = value },
                def: function() { return StreamingPreferences.CSK_OFF }
            },
            {
                key: "touchTrackpad", category: "input", icon: "mouse", type: "bool",
                label: qsTr("Touchscreen as a trackpad"),
                desc: qsTr("Else a touch moves the pointer there"),
                get: function() { return !StreamingPreferences.absoluteTouchMode },
                set: function(value) { StreamingPreferences.absoluteTouchMode = !value },
                def: function() { return false }
            },
            {
                key: "swapMouseButtons", category: "input", icon: "mouse", type: "bool",
                label: qsTr("Swap mouse buttons"),
                desc: "",
                get: function() { return StreamingPreferences.swapMouseButtons },
                set: function(value) { StreamingPreferences.swapMouseButtons = value },
                def: function() { return false }
            },
            {
                key: "reverseScroll", category: "input", icon: "mouse", type: "bool",
                label: qsTr("Reverse scrolling"),
                desc: "",
                get: function() { return StreamingPreferences.reverseScrollDirection },
                set: function(value) { StreamingPreferences.reverseScrollDirection = value },
                def: function() { return false }
            },

            // System
            {
                key: "language", category: "system", icon: "globe", type: "choice", sheet: true,
                label: qsTr("Language"),
                desc: "",
                options: function() {
                    return [
                        { label: qsTr("Automatic"), value: StreamingPreferences.LANG_AUTO },
                        { label: "Deutsch", value: StreamingPreferences.LANG_DE },
                        { label: "English", value: StreamingPreferences.LANG_EN },
                        { label: "Français", value: StreamingPreferences.LANG_FR },
                        { label: "简体中文", value: StreamingPreferences.LANG_ZH_CN },
                        { label: "Norwegian Bokmål", value: StreamingPreferences.LANG_NB_NO },
                        { label: "русский", value: StreamingPreferences.LANG_RU },
                        { label: "Español", value: StreamingPreferences.LANG_ES },
                        { label: "日本語", value: StreamingPreferences.LANG_JA },
                        { label: "Tiếng Việt", value: StreamingPreferences.LANG_VI },
                        { label: "ภาษาไทย", value: StreamingPreferences.LANG_TH },
                        { label: "한국어", value: StreamingPreferences.LANG_KO },
                        { label: "Magyar", value: StreamingPreferences.LANG_HU },
                        { label: "Nederlands", value: StreamingPreferences.LANG_NL },
                        { label: "Svenska", value: StreamingPreferences.LANG_SV },
                        { label: "Türkçe", value: StreamingPreferences.LANG_TR },
                        { label: "繁體中文", value: StreamingPreferences.LANG_ZH_TW },
                        { label: "Português", value: StreamingPreferences.LANG_PT },
                        { label: "Português do Brasil", value: StreamingPreferences.LANG_PT_BR },
                        { label: "Ελληνικά", value: StreamingPreferences.LANG_EL },
                        { label: "Italiano", value: StreamingPreferences.LANG_IT },
                        { label: "Język polski", value: StreamingPreferences.LANG_PL },
                        { label: "Čeština", value: StreamingPreferences.LANG_CS },
                        { label: "Български", value: StreamingPreferences.LANG_BG },
                        { label: "தமிழ்", value: StreamingPreferences.LANG_TA }
                    ]
                },
                get: function() { return StreamingPreferences.language },
                set: function(value) {
                    // Retranslating is expensive, so only do it if the language actually changed
                    if (StreamingPreferences.language !== value) {
                        StreamingPreferences.language = value
                        if (StreamingPreferences.retranslate()) {
                            // The library doesn't survive a retranslation, pop it on the way back
                            window.clearOnBack = true
                        }
                    }
                },
                def: function() { return StreamingPreferences.LANG_AUTO }
            },
            {
                key: "uiSounds", category: "system", icon: "volume", type: "bool",
                label: qsTr("Interface sounds"),
                desc: qsTr("Muted while streaming"),
                get: function() { return StreamingPreferences.uiSounds },
                set: function(value) { StreamingPreferences.uiSounds = value },
                def: function() { return true },
                companions: ["uiSoundVolume"]
            },
            {
                key: "uiSoundVolume", category: "system", icon: "volume", type: "slider",
                label: qsTr("Interface sound volume"),
                desc: "",
                enabled: function() { return StreamingPreferences.uiSounds },
                locked: function() { return qsTr("Needs interface sounds · A turns them on") },
                unlock: function() { StreamingPreferences.uiSounds = true },
                from: 0, step: 10,
                to: function() { return 100 },
                format: function(value) { return value + " %" },
                get: function() { return StreamingPreferences.uiSoundVolume },
                set: function(value) { StreamingPreferences.uiSoundVolume = value },
                def: function() { return 60 }
            },
            {
                key: "startupIntro", category: "system", icon: "play", type: "bool",
                label: qsTr("Startup intro"),
                desc: qsTr("Plays when %1 opens · any button skips it").arg(appName),
                get: function() { return StreamingPreferences.startupIntro },
                set: function(value) { StreamingPreferences.startupIntro = value },
                def: function() { return true }
            },
            {
                key: "uiDisplayMode", category: "system", icon: "monitor", type: "choice",
                label: qsTr("%1 window").arg(appName),
                desc: qsTr("How %1 opens").arg(appName),
                available: function() { return SystemProperties.hasDesktopEnvironment },
                options: function() {
                    return [
                        { label: qsTr("Windowed"), value: StreamingPreferences.UI_WINDOWED },
                        { label: qsTr("Maximized"), value: StreamingPreferences.UI_MAXIMIZED },
                        { label: qsTr("Fullscreen"), value: StreamingPreferences.UI_FULLSCREEN }
                    ]
                },
                get: function() { return StreamingPreferences.uiDisplayMode },
                set: function(value) { StreamingPreferences.uiDisplayMode = value },
                def: function() { return StreamingPreferences.UI_WINDOWED }
            },
            {
                key: "batterySaver", category: "system", icon: "power", type: "bool",
                label: qsTr("Battery saver"),
                desc: qsTr("60 FPS and a lower bitrate when unplugged"),
                get: function() { return StreamingPreferences.batterySaver },
                set: function(value) { StreamingPreferences.batterySaver = value },
                def: function() { return true }
            },
            {
                key: "keepAwake", category: "system", icon: "clock", type: "bool",
                label: qsTr("Keep the display awake"),
                desc: qsTr("No screensaver while streaming"),
                get: function() { return StreamingPreferences.keepAwake },
                set: function(value) { StreamingPreferences.keepAwake = value },
                def: function() { return true }
            },
            {
                key: "gameOptimizations", category: "system", icon: "gamepad", type: "bool",
                label: qsTr("Optimize game settings"),
                desc: qsTr("Lets the host adjust games for streaming"),
                get: function() { return StreamingPreferences.gameOptimizations },
                set: function(value) { StreamingPreferences.gameOptimizations = value },
                def: function() { return true }
            },
            {
                key: "quitAppAfter", category: "system", icon: "power", type: "bool",
                label: qsTr("Quit the game after streaming"),
                desc: qsTr("Unsaved progress is lost"),
                get: function() { return StreamingPreferences.quitAppAfter },
                set: function(value) { StreamingPreferences.quitAppAfter = value },
                def: function() { return false }
            },
            {
                key: "performanceOverlay", category: "system", icon: "gauge", type: "bool",
                label: qsTr("Performance stats"),
                desc: qsTr("Shown while streaming (Ctrl+Alt+Shift+S)"),
                get: function() { return StreamingPreferences.showPerformanceOverlay },
                set: function(value) { StreamingPreferences.showPerformanceOverlay = value },
                def: function() { return false }
            },
            {
                key: "logStreamStats", category: "system", icon: "code", type: "bool",
                label: qsTr("Save stream statistics"),
                desc: qsTr("One CSV line per second, next to the logs"),
                get: function() { return StreamingPreferences.logStreamStats },
                set: function(value) { StreamingPreferences.logStreamStats = value },
                def: function() { return false }
            },
            {
                key: "configurationWarnings", category: "system", icon: "info", type: "bool",
                label: qsTr("Configuration warnings"),
                desc: qsTr("Like a missing hardware decoder"),
                get: function() { return StreamingPreferences.configurationWarnings },
                set: function(value) { StreamingPreferences.configurationWarnings = value },
                def: function() { return true }
            },
            {
                key: "richPresence", category: "system", icon: "discord", type: "bool",
                label: qsTr("Discord status"),
                desc: qsTr("Shows the game you're streaming"),
                available: function() { return SystemProperties.hasDiscordIntegration },
                get: function() { return StreamingPreferences.richPresence },
                set: function(value) { StreamingPreferences.richPresence = value },
                def: function() { return true }
            }
        ]
    }

    // Values a custom profile saves and restores
    readonly property var profileKeys: [
        "autoResolution", "width", "height", "autoFps", "fps",
        "autoAdjustBitrate", "bitrateKbps", "videoCodecConfig", "enableHdr", "enableVsync", "framePacing",
        "enableVrr", "enableYUV444", "audioConfig"
    ]

    // Applied through setResolution(), setFps() and the bitrate rules
    readonly property var profileSizeKeys: ["autoResolution", "width", "height", "autoFps", "fps", "autoAdjustBitrate", "bitrateKbps"]

    // Colors a custom profile can have
    readonly property var profileColors: ["#FF6A3D", "#FFC857", "#5FD39A", "#5CC8FF", "#9B8CFF", "#FF7AB6"]

    // Bumped when the custom profiles change, to refresh what depends on them
    property int profilesRevision: 0

    function customProfiles() {
        try {
            var list = JSON.parse(StreamingPreferences.customProfiles)
            return Array.isArray(list) ? list : []
        }
        catch (e) {
            return []
        }
    }

    function saveCustomProfiles(list) {
        StreamingPreferences.customProfiles = JSON.stringify(list)
        StreamingPreferences.save()
        profilesRevision++
    }

    // A short description of the settings, like the built-in profiles have
    function describe(values) {
        var parts = []
        parts.push(values.autoResolution ? qsTr("Auto") : values.height + "p")
        parts.push(values.autoFps ? qsTr("auto FPS") : qsTr("%1 FPS").arg(values.fps))
        parts.push(values.autoAdjustBitrate ? qsTr("auto bitrate") : qsTr("%1 Mb/s").arg(Math.round(values.bitrateKbps / 100) / 10))
        return parts.join(" · ")
    }

    function currentValues() {
        var values = {}
        for (var i = 0; i < profileKeys.length; i++) {
            values[profileKeys[i]] = StreamingPreferences[profileKeys[i]]
        }
        return values
    }

    function makeCustomProfile(entry, index) {
        return {
            key: "custom" + index, custom: true, index: index, icon: "star",
            label: entry.name, color: entry.color,
            summary: describe(entry.values),
            apply: function() {
                var values = entry.values
                for (var key in values) {
                    if (profileKeys.indexOf(key) >= 0 && profileSizeKeys.indexOf(key) < 0) {
                        StreamingPreferences[key] = values[key]
                    }
                }
                // Automatic values follow the display this device is on now
                setResolution(values.width, values.height, values.autoResolution)
                setFps(values.fps, values.autoFps)
                StreamingPreferences.autoAdjustBitrate = values.autoAdjustBitrate
                StreamingPreferences.bitrateKbps = values.autoAdjustBitrate ? defaultBitrate() : values.bitrateKbps
            },
            matches: function() {
                var values = entry.values
                for (var key in values) {
                    if (profileKeys.indexOf(key) < 0 ||
                            ((key === "width" || key === "height") && values.autoResolution) ||
                            (key === "fps" && values.autoFps) ||
                            (key === "bitrateKbps" && values.autoAdjustBitrate)) {
                        continue
                    }
                    if (String(StreamingPreferences[key]) !== String(values[key])) {
                        return false
                    }
                }
                return true
            }
        }
    }

    // The user's profiles, then the built-in ones
    readonly property var allProfiles: {
        profilesRevision
        var list = customProfiles().map(makeCustomProfile)
        return list.concat(profiles)
    }

    function addCustomProfile(name, color) {
        var list = customProfiles()
        list.push({ name: name, color: color, values: currentValues() })
        saveCustomProfiles(list)
    }

    function updateCustomProfile(index) {
        var list = customProfiles()
        if (index >= 0 && index < list.length) {
            list[index].values = currentValues()
            saveCustomProfiles(list)
        }
    }

    function removeCustomProfile(index) {
        var list = customProfiles()
        if (index >= 0 && index < list.length) {
            list.splice(index, 1)
            saveCustomProfiles(list)
        }
    }

    // A name that isn't taken yet
    function newProfileName() {
        var names = customProfiles().map(function(entry) { return entry.name })
        for (var i = 1; ; i++) {
            var name = qsTr("My profile %1").arg(i)
            if (names.indexOf(name) < 0) {
                return name
            }
        }
    }

    // Built-in streaming profiles
    readonly property var profiles: [
        { key: "performance", icon: "layers", label: qsTr("Performance"), color: Theme.kaneMode ? Theme.accent : "#FF6A3D",
          summary: qsTr("Auto · auto FPS"),
          apply: function() {
              setResolution(0, 0, true)
              setFps(0, true)
              StreamingPreferences.autoAdjustBitrate = true
              StreamingPreferences.bitrateKbps = defaultBitrate()
          },
          matches: function() {
              return StreamingPreferences.autoResolution && StreamingPreferences.autoFps
          } },
        { key: "quality", icon: "image", label: qsTr("Quality"), color: "#9B8CFF",
          summary: qsTr("1440p · 60 FPS · high bitrate"),
          apply: function() {
              setResolution(2560, 1440, false)
              setFps(60, false)
              StreamingPreferences.autoAdjustBitrate = false
              StreamingPreferences.bitrateKbps = Math.min(Math.round(defaultBitrate() * 1.5 / 500) * 500,
                                                          StreamingPreferences.getMaxBitrate(StreamingPreferences.unlockBitrate))
          },
          matches: function() {
              return !StreamingPreferences.autoResolution && StreamingPreferences.height === 1440 &&
                     !StreamingPreferences.autoFps && StreamingPreferences.fps === 60
          } },
        { key: "battery", icon: "power", label: qsTr("Battery"), color: "#5FD39A",
          summary: qsTr("720p · 60 FPS · light"),
          apply: function() {
              setResolution(1280, 720, false)
              setFps(60, false)
              StreamingPreferences.autoAdjustBitrate = true
              StreamingPreferences.bitrateKbps = defaultBitrate()
          },
          matches: function() {
              return !StreamingPreferences.autoResolution && StreamingPreferences.height === 720 &&
                     !StreamingPreferences.autoFps && StreamingPreferences.fps === 60
          } },
        { key: "weaknetwork", icon: "wifi", label: qsTr("Weak network"), color: "#5CC8FF",
          summary: qsTr("720p · 30 FPS · low bitrate"),
          apply: function() {
              setResolution(1280, 720, false)
              setFps(30, false)
              StreamingPreferences.autoAdjustBitrate = false
              StreamingPreferences.bitrateKbps = Math.min(defaultBitrate(), 6000)
          },
          matches: function() {
              return !StreamingPreferences.autoResolution && StreamingPreferences.height === 720 &&
                     !StreamingPreferences.autoFps && StreamingPreferences.fps === 30
          } }
    ]
}
