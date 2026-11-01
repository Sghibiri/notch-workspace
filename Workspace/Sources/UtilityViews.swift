// SPDX-License-Identifier: GPL-3.0
import SwiftUI

struct FilesView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var shelf: ShelfService
    var body: some View {
        VStack(spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your file shelf").font(.system(size: 17, weight: .semibold))
                    Text("Drop here. Drag anywhere.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.dim)
                }
                Spacer()
                Button { shelf.chooseFiles() } label: { Label("Add files", systemImage: "plus").font(.system(size: 10, weight: .medium)) }.buttonStyle(QuietButton())
                if !shelf.entries.isEmpty {
                    Button { shelf.clear(); model.notify("Shelf cleared. Original files are untouched.") } label: { Image(systemName: "tray").font(.system(size: 11)) }
                        .buttonStyle(QuietButton()).help("Clear shelf references").accessibilityLabel("Clear shelf")
                }
            }
            if shelf.entries.isEmpty {
                EmptyCard(symbol: "tray.and.arrow.down", title: "A landing spot for your files", detail: "Drag files onto the notch to keep them close.\nYour originals stay right where they are.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 17))
                    .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(WorkspaceTheme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(shelf.entries) { entry in
                            FileTile(entry: entry, shelf: shelf)
                        }
                    }
                }
            }
            if let error = shelf.error {
                HStack {
                    Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                    Spacer()
                    Button("Dismiss") { shelf.error = nil }.font(.system(size: 10)).buttonStyle(.plain)
                }
            }
        }
    }
}

struct FileTile: View {
    let entry: ShelfEntry
    @ObservedObject var shelf: ShelfService
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 30, height: 30).opacity(entry.exists ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(entry.exists ? entry.url.deletingLastPathComponent().lastPathComponent : "File unavailable").font(.system(size: 9)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Open") { shelf.open(entry) }.disabled(!entry.exists)
                Button("Show in Finder") { shelf.reveal(entry) }
                ShareLink(item: entry.url) { Text("Share…") }.disabled(!entry.exists)
                Divider()
                Button("Remove from shelf") { shelf.remove(entry.id) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 16, height: 25) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("File actions")
        }.padding(11).frame(height: 56)
            .background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceTheme.line))
            .onTapGesture(count: 2) { shelf.open(entry) }
            .onDrag { NSItemProvider(contentsOf: entry.url) ?? NSItemProvider(object: entry.url as NSURL) }
            .help(entry.url.path)
            .contextMenu {
                Button("Open") { shelf.open(entry) }
                Button("Show in Finder") { shelf.reveal(entry) }
                Button("Remove from shelf") { shelf.remove(entry.id) }
            }
    }
}

struct ClipboardView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var clipboard: ClipboardService
    @State private var query = ""
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Clipboard").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { clipboard.enabled.toggle() } label: {
                    Label(clipboard.enabled ? "Pause" : "Enable", systemImage: clipboard.enabled ? "pause.circle" : "play.circle").font(.system(size: 10))
                }.buttonStyle(QuietButton())
                Button { clipboard.clear(); model.notify("Clipboard history cleared.") } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(QuietButton()).disabled(clipboard.history.entries.isEmpty).help("Clear history").accessibilityLabel("Clear clipboard history")
            }
            if !clipboard.enabled && clipboard.history.entries.isEmpty {
                VStack(spacing: 15) {
                    EmptyCard(symbol: "doc.on.clipboard", title: "Good ideas deserve a second copy", detail: "Enable to remember your next 40 text copies.\nHistory stays in memory and clears on quit or lock.")
                    Button("Enable clipboard history") { clipboard.enabled = true; model.notify("Clipboard history enabled.") }
                        .buttonStyle(.borderedProminent).tint(WorkspaceTheme.accent).foregroundStyle(.black).font(.system(size: 11, weight: .medium))
                }.padding(.bottom, 16)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(WorkspaceTheme.dim)
                    TextField("Find a recent copy…", text: $query).textFieldStyle(.plain).font(.system(size: 11)).accessibilityLabel("Search clipboard")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(WorkspaceTheme.dim) }.buttonStyle(.plain) }
                }.padding(10).background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 10))
                let results = clipboard.history.matching(query)
                if results.isEmpty {
                    EmptyCard(symbol: "text.quote", title: query.isEmpty ? "Waiting for your next copy" : "No matching clips", detail: query.isEmpty ? "Copy text in any app and it will appear here." : "Try a different word.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(results) { entry in
                                HStack(spacing: 10) {
                                    Image(systemName: entry.isLink ? "link" : "text.alignleft").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.accent).frame(width: 20)
                                    Button {
                                        clipboard.copy(entry)
                                        model.notify("Copied. Paste it wherever you need it.")
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(entry.text).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(.white.opacity(0.85))
                                            Text(entry.date, style: .relative).font(.system(size: 8)).foregroundStyle(WorkspaceTheme.dim)
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    Button { clipboard.remove(entry.id) } label: { Image(systemName: "xmark").font(.system(size: 8)).foregroundStyle(WorkspaceTheme.dim).padding(5) }.buttonStyle(.plain).help("Remove clip").accessibilityLabel("Remove clip")
                                }.padding(11).background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 11))
                            }
                        }
                    }
                }
                HStack {
                    Text(clipboard.enabled ? "Remembering new copies" : "Paused · existing history is still available")
                    Spacer()
                    Text("\(clipboard.history.entries.count) / 40")
                }.font(.system(size: 9)).foregroundStyle(WorkspaceTheme.dim)
            }
        }
    }
}

