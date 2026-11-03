// SPDX-License-Identifier: GPL-3.0
import AppKit

enum WorkspaceTests {
    @MainActor static func run() -> Int32 {
        var failures: [String] = []
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            count += 1
            if !condition() { failures.append(name) }
        }
        var history = ClipboardHistory(capacity: 2)
        history.insert("  \n")
        check(history.entries.isEmpty, "Blank copies are ignored")
        history.insert("alpha"); history.insert("beta"); history.insert("alpha")
        check(history.entries.map(\.text) == ["alpha", "beta"], "Deduplication moves a clip to the front")
        history.insert("gamma")
        check(history.entries.map(\.text) == ["gamma", "alpha"], "Old history is evicted at capacity")
        check(history.matching("ALP").map(\.text) == ["alpha"], "Search is case insensitive")
        history.insert(String(repeating: "x", count: 100_001))
        check(history.entries.count == 2, "Large clipboard payloads are ignored")
        history.clear(); check(history.entries.isEmpty, "History can be cleared")
        check(QuickAction.isValidWebsite("https://example.com/a?q=hello"), "HTTPS action accepts a normal URL")
        check(!QuickAction.isValidWebsite("javascript:alert(1)"), "Script URLs are rejected")
        check(!QuickAction.isValidWebsite("file:///etc/passwd"), "File URLs are rejected as websites")
        check(!QuickAction.isValidWebsite("https://"), "Website actions require a host")

        check(AppVersion("v0.10.0")! > AppVersion("v0.9.9")!, "Update versions compare numbers instead of sorting text")
        check(AppVersion("1.2.3")! > AppVersion("1.2.3-rc.1")!, "A final release follows its prereleases")
        check(AppVersion("1.2.3-beta.10")! > AppVersion("1.2.3-beta.2")!, "Numbered prereleases use numeric ordering")
        check(AppVersion("1.2.3+build.42") == AppVersion("v1.2.3"), "Build metadata does not cause false update prompts")
        let malformedVersions = ["", "v", "1.2", "1.2.3.4", "1.-2.3", "1.02.3", "1.2.3-beta..1", "1.2.3-01", "1.2.3+", "1.2.3/evil", "999999999999999999999999.0.0"]
        check(malformedVersions.allSatisfy { AppVersion($0) == nil }, "Malformed and overflowing remote version tags are rejected")
        let releasesJSON = """
        [{"tag_name":"v0.9.0","draft":false,"prerelease":true},
         {"tag_name":"v99.0.0","draft":true},
         {"tag_name":"invalid","draft":false},
         {"tag_name":"v0.10.0","draft":false,"prerelease":true}]
        """
        let releases = (try? JSONDecoder().decode([WorkspaceRelease].self, from: Data(releasesJSON.utf8))) ?? []
        let newest = WorkspaceRelease.newest(in: releases)
        check(newest?.tag_name == "v0.10.0", "Update checks include public development releases and ignore drafts and invalid tags")
        check(newest?.url.absoluteString == "https://github.com/Sghibiri/notch-workspace/releases/tag/v0.10.0", "Update links point to this project's release page")
        check(WorkspaceRelease.newest(in: []) == nil, "An empty release response does not claim the app is current")

        let geometry = PanelGeometry(screenFrame: CGRect(x: -1512, y: 200, width: 1512, height: 982), cameraWidth: 180, cameraHeight: 32)
        check(geometry.frame(expanded: true).maxY == 1182, "Panel attaches to the selected screen's top")
        check(geometry.frame(expanded: true).midX == -756, "Panel centers on displays with negative coordinates")
        check(geometry.frame(expanded: false).width < geometry.frame(expanded: true).width, "Collapsed panel frees neighboring menu space")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("a file with spaces.txt")
            try Data("Original file stays unchanged".utf8).write(to: file)
            let entry = try ShelfEntry(url: file)
            let store = ShelfPersistence(file: root.appendingPathComponent("shelf.json"))
            try store.save([entry])
            let loaded = try store.load()
            check(loaded.count == 1 && loaded[0].url.standardizedFileURL == file.standardizedFileURL, "Shelf bookmarks survive a save and reload")
            let shelf = ShelfService(directory: root.appendingPathComponent("service"))
            shelf.add([file, file])
            check(shelf.entries.count == 1, "Shelf rejects duplicate file references")
            shelf.add([root.appendingPathComponent("missing.txt")])
            check(shelf.entries.count == 1, "Shelf skips files that do not exist")
            shelf.clear()
            check(FileManager.default.fileExists(atPath: file.path), "Clearing the shelf preserves original files")
            let contents = try String(contentsOf: file, encoding: .utf8)
            check(contents == "Original file stays unchanged", "Shelf operations do not modify file contents")

