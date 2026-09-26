# KanePlay

**KanePlay** (as in *can play*) is a game streaming client for Windows, made for
handheld PCs like the ROG Ally and for playing on the couch with a gamepad. It
streams games from a PC running [Sunshine](https://github.com/LizardByte/Sunshine).

KanePlay is a fork of [Moonlight PC](https://github.com/moonlight-stream/moonlight-qt).
All the streaming technology comes from the Moonlight project and its contributors.
KanePlay is **not affiliated with or endorsed by** the Moonlight project; please don't
report KanePlay issues to them.

## What's different from Moonlight

- **A new interface built for gamepads**: Home, Library and Settings tabs (LB/RB),
  cover art library with favorites, connection steps, a session summary with the
  latency of the session, animations and interface sounds.
- **Streaming profiles**: Performance, Quality, Battery and Weak network, plus your
  own profiles with a name and a color.
- **Frame generation** is left to the tools that do it well: the settings open
  AMD Software, to turn AMD Fluid Motion Frames on for KanePlay (AMD graphics),
  or Lossless Scaling.
- **In-game menu** (Start + Select): stats, gamepad mouse, diagnostic capture
  and disconnect, without leaving the game.
- **Automatic reconnection** when the network drops, a **battery saver**, and a
  bitrate that learns from each PC.
- **In-app updates** from the GitHub releases of this repository.
- On first launch, KanePlay imports the settings and paired PCs of Moonlight, so
  there is nothing to pair again. Both apps can stay installed side by side.

## Download

Get the installer from the [releases](https://github.com/Kaynegiordano/KanePlay/releases).
KanePlay is for Windows 10 and 11, x64.

The installer isn't signed yet: if Windows SmartScreen shows up, choose
*More info*, then *Run anyway*.

## Gamepad shortcuts

| Where | Buttons | Does |
|---|---|---|
| Menus | LB / RB | Switch tabs |
| Menus | A / B / X / Y | Confirm / Back / Options / Settings |
| Advanced settings | LT / RT | Switch categories |
| In game | Start + Select (press and release) | In-game menu |
| In game | LB + RB + Select + Y | Disconnect (the host PC is left as it is) |
| In game | LB + RB + Select + X | Performance stats |

## Building

Requirements:

- Qt 6.11 SDK for MSVC 2022 x64
- Visual Studio 2026 (Community edition is fine)
- [7-Zip](https://www.7-zip.org/), on the `PATH`

Then, from a Qt command prompt at the root of the repository:

```
git submodule update --init --recursive
powershell -File setup-deps.ps1
scripts\build-arch.bat release
scripts\generate-bundle.bat release x64
```

The installer is written to `build\installer-release`. `scripts\publish-release.ps1`
publishes it as a GitHub release, along with the `update.json` manifest that the
app checks for updates.

## Credits

- [Moonlight](https://moonlight-stream.org) and
  [moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c) by
  Cameron Gutman and the Moonlight contributors (GPLv3)
- [Sunshine](https://github.com/LizardByte/Sunshine) by LizardByte, the host this client is made for
- [FFmpeg](https://ffmpeg.org), [SDL](https://libsdl.org), [libplacebo](https://code.videolan.org/videolan/libplacebo),
  [Qt](https://www.qt.io) and the other libraries listed in the app (Settings › About)
- [AMD AMF](https://github.com/GPUOpen-LibrariesAndSDKs/AMF) headers (MIT)
- The [Unbounded](https://github.com/googlefonts/unbounded) and
  [Manrope](https://github.com/sharanda/manrope) fonts (SIL Open Font License)

## License

KanePlay is licensed under the [GNU General Public License v3.0](LICENSE), like Moonlight.