struct ActionsView: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your next move").font(.system(size: 17, weight: .semibold))
                    Text("A few useful things, one click away.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.dim)
                }
                Spacer()
                Button { model.showActionEditor = true } label: { Label("Add action", systemImage: "plus").font(.system(size: 10)) }.buttonStyle(QuietButton()).disabled(model.actions.count >= 12)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    actionTile(model.pomodoro.buttonTitle, detail: "\(model.pomodoro.configuration.focusMinutes) / \(model.pomodoro.configuration.shortBreakMinutes) min", symbol: "timer", tint: WorkspaceTheme.mint) { model.toggleFocus() }
                    actionTile("Downloads", detail: "Find your latest files", symbol: "arrow.down.circle", tint: WorkspaceTheme.accent) { model.openDownloads() }
                    actionTile("Screenshot", detail: "Capture a moment", symbol: "viewfinder", tint: .white.opacity(0.85)) { model.openScreenshot() }
                    actionTile("Settings", detail: "Make yourself at home", symbol: "slider.horizontal.3", tint: .white.opacity(0.85)) { model.openSettings() }
                    ForEach(model.actions) { action in
                        actionTile(action.title, detail: action.kind == .shortcut ? "Run shortcut" : action.kind == .website ? "Open website" : "Open application", symbol: action.symbol, tint: WorkspaceTheme.accent) { model.run(action) }
                            .contextMenu { Button("Remove action") { model.removeAction(action.id) } }
                    }
                }
            }
        }
    }
    private func actionTile(_ title: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: symbol).font(.system(size: 17, weight: .light)).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text(detail).font(.system(size: 8)).foregroundStyle(WorkspaceTheme.dim).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(WorkspaceTheme.line))
        }.buttonStyle(.plain)
    }
}

struct ActionEditor: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var target = ""
    @State private var kind: QuickAction.Kind = .website
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make it yours").font(.system(size: 22, weight: .semibold))
            Text("Add a website, an app, or one of your Apple Shortcuts.").font(.system(size: 12)).foregroundStyle(.secondary)
            Picker("Action", selection: $kind) {
                Text("Website").tag(QuickAction.Kind.website)
                Text("App").tag(QuickAction.Kind.application)
                Text("Shortcut").tag(QuickAction.Kind.shortcut)
            }.pickerStyle(.segmented).onChange(of: kind) { _, _ in target = ""; error = nil }
            TextField("Name", text: $title).textFieldStyle(.roundedBorder)
            if kind == .application {
                HStack {
                    Text(target.isEmpty ? "Choose an application" : target).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Choose…", action: chooseApplication)
                }
            } else {
                TextField(kind == .website ? "https://example.com" : "Exact shortcut name", text: $target).textFieldStyle(.roundedBorder)
            }
            if kind == .shortcut { Text("Uses an existing shortcut from the Shortcuts app. macOS may ask for its permissions when it runs.").font(.system(size: 10)).foregroundStyle(.secondary) }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add action") {
                    if model.saveAction(title: title, kind: kind, target: target) { dismiss(); model.notify("Quick action added.") }
                    else { error = kind == .website ? "Add a name and a valid http or https address." : "Add a name and a valid destination." }
                }.buttonStyle(.borderedProminent).tint(WorkspaceTheme.accent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 425).preferredColorScheme(.dark)
    }
    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.begin { result in
            guard result == .OK, let url = panel.url, let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
            target = identifier
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var clipboard: ClipboardService
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 13) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 27)).foregroundStyle(WorkspaceTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notch Workspace").font(.system(size: 21, weight: .semibold))
                    Text("Your Mac, a little closer. · Version 0.1.0").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("Remember clipboard text", isOn: $clipboard.enabled)
            Text("Up to 40 text copies, kept only in memory. History clears when you quit or lock your Mac. Standard concealed and temporary clipboard items are skipped.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Clear clipboard history") { clipboard.clear() }
            Toggle("Reduce animation", isOn: $model.reduceMotion)
            PomodoroSettingsView(pomodoro: model.pomodoro)
            Text("Hover over the notch to open. Move away to close. Pin it to keep it open. Press Control–Option–Space to toggle it from any app.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Built from Boring Notch by TheBoredTeam, with music integration from MediaRemoteAdapter by Jonas van den Berg. This modified app is free software under GPL-3.0 and comes without warranty.").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("Boring Notch", destination: URL(string: "https://github.com/TheBoredTeam/boring.notch")!)
                Text("·")
                Button("License") {
                    if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) { NSWorkspace.shared.open(url) }
                }.buttonStyle(.link)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }.font(.system(size: 11))
        }.padding(28).frame(width: 440).preferredColorScheme(.dark)
    }
}
