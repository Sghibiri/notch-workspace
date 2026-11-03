# Notch Workspace

A native macOS notch workspace inspired by the expanding interactions in the supplied DynamicLake video, built as an independent GPL-3.0 derivative of Boring Notch.

## Run

Open **Notch Workspace.app** beside this source folder. Hover over the notch, or press **Control–Option–Space**. The menu bar icon provides another way in. Move away to collapse it, use the pin to keep it open, and press Escape to close it. The panel prefers a display with a physical notch and falls back to the main display.

## Included

- **Home:** live clock, adjustable Pomodoro sessions, current music, and links to the other tools. **Reset** and **Cancel** sit directly below an active timer. Reset restores the current session's full duration and pauses it; Cancel ends the cycle. **Times** opens settings inside the same anchored panel: focus 1–180 minutes, short break 1–60, long break 1–120, and 2–12 rounds before a long break. Pause/resume and optional automatic session progression are included. Configuration and the current session survive relaunch. Running sessions retain their absolute deadline, and paused sessions retain their remaining time. A session that ended while the app was closed advances once to the next phase, paused, even when automatic progression is enabled; unattended time does not count as extra focus rounds. Cancel removes the saved session. The compact notch shows the countdown and its paused/running state, with no repeating countdown updates while paused. Changes affect the next session. The timer reconciles its deadline after the Mac wakes.
- **Weather:** Estoril, Portugal by default, with a badge on Home and a dedicated Weather tab. **Open full weather** opens a larger resizable window. The toolbar supports full screen, Celsius/Fahrenheit, city changes, refresh, and an effects switch. Escape leaves full screen before closing the regular window. Forecasts include hourly temperatures and rain probability, seven daily forecasts, high/low temperatures, feels-like temperature, humidity, wind, sunrise, and sunset.
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

The app is built for the current Mac architecture, macOS 14 or later. The original version was checked on macOS 26.6.2. Version 0.3 adds local checks on macOS 27.2 and retains macOS 26 build and test coverage in GitHub Actions. The music adapter passed its own compatibility probe on macOS 27.2; weather passed a live integration check. Other OS versions are not manually verified.

The build preserves the upstream MediaRemoteAdapter framework and its signature, then locally signs the application. This is a local development build, without Apple notarization, automatic updates, or a launch-at-login entry.

## Checks

```sh
"../Notch Workspace.app/Contents/MacOS/NotchWorkspace" --self-test
```

The 69 checks use temporary files, a private test pasteboard, isolated preferences, and synthetic media data. They cover history limits and exclusions, file preservation and persistence, URL validation, panel geometry on additional displays, music updates, configurable Pomodoro durations, pause/resume, focus/break/long-break progression, session reset versus cycle cancellation, and configuration persistence. They do not touch the user's clipboard or play media.

## Performance approach

The application is native AppKit/SwiftUI, with no WebView, Electron, persistent server, account, analytics, or large UI dependencies. The main panel uses hover events instead of continuously sampling the pointer. Clipboard polling runs only while explicitly enabled. Pomodoro schedules one sleeping task for the deadline; a running countdown updates once per second while Home or the compact timer is visible. Music metadata is streamed by the bundled helper, with a 150 ms debounce; no artwork polling or network image fetching is used. The small waveform animates only while music is playing. Media progress updates once per second only while its player is visible. The original Boring Notch's optional camera/calendar/XPC/updater/animation packages are not linked into this target.

Local resource check for v0.1 on Apple silicon, macOS 26.6.2: after startup and interaction had settled, the collapsed app with music paused, clipboard disabled, and no Pomodoro used **0.00% combined CPU over 20.02 seconds** and **50.2 MiB combined resident memory**, including the music helper. CPU was computed from the two processes' cumulative CPU-time change over the sample, normalized to one core; memory is the sum of their resident sets. Opening views, startup, playing animations, and active integrations have higher resource use. This is one local check, not a cross-device benchmark.

For a UI preview with synthetic music and clipboard entries, isolated shelf storage, and no live music or clipboard monitoring:

