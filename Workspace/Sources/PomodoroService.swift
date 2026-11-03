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
    enum Phase: String, Codable { case idle, focus, shortBreak, longBreak
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
    @Published private(set) var sessionDuration: TimeInterval = 0
    var onCompletion: ((Phase) -> Void)?
    private let defaults: UserDefaults
    private var deadlineTask: Task<Void, Never>?
    private let scheduleTimers: Bool
    private struct SavedSession: Codable {
        let phase: Phase
        let deadline: Date?
        let remaining: TimeInterval
        let duration: TimeInterval
        let completedRounds: Int
    }
    var running: Bool { deadline != nil }
    var active: Bool { phase != .idle }
    var round: Int { min(configuration.roundsBeforeLongBreak, completedRounds + (phase == .focus ? 1 : 0)) }
    var buttonTitle: String { !active ? "Start focus" : running ? "Pause \(phase.title.lowercased())" : "Resume \(phase.title.lowercased())" }
    init(defaults: UserDefaults = .standard, now: Date = Date(), scheduleTimers: Bool = true) {
        self.defaults = defaults
        self.scheduleTimers = scheduleTimers
        if let data = defaults.data(forKey: "pomodoroConfiguration"), let saved = try? JSONDecoder().decode(PomodoroConfiguration.self, from: data) {
            configuration = saved.validated()
        } else { configuration = PomodoroConfiguration() }
        restoreSession(at: now)
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
        sessionDuration = pausedRemaining
        resume(at: date)
    }
    func pause(at date: Date = Date()) {
        guard let deadline else { return }
        if date >= deadline { finish(at: date); return }
        pausedRemaining = max(0, deadline.timeIntervalSince(date))
        self.deadline = nil
        deadlineTask?.cancel()
        persistSession()
    }
    func resume(at date: Date = Date()) {
        guard active, !running else { return }
        deadlineTask?.cancel()
        deadline = date.addingTimeInterval(pausedRemaining)
        scheduleDeadline()
        persistSession()
    }
    func finish(at date: Date = Date()) {
        advance(at: date, autoStart: configuration.autoAdvance, notify: true)
    }
    private func advance(at date: Date, autoStart: Bool, notify: Bool) {
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
        sessionDuration = pausedRemaining
        if autoStart { resume(at: date) } else { persistSession() }
        if notify { onCompletion?(finished) }
    }
    func reset() {
        deadlineTask?.cancel()
        deadline = nil
        pausedRemaining = 0
        phase = .idle
        completedRounds = 0
        sessionDuration = 0
        defaults.removeObject(forKey: "pomodoroSession")
    }
    func restartCurrentSession() {
        guard active else { return }
        deadlineTask?.cancel()
        deadline = nil
        let minutes = phase == .focus ? configuration.focusMinutes : phase == .shortBreak ? configuration.shortBreakMinutes : configuration.longBreakMinutes
        pausedRemaining = Double(minutes * 60)
        sessionDuration = pausedRemaining
        persistSession()
    }
    /// Preserve the absolute deadline on quit or update. Never turn a quit into
    /// a completed session, and never count time away as extra focus rounds.
    func shutdown() {
        persistSession()
        deadlineTask?.cancel()
    }
    private func persistSession() {
        guard active else { defaults.removeObject(forKey: "pomodoroSession"); return }
        let value = SavedSession(phase: phase, deadline: deadline, remaining: pausedRemaining, duration: sessionDuration, completedRounds: completedRounds)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "pomodoroSession") }
    }
    private func restoreSession(at date: Date) {
        guard let data = defaults.data(forKey: "pomodoroSession") else { return }
        guard let value = try? JSONDecoder().decode(SavedSession.self, from: data),
              value.phase != .idle, value.remaining.isFinite, value.duration.isFinite,
              value.duration > 0, value.duration <= 180 * 60, value.remaining >= 0,
              value.remaining <= value.duration, (0...12).contains(value.completedRounds),
              value.deadline.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true else {
            defaults.removeObject(forKey: "pomodoroSession")
            return
        }
        phase = value.phase
        completedRounds = value.completedRounds
        sessionDuration = value.duration
        pausedRemaining = value.remaining
        if let end = value.deadline {
            if end <= date {
                // A session that ended while the app was closed advances once.
                // Leave the next phase paused, including with auto-advance on.
                advance(at: date, autoStart: false, notify: false)
            } else {
                deadline = min(end, date.addingTimeInterval(value.duration))
                scheduleDeadline()
                persistSession()
            }
        }
    }
    func reconcileAfterWake(at date: Date = Date()) {
        guard let deadline else { return }
        if deadline <= date { finish(at: date) }
        else { scheduleDeadline() }
    }
    private func scheduleDeadline() {
        deadlineTask?.cancel()
        guard scheduleTimers, let deadline else { return }
        let seconds = max(0, deadline.timeIntervalSinceNow)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }
    deinit { deadlineTask?.cancel() }
}
