// SPDX-License-Identifier: GPL-3.0
import SwiftUI

struct HomeView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var music: MusicService
    @ObservedObject var shelf: ShelfService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var weather: WeatherService
    @State private var showPomodoro = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                FocusHomeCard(pomodoro: model.pomodoro, weather: weather, settingsOpen: showPomodoro,
                              openWeather: { model.tab = .weather }, editTimes: { showPomodoro.toggle() })
                    .frame(width: 244)
                if showPomodoro {
                    Surface {
                        PomodoroSettingsView(pomodoro: model.pomodoro, onDone: { showPomodoro = false })
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                        .frame(maxWidth: .infinity)
                } else {
                    MusicHomeCard(music: music, reduceMotion: model.reduceMotion, openPlayer: { model.tab = .music })
                        .frame(maxWidth: .infinity)
                }
            }.frame(height: showPomodoro ? 272 : 194)
            if !showPomodoro {
                HStack(spacing: 10) {
                    homeLink(.files, detail: shelf.entries.isEmpty ? "Drop files here" : "\(shelf.entries.count) saved references", color: WorkspaceTheme.mint)
                    homeLink(.clipboard, detail: clipboard.blockedBySystem ? "Access blocked" : clipboard.enabled ? "\(clipboard.history.entries.count) recent copies" : "Enable when you need it", color: WorkspaceTheme.accent)
                    homeLink(.actions, detail: "Apps, sites & shortcuts", color: WorkspaceTheme.blue)
                }.frame(height: 94)
            }
        }
    }
    private func homeLink(_ tab: WorkspaceTab, detail: String, color: Color) -> some View {
        Button { model.tab = tab } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: tab.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.28))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                    Text(detail).font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(14)
                .background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceTheme.line))
        }.buttonStyle(HoverButton(radius: 16))
    }
}

private struct FocusHomeCard: View {
    @ObservedObject var pomodoro: PomodoroService
    @ObservedObject var weather: WeatherService
    let settingsOpen: Bool
    let openWeather: () -> Void
    let editTimes: () -> Void

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Label("Focus", systemImage: "timer").font(.system(size: 11, weight: .semibold)).foregroundStyle(WorkspaceTheme.mint)
                    Spacer(minLength: 2)
                    WeatherHomeBadge(weather: weather, action: openWeather)
                    Button(action: editTimes) {
                        Image(systemName: settingsOpen ? "xmark" : "slider.horizontal.3").font(.system(size: 11)).foregroundStyle(settingsOpen ? WorkspaceTheme.accent : WorkspaceTheme.dim).frame(width: 27, height: 26)
                    }.buttonStyle(HoverButton(radius: 8))
                        .help("Customize Pomodoro").accessibilityLabel(settingsOpen ? "Done customizing Pomodoro" : "Customize Pomodoro")
                }
                if pomodoro.running {
                    TimelineView(.periodic(from: .now, by: 1)) { context in readout(at: context.date) }
                } else if pomodoro.active {
                    readout(at: Date())
                } else {
                    TimelineView(.periodic(from: Calendar.current.dateInterval(of: .minute, for: Date())!.start, by: 60)) { context in readout(at: context.date) }
                }
                HStack(spacing: 6) {
                    Button { pomodoro.toggle() } label: {
                        Label(pomodoro.active ? pomodoro.running ? "Pause" : "Resume" : "\(pomodoro.configuration.focusMinutes) min focus", systemImage: pomodoro.running ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    }.buttonStyle(QuietButton(tint: WorkspaceTheme.mint))
                        .accessibilityLabel(pomodoro.active ? pomodoro.buttonTitle : "Start \(pomodoro.configuration.focusMinutes) minute focus")
                    if pomodoro.active {
                        Button("Reset") { pomodoro.restartCurrentSession() }
                            .help("Reset this session to its full duration, paused")
                        Button("Cancel") { pomodoro.reset() }
                            .help("Cancel the Pomodoro cycle")
                    }
                    Spacer(minLength: 0)
                }.font(.system(size: 10, weight: .medium)).buttonStyle(QuietButton())
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
    private func readout(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pomodoro.active ? timeLabel(ceil(pomodoro.remaining(at: date))) : date.formatted(.dateTime.hour().minute()))
                .font(.system(size: 43, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(pomodoro.active ? WorkspaceTheme.mint : .white)
                .lineLimit(1).minimumScaleFactor(0.65)
                .contentTransition(.identity)
            Text(pomodoro.active ? "\(pomodoro.phase.title) · Round \(max(1, pomodoro.round)) of \(pomodoro.configuration.roundsBeforeLongBreak)\(pomodoro.running ? "" : " · Paused")" : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1).minimumScaleFactor(0.85)
            GeometryReader { geometry in
                let progress = pomodoro.active ? 1 - pomodoro.remaining(at: date) / max(1, pomodoro.sessionDuration) : 0
                Capsule().fill(.white.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule().fill(WorkspaceTheme.mint.opacity(0.7)).frame(width: geometry.size.width * min(1, max(0, progress)))
                    }
            }.frame(height: 2).padding(.top, 3).accessibilityHidden(true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MusicHomeCard: View {
    @ObservedObject var music: MusicService
    let reduceMotion: Bool
    let openPlayer: () -> Void

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("NOW PLAYING").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(WorkspaceTheme.dim)
                    Spacer()
                    Waveform(playing: music.snapshot.isPlaying, reduceMotion: reduceMotion)
                }
                HStack(spacing: 12) {
                    Artwork(data: music.snapshot.artwork, size: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(music.snapshot.hasTrack ? music.snapshot.title : "Ready when you are")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.94)).lineLimit(2)
                        Text(music.snapshot.hasTrack ? music.snapshot.artist : "Play something you love.")
                            .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Button { music.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 12)).frame(width: 26, height: 32) }
                        .disabled(!music.snapshot.hasTrack).opacity(music.snapshot.hasTrack ? 1 : 0.3).accessibilityLabel("Previous track")
                    Button { music.snapshot.hasTrack ? music.toggle() : music.openPlayer() } label: {
                        Image(systemName: music.snapshot.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.black).frame(width: 34, height: 34).background(.white.opacity(0.94), in: Circle())
                    }.accessibilityLabel(music.snapshot.isPlaying ? "Pause playback" : "Play music")
                    Button { music.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 12)).frame(width: 26, height: 32) }
                        .disabled(!music.snapshot.hasTrack).opacity(music.snapshot.hasTrack ? 1 : 0.3).accessibilityLabel("Next track")
                    Spacer(minLength: 0)
                    Button(action: openPlayer) {
                        Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.accent).frame(width: 30, height: 32)
                    }.help("Open player").accessibilityLabel("Open player")
                }.buttonStyle(HoverButton(radius: 10))
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
