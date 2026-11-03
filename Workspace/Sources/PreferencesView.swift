// SPDX-License-Identifier: GPL-3.0
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var clipboard: ClipboardService
    @State private var showFocusTimes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 13) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 25, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
                        .frame(width: 50, height: 50).background(WorkspaceTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Notch Workspace").font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("A little space, within reach. · \(AppInfo.version)").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.dim)
                    }
                }.padding(.bottom, 2)
                SettingsSection(title: "GENERAL", symbol: "slider.horizontal.3") {
                    LoginItemRow(loginItem: model.loginItem)
                    Divider().overlay(.white.opacity(0.04))
                    Toggle(isOn: $model.reduceMotion) {
                        settingLabel("Reduce animation", detail: "Keep transitions and the music waveform still.")
                    }.accessibilityLabel("Reduce animation")
                    Divider().overlay(.white.opacity(0.04))
                    Label("Control–Option–Space opens your workspace from any app.", systemImage: "keyboard")
                        .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.dim).fixedSize(horizontal: false, vertical: true)
                }
                SettingsSection(title: "CLIPBOARD", symbol: "doc.on.clipboard") {
                    Toggle(isOn: $clipboard.enabled) {
                        settingLabel("Remember text copies", detail: "Up to 40 copies, kept in memory. Clears on quit or lock.")
                    }.accessibilityLabel("Remember clipboard text")
                    HStack {
                        Text("Concealed and temporary items are skipped.").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim)
                        Spacer()
                        Button("Clear history") { clipboard.clear() }.font(.system(size: 10)).buttonStyle(QuietButton()).disabled(clipboard.history.entries.isEmpty)
                    }
                }
                SettingsSection(title: "FOCUS", symbol: "timer") {
                    DisclosureGroup("Pomodoro times", isExpanded: $showFocusTimes) {
                        PomodoroSettingsView(pomodoro: model.pomodoro).padding(.top, 14)
                    }.font(.system(size: 12, weight: .medium))
                }
                SettingsSection(title: "UPDATES", symbol: "arrow.down.circle") {
                    UpdateSettingsRow(updates: model.updates)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Built from Boring Notch by TheBoredTeam, with music integration from MediaRemoteAdapter by Jonas van den Berg. GPL-3.0, without warranty.")
                        .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Link("Source", destination: AppInfo.repository)
                        Link("Boring Notch", destination: URL(string: "https://github.com/TheBoredTeam/boring.notch")!)
                        Button("License") {
                            if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) { NSWorkspace.shared.open(url) }
                        }.buttonStyle(.link)
                        Spacer()
                        Button("Quit") { NSApp.terminate(nil) }.buttonStyle(QuietButton())
                    }.font(.system(size: 11))
                }.padding(.horizontal, 2)
            }.padding(26)
        }.frame(width: 500, height: 650)
            .background(Color(red: 0.035, green: 0.035, blue: 0.045))
            .toggleStyle(.switch).controlSize(.small).tint(WorkspaceTheme.accent).preferredColorScheme(.dark)
            .onExitCommand { NSApp.keyWindow?.performClose(nil) }
    }
    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(WorkspaceTheme.dim).padding(.leading, 3)
            Surface {
                VStack(alignment: .leading, spacing: 14) { content }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct LoginItemRow: View {
    @ObservedObject var loginItem: LoginItemService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Launch at login").font(.system(size: 12, weight: .medium))
                    Text(loginItem.canRegister ? "Keep your workspace ready when you sign in." : "Move the app to Applications, then reopen it to enable.")
                        .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(!loginItem.canRegister && !loginItem.enabled).accessibilityLabel("Launch at login")
            if loginItem.needsApproval || loginItem.error != nil {
                HStack(alignment: .top) {
                    Text(loginItem.error ?? "Approve Notch Workspace in Login Items to finish enabling.").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.accent).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Login Items") { loginItem.openLoginItems() }.font(.system(size: 10)).buttonStyle(QuietButton())
                }
            }
        }.onAppear { loginItem.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}

private struct UpdateSettingsRow: View {
    @ObservedObject var updates: UpdateService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Version \(AppInfo.version)").font(.system(size: 12, weight: .medium))
                    Text("Checks GitHub only when you ask.").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim)
                }
                Spacer()
                if updates.state == .checking { ProgressView().controlSize(.small).accessibilityLabel("Checking for updates") }
                Button(updates.state == .checking ? "Checking…" : "Check for updates") { updates.check() }
                    .font(.system(size: 11)).buttonStyle(QuietButton(tint: WorkspaceTheme.accent)).disabled(updates.state == .checking || updates.preview)
            }
            switch updates.state {
            case .current:
                Label("You're up to date.", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.mint)
            case .available(let release):
                HStack {
                    Label("\(release.tag_name) is available", systemImage: "arrow.down.circle").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.mint)
                    Spacer()
                    Link("View release", destination: release.url).font(.system(size: 11, weight: .medium))
                }
            case .failed:
                HStack {
                    Text("Couldn't check right now. Try again, or view releases.").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim)
                    Spacer()
                    Link("Releases", destination: AppInfo.releases).font(.system(size: 11))
                }
            case .idle, .checking: EmptyView()
            }
        }
    }
}
