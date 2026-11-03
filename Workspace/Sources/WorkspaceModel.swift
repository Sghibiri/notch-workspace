// SPDX-License-Identifier: GPL-3.0
import AppKit
import Combine

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var expanded = false
    @Published var tab: WorkspaceTab = .home
    @Published var pinned = false
    @Published var toast: String?
    @Published var showActionEditor = false
    @Published var actions: [QuickAction] = []
    @Published var cameraHeight: CGFloat = 32
    @Published var cameraWidth: CGFloat = 186
    @Published var reduceMotion: Bool {
        didSet { defaults.set(reduceMotion, forKey: "reduceMotion") }
    }
    let clipboard: ClipboardService
    let shelf: ShelfService
    let music: MusicService
    let pomodoro: PomodoroService
    let weather: WeatherService
    let defaults: UserDefaults
    let preview: Bool
    var requestToggle: (() -> Void)?
    var requestExpand: ((WorkspaceTab) -> Void)?
    var pointerChanged: ((Bool) -> Void)?
    var requestWeatherWindow: (() -> Void)?
    var requestLayoutUpdate: (() -> Void)?
    private var toastTask: Task<Void, Never>?
    private var pomodoroSubscription: AnyCancellable?
    private var shortcutProcesses: [UUID: Process] = [:]

    init(preview: Bool = false, storageDirectory: URL? = nil, defaults: UserDefaults = .standard) {
        self.preview = preview
        self.defaults = defaults
        reduceMotion = defaults.bool(forKey: "reduceMotion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        clipboard = ClipboardService(defaults: defaults, startMonitoring: !preview)
        shelf = ShelfService(directory: storageDirectory)
        music = MusicService(start: !preview)
        pomodoro = PomodoroService(defaults: defaults)
        weather = WeatherService(defaults: defaults, directory: storageDirectory, preview: preview)
        if let data = defaults.data(forKey: "quickActions"), let saved = try? JSONDecoder().decode([QuickAction].self, from: data) { actions = saved }
        if preview { music.seedPreview(); clipboard.seedPreview() }
        pomodoroSubscription = pomodoro.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            Task { @MainActor [weak self] in self?.requestLayoutUpdate?() }
        }
        pomodoro.onCompletion = { [weak self] phase in
            self?.requestExpand?(.home)
            self?.notify(phase == .focus ? "Focus complete. Time for a breather." : "Break complete. Ready for the next round?")
            NSSound.beep()
        }
    }
    func notify(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
    func toggleFocus() {
        pomodoro.toggle()
    }
    func saveAction(title: String, kind: QuickAction.Kind, target: String) -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !destination.isEmpty, actions.count < 12 else { return false }
        switch kind {
        case .website: guard QuickAction.isValidWebsite(destination) else { return false }
        case .application: guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: destination) != nil else { return false }
        case .shortcut: break
        }
        let action = QuickAction(id: UUID(), title: name, symbol: kind == .website ? "globe" : kind == .shortcut ? "square.stack.3d.up" : "app", kind: kind, target: destination)
        persistActions(actions + [action])
        return true
    }
    func removeAction(_ id: UUID) { persistActions(actions.filter { $0.id != id }) }
    private func persistActions(_ next: [QuickAction]) {
        do { let data = try JSONEncoder().encode(next); defaults.set(data, forKey: "quickActions"); actions = next }
        catch { notify("The quick action could not be saved.") }
    }
    func run(_ action: QuickAction) {
        switch action.kind {
        case .website:
            guard QuickAction.isValidWebsite(action.target), let url = URL(string: action.target) else { notify("That website address is invalid."); return }
            NSWorkspace.shared.open(url)
        case .application:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: action.target) else { notify("That application is no longer available."); return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .shortcut:
            let id = UUID()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", action.target]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] child in
                let success = child.terminationStatus == 0
                Task { @MainActor in
                    self?.shortcutProcesses.removeValue(forKey: id)
                    self?.notify(success ? "Shortcut finished." : "Shortcut failed. Check its name and permissions in Shortcuts.")
                }
            }
            do { shortcutProcesses[id] = process; try process.run(); notify("Running \(action.title)…") }
            catch { shortcutProcesses.removeValue(forKey: id); notify("Could not run that shortcut.") }
        }
    }
    func openDownloads() {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(url) }
    }
    func openSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!) }
    func openScreenshot() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    func stop() {
        music.stop()
        weather.stop()
        clipboard.clear()
        pomodoro.shutdown()
        toastTask?.cancel()
        for process in shortcutProcesses.values where process.isRunning { process.terminate() }
    }
}