            let pasteboard = NSPasteboard(name: .init("NotchWorkspaceTests-\(UUID().uuidString)"))
            defer { pasteboard.releaseGlobally() }
            let suite = "NotchWorkspaceTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let clipboard = ClipboardService(pasteboard: pasteboard, defaults: defaults, startMonitoring: false)
            pasteboard.clearContents(); pasteboard.setString("not collected", forType: .string)
            clipboard.captureIfChanged()
            check(clipboard.history.entries.isEmpty, "Clipboard capture is off until enabled")
            clipboard.enabled = true
            pasteboard.clearContents(); pasteboard.setString("synthetic test copy", forType: .string)
            clipboard.captureIfChanged()
            check(clipboard.history.entries.first?.text == "synthetic test copy", "Enabled clipboard captures a new text copy")
            pasteboard.clearContents(); pasteboard.setString("concealed test item", forType: .string)
            pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            clipboard.captureIfChanged()
            check(clipboard.history.entries.count == 1, "Concealed clipboard contents are excluded")
            clipboard.copy(clipboard.history.entries[0]); clipboard.captureIfChanged()
            check(clipboard.history.entries.count == 1 && pasteboard.string(forType: .string) == "synthetic test copy", "Recopying does not duplicate history")

            let music = MusicService(start: false)
            music.consume("{\"payload\":{\"title\":\"Test song\",\"artist\":\"Artist\",\"bundleIdentifier\":\"com.test.player\",\"duration\":120,\"elapsedTime\":30,\"playing\":true,\"artworkData\":\"YWJj\"}}")
            check(music.snapshot.hasTrack && music.snapshot.isPlaying, "Music metadata updates the playback state")
            music.consume("{\"diff\":true,\"payload\":{\"playing\":false}}")
            check(music.snapshot.artwork == Data("abc".utf8) && music.snapshot.title == "Test song", "Partial music updates preserve artwork and title")
            music.consume("invalid metadata")
            check(music.snapshot.title == "Test song", "Malformed metadata leaves the last good state")
            music.consume("{\"payload\":null}")
            check(!music.snapshot.hasTrack && music.snapshot.artwork == nil, "Ending a media session clears stale titles and artwork")
            var snapshot = MediaSnapshot()
            snapshot.duration = 100; snapshot.elapsed = 90; snapshot.isPlaying = true; snapshot.updatedAt = Date(timeIntervalSince1970: 0)
            check(snapshot.position(at: Date(timeIntervalSince1970: 50)) == 100, "Playback progress clamps to the track duration")

