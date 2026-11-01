# Notch Workspace

A native macOS notch workspace inspired by the expanding interactions in the supplied DynamicLake video, built as an independent GPL-3.0 derivative of Boring Notch.

## Run

Open **Notch Workspace.app** beside this source folder. Hover over the notch, or press **Control–Option–Space**. The menu bar icon provides another way in. Move away to collapse it, use the pin to keep it open, and press Escape to close it. The panel prefers a display with a physical notch and falls back to the main display.

## Included

- **Home:** live clock, adjustable Pomodoro sessions, current music, and links to the other tools. **Reset** and **Cancel** sit directly below an active timer. Reset restores the current session's full duration and pauses it; Cancel ends the cycle. **Times** opens settings inside the same anchored panel: focus 1–180 minutes, short break 1–60, long break 1–120, and 2–12 rounds before a long break. Pause/resume and optional automatic session progression are included. Configuration survives relaunch; an active session does not. Changes affect the next session. The timer reconciles its deadline after the Mac wakes.
- **Music:** system Now Playing metadata and artwork, previous/next/play/pause, track seeking, and a link to the current player. Uses Boring Notch's bundled MediaRemoteAdapter; compatibility depends on the current macOS version and player. Nothing is played automatically.
- **Files:** drop files onto the compact or expanded notch; add files with a picker; drag them back into other apps, share, open, reveal in Finder, or remove from the shelf. References survive relaunches using file bookmarks. The shelf never moves or deletes the original files.
- **Clipboard:** explicitly enable it in the Clipboard tab or Settings. Keeps up to 40 text copies in memory, with search, click to copy, removal, pause, and clear. History is cleared on quit, session deactivation, and screen lock. Standard concealed, transient, and generated items are excluded, as are copies made with known password managers in front. This is not a guarantee that every sensitive text copy is recognizable; pause capture whenever needed. History is not written to disk. Clipboard images and file copies are not collected.
- **Actions:** Downloads, Screenshot, System Settings, a focus timer, plus up to 12 custom application, http/https website, or named Apple Shortcuts actions. Right-click a custom action to remove it. Shortcuts are executed with an argument array, never as shell command text.
- **Settings:** clipboard capture, clear history, reduced animation, license, and credits.

## Build without Xcode

On a Mac with Swift and Apple's Command Line Tools:

```sh
bash Workspace/Scripts/build.sh
```

The default outputs are `../Notch Workspace.app` and `../Notch Workspace.zip`. An optional first argument selects a different app output path. For installation, unzip the archive and move the app into Applications. The build signs and verifies the bundle in a temporary local directory before packaging, avoiding Finder metadata added automatically by cloud-backed Documents folders. The script uses the installed macOS 26 SDK when the standalone tools also contain the macOS 27 SDK, because the latter requires a SwiftUI macro plugin that is only included with full Xcode. The upstream canvas-only `#Preview` is stripped from a build copy of NotchShape; the upstream source stays intact.

The app is built for the current Mac architecture, macOS 14 or later. The delivered binary was compiled and checked on Apple silicon with macOS 26.6.2. Other OS versions are not verified.

The build preserves the upstream MediaRemoteAdapter framework and its signature, then locally signs the application. This is a local development build, without Apple notarization, automatic updates, or a launch-at-login entry.

## Checks

```sh
"../Notch Workspace.app/Contents/MacOS/NotchWorkspace" --self-test
```

The 36 checks use temporary files, a private test pasteboard, isolated preferences, and synthetic media data. They cover history limits and exclusions, file preservation and persistence, URL validation, panel geometry on additional displays, music updates, configurable Pomodoro durations, pause/resume, focus/break/long-break progression, session reset versus cycle cancellation, and configuration persistence. They do not touch the user's clipboard or play media.

## Performance approach

The application is native AppKit/SwiftUI, with no WebView, Electron, network service, account, analytics, or large UI dependencies. The main panel uses hover events instead of continuously sampling the pointer. Clipboard polling runs only while explicitly enabled. Pomodoro schedules one sleeping task for the deadline; its visible countdown updates only when Home is displayed. Music metadata is streamed by the bundled helper, with a 150 ms debounce; no artwork polling or network image fetching is used. The small waveform animates only while music is playing. Media progress updates once per second only while its player is visible. The original Boring Notch's optional camera/calendar/XPC/updater/animation packages are not linked into this target.

Local resource check on Apple silicon, macOS 26.6.2: after startup and interaction had settled, the collapsed app with music paused, clipboard disabled, and no Pomodoro used **0.00% combined CPU over 20.02 seconds** and **50.2 MiB combined resident memory**, including the music helper. CPU was computed from the two processes' cumulative CPU-time change over the sample, normalized to one core; memory is the sum of their resident sets. Opening views, startup, playing animations, and active integrations have higher resource use. This is one local check, not a cross-device benchmark.

For a UI preview with synthetic music and clipboard entries, isolated shelf storage, and no live music or clipboard monitoring:

```sh
"../Notch Workspace.app/Contents/MacOS/NotchWorkspace" --preview
```

## Source layout

The custom target lives in `Workspace/Sources`, with checks in `Workspace/Tests`. The upstream Boring Notch Xcode app is retained in `boringNotch` and is not changed into a different product. The new target directly compiles its existing NotchShape and adapts its music integration. See `Workspace/NOTICE.md` for the upstream commit, licensing, and credits.

This first version does not include hidden menu bar icon management, notification interception, phone call controls, Bluetooth/AirPods activities, weather, brightness HUD replacement, or arbitrary third-party plugins. Those are separate integrations rather than placeholder buttons. The supplied video is used as a design reference, not included in the app.
