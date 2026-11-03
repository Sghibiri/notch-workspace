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
        HStack(spacing: 0) {
            Group {
            if music.snapshot.hasTrack { Artwork(data: music.snapshot.artwork, size: 19) }
            else { Image(systemName: "square.stack.3d.up.fill").font(.system(size: 13)).foregroundStyle(WorkspaceTheme.accent) }
            }.frame(width: model.pomodoro.active ? 46 : 23)
            Spacer(minLength: model.cameraWidth)
            if model.pomodoro.active {
                CompactPomodoroView(pomodoro: model.pomodoro).frame(width: 46)
            }
            else { Waveform(playing: music.snapshot.isPlaying, reduceMotion: model.reduceMotion) }
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
            HStack(spacing: 2) {
                ForEach(WorkspaceTab.allCases) { tab in
                    Button {
                        withAnimation(model.reduceMotion ? nil : .easeInOut(duration: 0.16)) { model.tab = tab }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbol).font(.system(size: 11, weight: .medium))
                            Text(tab.title).font(.system(size: 11, weight: .medium))
                        }.padding(.horizontal, 9).padding(.vertical, 9)
                            .foregroundStyle(model.tab == tab ? WorkspaceTheme.accent : WorkspaceTheme.dim)
                            .background(model.tab == tab ? WorkspaceTheme.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(HoverButton(radius: 10)).accessibilityLabel("\(tab.title) tab")
                }
                Spacer(minLength: 5)
                Button { model.pinned.toggle() } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin").font(.system(size: 12)).foregroundStyle(model.pinned ? WorkspaceTheme.accent : WorkspaceTheme.dim).frame(width: 29, height: 30)
                }.buttonStyle(HoverButton(radius: 9)).help(model.pinned ? "Unpin panel" : "Keep panel open").accessibilityLabel(model.pinned ? "Unpin panel" : "Pin panel")
                Button { model.requestPreferences?() } label: {
                    Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.dim).frame(width: 29, height: 30)
                }.buttonStyle(HoverButton(radius: 9)).help("Workspace settings").accessibilityLabel("Workspace settings")
            }.padding(.horizontal, 22).padding(.top, 5).padding(.bottom, 13)

            Group {
                switch model.tab {
                case .home: HomeView(model: model, music: music, shelf: model.shelf, clipboard: model.clipboard, weather: model.weather)
                case .weather: WeatherQuickView(model: model, weather: model.weather)
                case .music: MusicView(music: music)
                case .files: FilesView(model: model, shelf: model.shelf)
                case .clipboard: ClipboardView(model: model, clipboard: model.clipboard)
                case .actions: ActionsView(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 22)
            HStack(spacing: 6) {
                Circle().fill(model.toast == nil ? WorkspaceTheme.mint.opacity(0.6) : WorkspaceTheme.accent).frame(width: 4, height: 4)
                Text(model.toast ?? (model.pinned ? "Pinned open · unpin to close on exit" : "Pin the panel to keep it open"))
                    .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                Spacer()
                Label("On this Mac", systemImage: "lock").font(.system(size: 9)).foregroundStyle(.white.opacity(0.36))
            }.padding(.horizontal, 27).frame(height: 34)
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

struct MusicView: View {
    @ObservedObject var music: MusicService
    @State private var seeking = false
    @State private var seekValue: Double = 0
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 23) {
                Artwork(data: music.snapshot.artwork, size: 113)
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR SOUNDTRACK").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(WorkspaceTheme.accent)
                    Text(music.snapshot.title).font(.system(size: 23, weight: .semibold)).lineLimit(2)
                    Text(music.snapshot.artist).font(.system(size: 13)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                    Button { music.openPlayer() } label: { Label(music.snapshot.hasTrack ? "Open in player" : "Open a music app", systemImage: "arrow.up.right").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(WorkspaceTheme.accent).padding(.top, 6)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if music.snapshot.isPlaying {
                TimelineView(.periodic(from: .now, by: 1)) { context in progress(at: context.date) }
            } else { progress(at: Date()) }
            HStack(spacing: 30) {
                Button { music.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 18)).frame(width: 34, height: 40) }.disabled(!music.snapshot.hasTrack).accessibilityLabel("Previous track")
                Button { music.snapshot.hasTrack ? music.toggle() : music.openPlayer() } label: {
                    Image(systemName: music.snapshot.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)).foregroundStyle(.black).frame(width: 48, height: 48).background(.white, in: Circle())
                }.accessibilityLabel(music.snapshot.isPlaying ? "Pause playback" : "Play music")
                Button { music.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 18)).frame(width: 34, height: 40) }.disabled(!music.snapshot.hasTrack).accessibilityLabel("Next track")
            }.buttonStyle(HoverButton(radius: 14))
            if let status = music.status { Text(status).font(.system(size: 10)).foregroundStyle(WorkspaceTheme.dim) }
        }.padding(.vertical, 5)
    }
    private func progress(at date: Date) -> some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { seeking ? seekValue : music.snapshot.position(at: date) }, set: { seekValue = $0 }), in: 0...max(1, music.snapshot.duration), onEditingChanged: { value in
                if value { seekValue = music.snapshot.position() }
                seeking = value
                if !value { music.seek(seekValue) }
            }).tint(WorkspaceTheme.accent).disabled(!music.snapshot.hasTrack || music.snapshot.duration <= 0).accessibilityLabel("Playback position")
            HStack {
                Text(timeLabel(seeking ? seekValue : music.snapshot.position(at: date)))
                Spacer()
                Text(timeLabel(music.snapshot.duration))
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(WorkspaceTheme.dim)
        }
    }
}