            let pomodoro = PomodoroService(defaults: defaults)
            var config = PomodoroConfiguration()
            config.focusMinutes = 2; config.shortBreakMinutes = 1; config.longBreakMinutes = 3; config.roundsBeforeLongBreak = 2
            pomodoro.configure(config)
            let start = Date()
            pomodoro.toggle(at: start)
            check(pomodoro.phase == .focus && pomodoro.remaining(at: start) == 120, "Pomodoro uses the configured focus duration")
            pomodoro.pause(at: start.addingTimeInterval(35))
            check(!pomodoro.running && pomodoro.remaining() == 85, "Pause preserves remaining focus time")
            pomodoro.resume(at: start.addingTimeInterval(100))
            check(pomodoro.remaining(at: start.addingTimeInterval(100)) == 85, "Resume restores the remaining duration")
            pomodoro.restartCurrentSession()
            check(pomodoro.phase == .focus && !pomodoro.running && pomodoro.remaining() == 120, "Reset restores the current session duration and pauses it")
            pomodoro.resume(at: start.addingTimeInterval(100))
            pomodoro.finish(at: start.addingTimeInterval(185))
            check(pomodoro.phase == .shortBreak && !pomodoro.running && pomodoro.completedRounds == 1, "Focus completion offers a short break without auto-starting")
            pomodoro.finish(); pomodoro.finish()
            check(pomodoro.phase == .longBreak && pomodoro.remaining() == 180, "The configured number of rounds triggers a long break")
            pomodoro.finish()
            check(pomodoro.phase == .focus && pomodoro.completedRounds == 0, "Long break completion resets the round cycle")
            pomodoro.reset()
            check(pomodoro.phase == .idle && pomodoro.deadline == nil, "Reset cancels the scheduled Pomodoro")
            config.focusMinutes = -100; config.longBreakMinutes = 10000
            pomodoro.configure(config)
            check(pomodoro.configuration.focusMinutes == 1 && pomodoro.configuration.longBreakMinutes == 120, "Saved Pomodoro durations are kept within valid bounds")
            let restored = PomodoroService(defaults: defaults)
            check(restored.configuration == pomodoro.configuration, "Pomodoro preferences persist across launches")
            restored.reset(); pomodoro.reset()

            let sessionDate = Date()
            let durable = PomodoroService(defaults: defaults, now: sessionDate, scheduleTimers: false)
            var durableConfig = PomodoroConfiguration()
            durableConfig.focusMinutes = 2
            durableConfig.shortBreakMinutes = 1
            durable.configure(durableConfig)
            durable.start(.focus, at: sessionDate)
            durable.shutdown()
            let relaunched = PomodoroService(defaults: defaults, now: sessionDate.addingTimeInterval(30), scheduleTimers: false)
            check(relaunched.running && relaunched.phase == .focus && relaunched.remaining(at: sessionDate.addingTimeInterval(30)) == 90, "A running Pomodoro keeps its original deadline across relaunches")
            relaunched.pause(at: sessionDate.addingTimeInterval(45))
            relaunched.shutdown()
            let pausedSession = PomodoroService(defaults: defaults, now: sessionDate.addingTimeInterval(3600), scheduleTimers: false)
            check(!pausedSession.running && pausedSession.remaining() == 75, "A paused Pomodoro stays paused with the same remaining time after relaunch")
            pausedSession.restartCurrentSession()
            let resetSession = PomodoroService(defaults: defaults, now: sessionDate.addingTimeInterval(3601), scheduleTimers: false)
            check(!resetSession.running && resetSession.remaining() == 120, "Reset session duration survives a restart")
            resetSession.reset()
            let cancelledSession = PomodoroService(defaults: defaults, now: sessionDate, scheduleTimers: false)
            check(!cancelledSession.active && defaults.data(forKey: "pomodoroSession") == nil, "Cancelling removes the saved session")
            durableConfig.autoAdvance = true
            cancelledSession.configure(durableConfig)
            cancelledSession.start(.focus, at: sessionDate)
            cancelledSession.shutdown()
            let endedWhileAway = PomodoroService(defaults: defaults, now: sessionDate.addingTimeInterval(86_400), scheduleTimers: false)
            check(endedWhileAway.phase == .shortBreak && !endedWhileAway.running && endedWhileAway.completedRounds == 1, "An elapsed session advances once and waits instead of counting unattended rounds")
            let openedAgain = PomodoroService(defaults: defaults, now: sessionDate.addingTimeInterval(86_401), scheduleTimers: false)
            check(openedAgain.phase == .shortBreak && openedAgain.completedRounds == 1 && openedAgain.remaining() == 60, "Repeated relaunches do not count an ended session twice")
            openedAgain.reset()
            durableConfig.focusMinutes = 10
            openedAgain.configure(durableConfig)
            openedAgain.start(.focus, at: sessionDate)
            durableConfig.focusMinutes = 1
            openedAgain.configure(durableConfig)
            openedAgain.shutdown()
            let editedConfigSession = PomodoroService(defaults: defaults, now: sessionDate.addingTimeInterval(10), scheduleTimers: false)
            check(editedConfigSession.sessionDuration == 600 && editedConfigSession.remaining(at: sessionDate.addingTimeInterval(10)) == 590, "Editing future durations does not shorten the restored current session")
            editedConfigSession.reset()
            defaults.set(Data("not a saved session".utf8), forKey: "pomodoroSession")
            let damagedSession = PomodoroService(defaults: defaults, scheduleTimers: false)
            check(!damagedSession.active && defaults.data(forKey: "pomodoroSession") == nil, "Malformed saved sessions are ignored safely")
            let badSession = "{\"phase\":\"focus\",\"remaining\":-1,\"duration\":120,\"completedRounds\":0}"
            defaults.set(Data(badSession.utf8), forKey: "pomodoroSession")
            let negativeSession = PomodoroService(defaults: defaults, scheduleTimers: false)
            check(!negativeSession.active, "Invalid saved timer values cannot create an active timer")
            let timerGeometry = geometry.frame(expanded: false, showsTimer: true)
            check(timerGeometry.width > geometry.compactSize.width && timerGeometry.midX == geometry.screenFrame.midX, "Compact timer gains room while staying centered around the camera")
            check(geometry.frame(expanded: true, showsTimer: true) == geometry.frame(expanded: true), "Timer changes do not move or resize the expanded panel")

