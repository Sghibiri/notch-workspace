// SPDX-License-Identifier: GPL-3.0
import AppKit
import Combine

@MainActor
final class ShelfService: ObservableObject {
    @Published private(set) var entries: [ShelfEntry] = []
    @Published var error: String?
    private let storage: ShelfPersistence
    init(directory: URL? = nil) {
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notch Workspace", isDirectory: true)
        storage = ShelfPersistence(file: folder.appendingPathComponent("shelf.json"))
        do { entries = try storage.load() }
        catch { self.error = "Your saved shelf could not be read. The original files are safe." }
    }
    func add(_ urls: [URL]) {
        var next = entries
        for url in urls where url.isFileURL && FileManager.default.fileExists(atPath: url.path) {
            guard !next.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { continue }
            do { next.insert(try ShelfEntry(url: url), at: 0) }
            catch { self.error = "Could not add \(url.lastPathComponent)." }
        }
        commit(Array(next.prefix(48)))
    }
    func chooseFiles() {
        let picker = NSOpenPanel()
        picker.title = "Add to your shelf"
        picker.prompt = "Add to Shelf"
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = true
        picker.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.add(picker.urls) }
        }
    }
    func remove(_ id: UUID) { commit(entries.filter { $0.id != id }) }
    func clear() { commit([]) }
    func open(_ entry: ShelfEntry) {
        guard entry.exists else { error = "This file has moved or is unavailable. Remove it and add it again."; return }
        NSWorkspace.shared.open(entry.url)
    }
    func reveal(_ entry: ShelfEntry) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
    private func commit(_ next: [ShelfEntry]) {
        do { try storage.save(next); entries = next }
        catch { self.error = "The shelf could not be saved. Try again after checking available disk space." }
    }
}
