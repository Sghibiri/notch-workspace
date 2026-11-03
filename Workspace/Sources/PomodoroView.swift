// SPDX-License-Identifier: GPL-3.0
import SwiftUI

struct CompactPomodoroView: View {
    @ObservedObject var pomodoro: PomodoroService
    var body: some View {
        Group {
            if pomodoro.running {
                TimelineView(.periodic(from: .now, by: 1)) { context in countdown(at: context.date) }
            } else { countdown(at: Date()) }
        }
        .help("\(pomodoro.phase.title) timer · open the notch for Pause, Reset, and Cancel")
    }
    private func countdown(at date: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: pomodoro.running ? "timer" : "pause.fill").font(.system(size: 7, weight: .medium))
            Text(timeLabel(ceil(pomodoro.remaining(at: date)))).font(.system(size: 9, weight: .semibold, design: .monospaced)).monospacedDigit()
        }.foregroundStyle(pomodoro.phase == .focus ? WorkspaceTheme.mint : WorkspaceTheme.accent)
            .accessibilityLabel("\(pomodoro.phase.title), \(timeLabel(ceil(pomodoro.remaining(at: date)))), \(pomodoro.running ? "running" : "paused")")
    }
}

struct PomodoroSettingsView: View {
    @ObservedObject var pomodoro: PomodoroService
    var onDone: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Pomodoro", systemImage: "timer").font(.system(size: 14, weight: .semibold))
                Spacer()
                if let onDone { Button("Done", action: onDone).font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(WorkspaceTheme.accent) }
            }
            minutes("Focus", keyPath: \.focusMinutes, range: 1...180)
            minutes("Short break", keyPath: \.shortBreakMinutes, range: 1...60)
            minutes("Long break", keyPath: \.longBreakMinutes, range: 1...120)
            Stepper(value: configBinding(\.roundsBeforeLongBreak), in: 2...12) {
                HStack {
                    Text("Rounds before long break")
                    Spacer()
                    Text("\(pomodoro.configuration.roundsBeforeLongBreak)").monospacedDigit().foregroundStyle(WorkspaceTheme.accent)
                }.font(.system(size: 11))
            }.accessibilityLabel("Rounds before long break")
            Toggle("Start the next session automatically", isOn: configBinding(\.autoAdvance)).font(.system(size: 10))
            Text(pomodoro.active ? "Changes apply to the next session. Reset to begin with your new times." : "Your rhythm, your rules. Saved on this Mac.").font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func minutes(_ title: String, keyPath: WritableKeyPath<PomodoroConfiguration, Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: configBinding(keyPath), in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(pomodoro.configuration[keyPath: keyPath]) min").monospacedDigit().foregroundStyle(WorkspaceTheme.mint)
            }.font(.system(size: 11))
        }.accessibilityLabel("\(title) duration in minutes")
    }
    private func configBinding<Value>(_ keyPath: WritableKeyPath<PomodoroConfiguration, Value>) -> Binding<Value> {
        Binding(get: { pomodoro.configuration[keyPath: keyPath] }, set: { value in
            var config = pomodoro.configuration
            config[keyPath: keyPath] = value
            pomodoro.configure(config)
        })
    }
}