            defaults.set(true, forKey: "clipboardEnabled")
            var allowClipboard = false
            let protectedClipboard = ClipboardService(pasteboard: pasteboard, defaults: defaults, startMonitoring: false, accessAllowed: { allowClipboard })
            pasteboard.clearContents(); pasteboard.setString("blocked synthetic content", forType: .string)
            protectedClipboard.captureIfChanged()
            check(protectedClipboard.blockedBySystem && protectedClipboard.history.entries.isEmpty, "System-denied clipboard access stops text collection")
            allowClipboard = true
            protectedClipboard.recheckAccess()
            check(!protectedClipboard.blockedBySystem && protectedClipboard.history.entries.isEmpty, "Restoring permission does not collect a copy made while blocked")
            pasteboard.clearContents(); pasteboard.setString("new synthetic copy after approval", forType: .string)
            protectedClipboard.captureIfChanged()
            check(protectedClipboard.history.entries.first?.text == "new synthetic copy after approval", "Capture resumes for new copies after access is restored")
            allowClipboard = false
            pasteboard.clearContents(); pasteboard.setString("blocked again", forType: .string)
            protectedClipboard.captureIfChanged()
            check(protectedClipboard.blockedBySystem && protectedClipboard.history.entries.count == 1, "Revoking access prevents further collection and preserves prior history")
            protectedClipboard.enabled = false
            protectedClipboard.clear()

