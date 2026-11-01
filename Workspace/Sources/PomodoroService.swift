// SPDX-License-Identifier: GPL-3.0
import Combine
import Foundation

struct PomodoroConfiguration: Codable, Equatable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var roundsBeforeLongBreak: Int = 4
    var autoAdvance = false
    func validated() -> Self {
        var value = self
        value.focusMinutes = min(180, max(1, focusMinutes))
        value.shortBreakMinutes = min(60, max(1, shortBreakMinutes))
        value.longBreakMinutes = min(120, max(1, longBreakMinutes))
        value.roundsBeforeLongBreak = min(12, max(2, roundsBeforeLongBreak))
        return value
    }
}

@MainActor
final class PomodoroService: ObservableObject {
    enum Phase: String { case idle, focus, shortBreak, longBreak
        var title: String {
            switch self {
            case .idle: return "Pomodoro"
            case .focus: return "Focus"
            case .shortBreak: return "Short break"
            case .longBreak: return "Long break"
            }
        }
    }
    @Published private(set) var configuration: PomodoroConfiguration
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var deadline: Date?
    @Published private(set) var pausedRemaining: TimeInterval = 0
    @Published private(set) var completedRounds = 0
    var onCompletion: ((Phase) -> Void)?
    private let defaults: UserDefaults
    private var deadlineTask: Task<Void, Never>?
    var running: Bool { deadline != nil }
    var active: Bool { phase != .idle }
    var round: Int { min(configuration.roundsBeforeLongBreak, completedRounds + (phase == .focus ? 1 : 0)) }
    var buttonTitle: String { !active ? "Start focus" : running ? "Pause \(phase.title.lowercased())" : "Resume \(phase.title.lowercased())" }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "pomodoroConfiguration"), let saved = try? JSONDecoder().decode(PomodoroConfiguration.self, from: data) {
            configuration = saved.validated()
        } else { configuration = PomodoroConfiguration() }
    }
    func configure(_ value: PomodoroConfiguration) {
        configuration = value.validated()
        if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: "pomodoroConfiguration") }
    }
    func remaining(at date: Date = Date()) -> TimeInterval {
        deadline.map { max(0, $0.timeIntervalSince(date)) } ?? pausedRemaining
    }
    func toggle(at date: Date = Date()) {
        if !active { start(.focus, at: date) }
        else if running { pause(at: date) }
        else { resume(at: date) }
    }
    func start(_ next: Phase, at date: Date = Date()) {
        deadlineTask?.cancel()
        if next == .idle { reset(); return }
        phase = next
        let minutes = next == .focus ? configuration.focusMinutes : next == .shortBreak ? configuration.shortBreakMinutes : configuration.longBreakMinutes
        pausedRemaining = Double(minutes * 60)
        resume(at: date)
    }
    func pause(at date: Date = Date()) {
        guard let deadline else { return }
        if date >= deadline { finish(at: date); return }
        pausedRemaining = max(0, deadline.timeIntervalSince(date))
        self.deadline = nil
        deadlineTask?.cancel()
    }
    func resume(at date: Date = Date()) {
        guard active, !running else { return }
        deadlineTask?.cancel()
        deadline = date.addingTimeInterval(pausedRemaining)
        scheduleDeadline()
    }
    func finish(at date: Date = Date()) {
        deadlineTask?.cancel()
        guard active else { return }
        let finished = phase
        deadline = nil
        if finished == .focus {
            completedRounds += 1
            phase = completedRounds >= configuration.roundsBeforeLongBreak ? .longBreak : .shortBreak
        } else {
            if finished == .longBreak { completedRounds = 0 }
            phase = .focus
        }
        let minutes = phase == .focus ? configuration.focusMinutes : phase == .shortBreak ? configuration.shortBreakMinutes : configuration.longBreakMinutes
        pausedRemaining = Double(minutes * 60)
        if configuration.autoAdvance { resume(at: date) }
        onCompletion?(finished)
    }
    func reset() {
        deadlineTask?.cancel()
        deadline = nil
        pausedRemaining = 0
        phase = .idle
        completedRounds = 0
    }
    func restartCurrentSession() {
        guard active else { return }
        deadlineTask?.cancel()
        deadline = nil
        let minutes = phase == .focus ? configuration.focusMinutes : phase == .shortBreak ? configuration.shortBreakMinutes : configuration.longBreakMinutes
        pausedRemaining = Double(minutes * 60)
    }
    func reconcileAfterWake(at date: Date = Date()) {
        guard let deadline else { return }
        if deadline <= date { finish(at: date) }
        else { scheduleDeadline() }
    }
    private func scheduleDeadline() {
        deadlineTask?.cancel()
        guard let deadline else { return }
        let seconds = max(0, deadline.timeIntervalSinceNow)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }
    deinit { deadlineTask?.cancel() }
}