```sh
"../Notch Workspace.app/Contents/MacOS/NotchWorkspace" --preview
```

## Source layout

The custom target lives in `Workspace/Sources`, with checks in `Workspace/Tests`. The upstream Boring Notch Xcode app is retained in `boringNotch` and is not changed into a different product. The new target directly compiles its existing NotchShape and adapts its music integration. See `Workspace/NOTICE.md` for the upstream commit, licensing, and credits.

This first version does not include hidden menu bar icon management, notification interception, phone call controls, Bluetooth/AirPods activities, brightness HUD replacement, or arbitrary third-party plugins. Those are separate integrations rather than placeholder buttons. The supplied video is used as a design reference, not included in the app.

## Weather implementation and data

Forecasts come directly from Open-Meteo, and location search uses its GeoNames-based geocoding endpoint. The app sends the selected city's public coordinates or the explicitly submitted search query to those services. No device location permission, API key, account, clipboard, file shelf, or contact data is involved. Weather snapshots and city/unit choices are stored locally. Cached data remains available after a connection failure and the interface shows its last update and refresh error.

Forecast timestamps are requested as absolute Unix times and displayed in the selected place's time zone. The API returns metric temperatures and wind; Fahrenheit conversion is local. Incomplete hourly or daily rows are skipped without mixing their dates. A cached forecast is never reused for a different place. Refreshes are coalesced and automatic requests are limited to a 15-minute interval while Home's weather badge, the Weather tab, or the weather window is visible. One small in-flight request may finish into the cache after a view closes; no background refresh timer remains.

The larger view uses native Canvas drawing capped at 12 frames per second for rain, snow, cloud drift, sunshine glow, and night stars. The notch card is static. Effects stop while the weather window is covered, minimized, closed, or the app is inactive. Reduced motion and Low Power Mode also stop animations. Closing the window releases its hosting view. No image/video assets or browser rendering are used for the atmosphere.

The 69 isolated checks include weather condition icons, temperature conversion, URL parameters and coordinate validation, incomplete data, hourly timestamp alignment, time zones, cached forecasts, cache/city isolation, saved display preferences, and sample data without network requests. A live integration check is also available:

```sh
"../Notch Workspace.app/Contents/MacOS/NotchWorkspace" --weather-check
```

The Open-Meteo public endpoint is for non-commercial use; its weather data is provided under CC BY 4.0. The window credits Open-Meteo and GeoNames. See https://open-meteo.com/en/terms and https://open-meteo.com/en/docs/geocoding-api . Preview mode's weather is explicitly marked as sample data. The screenshot in this repository is a real forecast captured during development, not a promise of current conditions.

## macOS 27.2 and reliability improvements

The app keeps using standard AppKit windows, its existing keyboard shortcut, and the working MediaRemoteAdapter bridge. No new dependency or expanded system permission is needed for the notch, Pomodoro, music bridge, or weather.

Clipboard capture now checks the public `NSPasteboard.accessBehavior` API on macOS 15.4 and later. If macOS reports `alwaysDeny`, capture stops and its polling timer is removed. The Clipboard tab explains that access is blocked and provides System Settings and Check access buttons. Returning to the app rechecks a previously blocked state. Allowing access starts collecting new copies; copies made while blocked are skipped. The app never changes macOS privacy settings itself. See [Apple's pasteboard access documentation](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum/alwaysdeny).

Pomodoro persistence writes only at state changes, not once per second. Saved values are validated, corrupt values are ignored, and the original session duration is retained if future timer settings change. Restoring an already expired session advances only once and leaves the next phase paused. Countdown updates run once per second only while the running timer is visible; paused countdowns do not schedule updates. Timer changes leave the expanded panel's geometry unchanged.

The music view now clears the previous track and artwork when the media bridge reports that the active session ended. Additional isolated checks cover this, running and paused timer restoration, reset/cancellation, configuration edits, corrupt saved state, compact panel centering, clipboard denial/recovery, and collection after access is restored.
