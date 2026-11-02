// SPDX-License-Identifier: GPL-3.0
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var music: MusicService
    @State private var dropTarget = false
    var body: some View {
        VStack(spacing: 0) {
            if model.expanded {
                expandedContent
                    .transition(.opacity.combined(with: .offset(y: -8)))
            } else { compactContent.transition(.opacity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(topCornerRadius: model.expanded ? 10 : 5, bottomCornerRadius: model.expanded ? 26 : 12))
        .overlay(alignment: .bottom) {
            if dropTarget { Capsule().fill(WorkspaceTheme.accent).frame(width: 70, height: 3).padding(.bottom, 5) }
        }
        .preferredColorScheme(.dark)
        .onHover { model.pointerChanged?($0) }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget, perform: receiveFiles)
        .onChange(of: dropTarget) { _, value in if value { model.requestExpand?(.files) } }
        .onExitCommand { if !model.showActionEditor { model.pinned = false; model.requestToggle?() } }
        .sheet(isPresented: $model.showActionEditor) { ActionEditor(model: model) }
    }
    private var compactContent: some View {
        HStack {
            if music.snapshot.hasTrack { Artwork(data: music.snapshot.artwork, size: 19) }
            else { Image(systemName: "square.stack.3d.up.fill").font(.system(size: 13)).foregroundStyle(WorkspaceTheme.accent) }
            Spacer(minLength: model.cameraWidth)
            if model.pomodoro.active { Image(systemName: "timer").font(.system(size: 13)).foregroundStyle(WorkspaceTheme.mint) }
            else { Waveform(playing: music.snapshot.isPlaying) }
        }
        .padding(.horizontal, 17)
        .frame(height: max(32, model.cameraHeight))
        .contentShape(Rectangle())
        .onTapGesture { model.requestExpand?(.home) }
        .help("Open Notch Workspace · ⌃⌥Space")
    }
    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(WorkspaceTheme.accent).frame(width: 4, height: 4)
                    Text("WORKSPACE").font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(1.6).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Text("⌃⌥ SPACE").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
            }.padding(.horizontal, 28).frame(height: max(34, model.cameraHeight + 3))
            HStack(spacing: 3) {
                ForEach(WorkspaceTab.allCases) { tab in
                    Button {
                        withAnimation(model.reduceMotion ? nil : .easeInOut(duration: 0.16)) { model.tab = tab }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbol).font(.system(size: 11, weight: .medium))
                            Text(tab.title).font(.system(size: 11, weight: .medium))
                        }.padding(.horizontal, 8).padding(.vertical, 8)
                            .foregroundStyle(model.tab == tab ? .white : WorkspaceTheme.dim)
                            .background(model.tab == tab ? Color.white.opacity(0.105) : .clear, in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel("\(tab.title) tab")
                }
                Spacer(minLength: 5)
                Button { model.pinned.toggle() } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin").font(.system(size: 12)).foregroundStyle(model.pinned ? WorkspaceTheme.accent : WorkspaceTheme.dim)
                }.buttonStyle(.plain).help(model.pinned ? "Unpin panel" : "Keep panel open").accessibilityLabel(model.pinned ? "Unpin panel" : "Pin panel")
            }.padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 18)

            Group {
                switch model.tab {
                case .home: HomeView(model: model, music: music, shelf: model.shelf, clipboard: model.clipboard, weather: model.weather)
                case .weather: WeatherQuickView(model: model, weather: model.weather)
                case .music: MusicView(music: music)
                case .files: FilesView(model: model, shelf: model.shelf)
                case .clipboard: ClipboardView(model: model, clipboard: model.clipboard)
                case .actions: ActionsView(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 26)
            HStack(spacing: 6) {
                Circle().fill(model.toast == nil ? WorkspaceTheme.mint.opacity(0.6) : WorkspaceTheme.accent).frame(width: 4, height: 4)
                Text(model.toast ?? "A little space. A lot within reach.")
                    .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                Spacer()
                Text("LOCAL BY DESIGN").font(.system(size: 7, weight: .medium)).tracking(1.2).foregroundStyle(.white.opacity(0.23))
            }.padding(.horizontal, 29).frame(height: 38)
        }
    }
    private func receiveFiles(_ providers: [NSItemProvider]) -> Bool {
        let items = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !items.isEmpty else { return false }
        model.requestExpand?(.files)
        for provider in items {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? URL { url = value }
                else if let value = item as? String { url = URL(string: value) }
                else { url = nil }
                if let url { Task { @MainActor in model.shelf.add([url]); model.notify("Added to your shelf.") } }
            }
        }
        return true
    }
}

