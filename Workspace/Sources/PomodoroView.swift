// SPDX-License-Identifier: GPL-3.0
import SwiftUI

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
