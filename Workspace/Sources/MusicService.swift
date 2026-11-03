// Adapted from Boring Notch's NowPlayingController by Alexander (2025).
// Uses the bundled MediaRemoteAdapter by Jonas van den Berg (BSD-3-Clause).
// SPDX-License-Identifier: GPL-3.0
import AppKit
import Combine

@MainActor
final class MusicService: ObservableObject {
    @Published private(set) var snapshot = MediaSnapshot()
    @Published private(set) var status: String?
    private var process: Process?
    private var pipe: Pipe?
    private var reader: Task<Void, Never>?
    private var commandProcesses: [UUID: Process] = [:]
    private var restartTask: Task<Void, Never>?
    private var attempts = 0
    private var stopped = false

    init(start: Bool = true) { if start { startStream() } }
    private func adapter() -> (script: String, framework: String)? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = Bundle.main.privateFrameworksPath else { return nil }
        return (script.path, frameworks + "/MediaRemoteAdapter.framework")
    }
    func startStream() {
        guard process == nil, !stopped else { return }
        guard let paths = adapter() else { status = "Music integration is unavailable in this build."; return }
        let child = Process()
        let pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [paths.script, paths.framework, "stream", "--no-diff", "--debounce=150"]
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamEnded() }
        }
        do {
            try child.run()
            self.process = child
            self.pipe = pipe
            status = nil
            reader = Task { [weak self] in
                do {
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        guard !Task.isCancelled else { return }
                        self?.consume(line)
                    }
                } catch { /* Termination triggers recovery; no metadata is logged. */ }
            }
        } catch { status = "Could not connect to Now Playing. Reopen the app to retry." }
    }
    func consume(_ line: String) {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if root["payload"] is NSNull {
            snapshot = MediaSnapshot()
            status = nil
            return
        }
        guard let payload = root["payload"] as? [String: Any] else { return }
        let diff = root["diff"] as? Bool ?? false
        var next = diff ? snapshot : MediaSnapshot()
        next.title = payload["title"] as? String ?? (diff ? snapshot.title : "Nothing playing")
        next.artist = payload["artist"] as? String ?? (diff ? snapshot.artist : "Start something you love.")
        next.album = payload["album"] as? String ?? (diff ? snapshot.album : "")
        next.bundleIdentifier = payload["parentApplicationBundleIdentifier"] as? String ?? payload["bundleIdentifier"] as? String ?? (diff ? snapshot.bundleIdentifier : "")
        if let value = payload["playing"] as? Bool { next.isPlaying = value }
        if let value = payload["duration"] as? Double { next.duration = value.isFinite ? max(0, value) : 0 }
        if let value = payload["elapsedTime"] as? Double { next.elapsed = value.isFinite ? max(0, value) : 0 }
        else if diff { next.elapsed = snapshot.position() }
        if let value = payload["playbackRate"] as? Double { next.rate = value.isFinite ? max(0, value) : 1 }
        if let encoded = payload["artworkData"] as? String { next.artwork = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let timestamp = payload["timestamp"] as? String,
           let date = ISO8601DateFormatter().date(from: timestamp) { next.updatedAt = date }
        else { next.updatedAt = Date() }
        snapshot = next
        attempts = 0
    }
    func toggle() { command("send", "2") }
    func next() { command("send", "4") }
    func previous() { command("send", "5") }
    func seek(_ value: Double) {
        guard value.isFinite else { return }
        command("seek", String(Int64(max(0, min(value, snapshot.duration)) * 1_000_000)))
    }
    private func command(_ operation: String, _ value: String) {
        guard let paths = adapter(), !stopped else { return }
        let id = UUID()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [paths.script, paths.framework, operation, value]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] process in
            let failed = process.terminationStatus != 0
            Task { @MainActor in
                self?.commandProcesses.removeValue(forKey: id)
                if failed { self?.status = "The player did not accept that command." }
            }
        }
        do { commandProcesses[id] = child; try child.run() }
        catch { commandProcesses.removeValue(forKey: id); status = "Could not send the playback command." }
    }
    func openPlayer() {
        let identifiers = [snapshot.bundleIdentifier, "com.spotify.client", "com.apple.Music"].filter { !$0.isEmpty }
        for identifier in identifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
    }
    private func streamEnded() {
        process = nil
        reader?.cancel()
        pipe = nil
        guard !stopped else { return }
        attempts += 1
        guard attempts <= 3 else { status = "Now Playing disconnected. Reopen the app to reconnect."; return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.startStream()
        }
    }
    func stop() {
        stopped = true
        restartTask?.cancel()
        reader?.cancel()
        if let process, process.isRunning { process.terminate() }
        for child in commandProcesses.values where child.isRunning { child.terminate() }
        process = nil
        commandProcesses.removeAll()
        try? pipe?.fileHandleForReading.close()
        pipe = nil
    }
    func seedPreview() {
        snapshot.title = "Midnight, in motion"
        snapshot.artist = "Your soundtrack · Now Playing"
        snapshot.bundleIdentifier = "com.apple.Music"
        snapshot.duration = 238
        snapshot.elapsed = 83
        snapshot.isPlaying = true
    }
}