struct HomeView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var music: MusicService
    @ObservedObject var shelf: ShelfService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var weather: WeatherService
    @State private var showPomodoro = false
    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 9) {
                                Text(context.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                                    .font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(WorkspaceTheme.dim)
                                WeatherHomeBadge(weather: weather) { model.tab = .weather }
                            }
                            if model.pomodoro.active {
                                Text(timeLabel(model.pomodoro.remaining(at: context.date))).font(.system(size: 47, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(WorkspaceTheme.mint)
                            } else {
                                Text(context.date.formatted(.dateTime.hour().minute())).font(.system(size: 47, weight: .light, design: .rounded)).monospacedDigit()
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Button { model.toggleFocus() } label: {
                            Label(model.pomodoro.active ? model.pomodoro.buttonTitle : "\(model.pomodoro.configuration.focusMinutes) min focus", systemImage: model.pomodoro.running ? "pause.circle" : "timer")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(WorkspaceTheme.mint)
                        }.buttonStyle(.plain)
                    }.padding(.top, 4)
                    HStack(spacing: 12) {
                        if model.pomodoro.active {
                            Button("Reset") { model.pomodoro.restartCurrentSession() }
                                .help("Reset this session to its full duration, paused")
                            Button("Cancel") { model.pomodoro.reset() }
                                .help("Cancel the Pomodoro cycle")
                        }
                        Button { showPomodoro.toggle() } label: {
                            Label(showPomodoro ? "Done" : "Times", systemImage: "slider.horizontal.3")
                        }.help("Customize Pomodoro")
                            .accessibilityLabel(showPomodoro ? "Done customizing Pomodoro" : "Customize Pomodoro")
                    }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
                    if model.pomodoro.active {
                        Text("\(model.pomodoro.phase.title.uppercased()) · ROUND \(max(1, model.pomodoro.round)) / \(model.pomodoro.configuration.roundsBeforeLongBreak)")
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                if showPomodoro {
                    Surface {
                        PomodoroSettingsView(pomodoro: model.pomodoro, onDone: { showPomodoro = false })
                    }.frame(width: 305)
                } else {
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("NOW PLAYING").font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(WorkspaceTheme.dim)
                            Spacer()
                            Waveform(playing: music.snapshot.isPlaying)
                        }
                        HStack(spacing: 11) {
                            Artwork(data: music.snapshot.artwork, size: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(music.snapshot.hasTrack ? music.snapshot.title : "Ready when you are").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(music.snapshot.hasTrack ? music.snapshot.artist : "Your soundtrack lives here.").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                            }
                        }
                        HStack {
                            Button { model.tab = .music } label: { Text("Open player").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.accent) }.buttonStyle(.plain)
                            Spacer()
                            Button { music.snapshot.hasTrack ? music.toggle() : music.openPlayer() } label: {
                                Image(systemName: music.snapshot.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 12)).frame(width: 25, height: 20)
                            }.buttonStyle(.plain).accessibilityLabel(music.snapshot.isPlaying ? "Pause" : "Play")
                        }
                    }
                }.frame(width: 286)
                }
            }
            if !showPomodoro {
            HStack(spacing: 10) {
                homeLink(.files, detail: shelf.entries.isEmpty ? "Drop something in" : "\(shelf.entries.count) within reach", color: WorkspaceTheme.mint)
                homeLink(.clipboard, detail: clipboard.enabled ? "\(clipboard.history.entries.count) recent clips" : "Ready to enable", color: WorkspaceTheme.accent)
                homeLink(.actions, detail: "Make your next move", color: Color(red: 0.63, green: 0.79, blue: 1))
            }
            }
        }
    }
    private func homeLink(_ tab: WorkspaceTab, detail: String, color: Color) -> some View {
        Button { model.tab = tab } label: {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: tab.symbol).font(.system(size: 16, weight: .light)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.title).font(.system(size: 11, weight: .medium))
                    Text(detail).font(.system(size: 9)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(WorkspaceTheme.line))
        }.buttonStyle(.plain)
    }
}

struct MusicView: View {
    @ObservedObject var music: MusicService
    @State private var seeking = false
    @State private var seekValue: Double = 0
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 23) {
                Artwork(data: music.snapshot.artwork, size: 113)
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR SOUNDTRACK").font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(WorkspaceTheme.accent)
                    Text(music.snapshot.title).font(.system(size: 21, weight: .semibold)).lineLimit(2)
                    Text(music.snapshot.artist).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                    Button { music.openPlayer() } label: { Label(music.snapshot.hasTrack ? "Open in player" : "Open a music app", systemImage: "arrow.up.right").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(WorkspaceTheme.accent).padding(.top, 6)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    Slider(value: Binding(get: { seeking ? seekValue : music.snapshot.position(at: context.date) }, set: { seekValue = $0 }), in: 0...max(1, music.snapshot.duration), onEditingChanged: { value in
                        if value { seekValue = music.snapshot.position() }
                        seeking = value
                        if !value { music.seek(seekValue) }
                    }).tint(WorkspaceTheme.accent).disabled(!music.snapshot.hasTrack || music.snapshot.duration <= 0).accessibilityLabel("Playback position")
                    HStack {
                        Text(timeLabel(seeking ? seekValue : music.snapshot.position(at: context.date)))
                        Spacer()
                        Text(timeLabel(music.snapshot.duration))
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(WorkspaceTheme.dim)
                }
            }
            HStack(spacing: 30) {
                Button { music.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 18)) }.disabled(!music.snapshot.hasTrack).accessibilityLabel("Previous track")
                Button { music.snapshot.hasTrack ? music.toggle() : music.openPlayer() } label: {
                    Image(systemName: music.snapshot.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)).foregroundStyle(.black).frame(width: 48, height: 48).background(.white, in: Circle())
                }.accessibilityLabel(music.snapshot.isPlaying ? "Pause playback" : "Play music")
                Button { music.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 18)) }.disabled(!music.snapshot.hasTrack).accessibilityLabel("Next track")
            }.buttonStyle(.plain)
            if let status = music.status { Text(status).font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim) }
        }.padding(.vertical, 5)
    }
}