            check(WeatherCondition(code: 0, isDay: false).symbol == "moon.stars.fill", "Clear nights use the night icon")
            check(WeatherCondition(code: 75, isDay: true).mood == .snow && WeatherCondition(code: 95, isDay: true).mood == .storm, "Snow and thunderstorm codes select their matching effects")
            check(WeatherCondition(code: 999, isDay: true).mood == .unknown, "Unknown weather codes do not claim clear skies")
            check(WeatherUnit.fahrenheit.value(0) == 32 && WeatherUnit.fahrenheit.value(100) == 212, "Temperature conversion uses the Celsius scale correctly")
            check(WeatherUnit.celsius.format(16.6) == "17°", "Temperatures round for display")
            let forecastURL = try WeatherService.forecastURL(for: .estoril)
            let params = URLComponents(url: forecastURL, resolvingAgainstBaseURL: false)!.queryItems!
            check(forecastURL.host == "api.open-meteo.com" && params.contains(.init(name: "timezone", value: "auto")), "Forecast requests use the provider and location time zone")
            check(params.contains(.init(name: "timeformat", value: "unixtime")), "Forecast timestamps are requested as absolute instants")
            let invalidPlace = WeatherPlace(id: 0, name: "Invalid", latitude: 1000, longitude: 0, country: nil, admin1: nil, timezone: nil)
            let invalidURL = try? WeatherService.forecastURL(for: invalidPlace)
            check(invalidURL == nil, "Invalid coordinates are rejected before making a request")
            let fixture = """
            {"timezone":"Europe/Lisbon","current":{"time":1793577600,"temperature_2m":16.1,"apparent_temperature":14.3,"relative_humidity_2m":58,"wind_speed_10m":8,"weather_code":0,"is_day":0},"hourly":{"time":[1793577600,1793581200,1793584800],"temperature_2m":[16.1,null,17.2],"precipitation_probability":[5,null,40],"weather_code":[0,2,61],"is_day":[0,1,1]},"daily":{"time":[1793577600,1793664000],"temperature_2m_min":[12,13],"temperature_2m_max":[20,21],"weather_code":[0],"sunrise":[1793602800],"sunset":[1793638800],"precipitation_probability_max":[15],"uv_index_max":[3]}}
            """
            let decodedWeather = try JSONDecoder().decode(WeatherAPIResponse.self, from: Data(fixture.utf8))
            let forecast = try decodedWeather.snapshot(place: .estoril, fetchedAt: Date(timeIntervalSince1970: 1793577600))
            check(forecast.hours.count == 2 && forecast.days.count == 1, "Missing forecast fields skip incomplete rows without misaligning arrays")
            check(forecast.temperature == 16.1 && forecast.humidity == 58 && forecast.wind == 8, "Current weather values survive decoding")
            check(forecast.hours[1].code == 61 && forecast.hours[1].precipitationChance == 40, "Hourly conditions stay attached to their own timestamp")
            check(forecast.timeZone.identifier == "Europe/Lisbon", "Forecast dates use Estoril's time zone")
            check(forecast.upcomingHours(at: Date(timeIntervalSince1970: 1793584800)).count == 1, "The hourly view excludes past forecast slots")
            let weatherFolder = root.appendingPathComponent("weather")
            try FileManager.default.createDirectory(at: weatherFolder, withIntermediateDirectories: true)
            try JSONEncoder().encode(forecast).write(to: weatherFolder.appendingPathComponent("weather.json"))
            let weather = WeatherService(defaults: defaults, directory: weatherFolder)
            check(weather.snapshot?.temperature == 16.1 && !weather.isLoading, "Cached weather loads without starting a network request")
            weather.unit = .fahrenheit
            weather.effectsEnabled = false
            let restoredWeather = WeatherService(defaults: defaults, directory: weatherFolder)
            check(restoredWeather.unit == .fahrenheit && !restoredWeather.effectsEnabled, "Weather display and animation choices persist")
            let otherPlace = WeatherPlace(id: 1, name: "Another city", latitude: 40, longitude: -8, country: "Portugal", admin1: nil, timezone: "Europe/Lisbon")
            defaults.set(try JSONEncoder().encode(otherPlace), forKey: "weatherPlace")
            let differentCity = WeatherService(defaults: defaults, directory: weatherFolder)
            check(differentCity.snapshot == nil, "A saved forecast is not reused for a different city")
            let previewWeather = WeatherService(defaults: defaults, directory: weatherFolder, preview: true)
            check(previewWeather.preview && previewWeather.snapshot?.place == .estoril && !previewWeather.isLoading, "Weather preview uses explicit sample data without network access")
            weather.stop(); restoredWeather.stop(); differentCity.stop(); previewWeather.stop()
        } catch { failures.append("Unexpected error: \(error)") }
        print("Notch Workspace: \(count - failures.count)/\(count) checks passed")
        for failure in failures { print("FAIL: \(failure)") }
        return failures.isEmpty ? 0 : 1
    }
}
