// Notch Workspace · a local modification of Boring Notch, 2026-11-02.
// SPDX-License-Identifier: GPL-3.0
import AppKit
import Combine
import Foundation

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case home, music, files, clipboard, actions
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .music: return "waveform"
        case .files: return "tray"
        case .clipboard: return "doc.on.clipboard"
        case .actions: return "bolt"
        }
    }
}

struct ClipboardEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
    var isLink: Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
}

struct ClipboardHistory {
    private(set) var entries: [ClipboardEntry] = []
    let capacity: Int
    init(capacity: Int = 40) { self.capacity = max(1, capacity) }
    mutating func insert(_ text: String, at date: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 100_000 else { return }
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(text: text, date: date), at: 0)
        entries = Array(entries.prefix(capacity))
    }
    mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    mutating func clear() { entries.removeAll() }
    func matching(_ query: String) -> [ClipboardEntry] {
        query.isEmpty ? entries : entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
}

struct ShelfEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let bookmark: Data
    let originalPath: String
    let name: String
    let addedAt: Date
    init(url: URL) throws {
        id = UUID()
        bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        originalPath = url.standardizedFileURL.path
        name = url.lastPathComponent
        addedAt = Date()
    }
    var url: URL {
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? URL(fileURLWithPath: originalPath)
    }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

struct ShelfPersistence {
    let file: URL
    func load() throws -> [ShelfEntry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([ShelfEntry].self, from: Data(contentsOf: file))
    }
    func save(_ entries: [ShelfEntry]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

struct QuickAction: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var symbol: String
    var kind: Kind
    var target: String
    enum Kind: String, Codable { case application, shortcut, website }
    static func isValidWebsite(_ target: String) -> Bool {
        guard let url = URL(string: target) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
}

struct MediaSnapshot {
    var title = "Nothing playing"
    var artist = "Start something you love."
    var album = ""
    var bundleIdentifier = ""
    var artwork: Data?
    var isPlaying = false
    var duration: Double = 0
    var elapsed: Double = 0
    var rate: Double = 1
    var updatedAt = Date()
    var hasTrack: Bool { !bundleIdentifier.isEmpty && title != "Nothing playing" && !title.isEmpty }
    func position(at date: Date = Date()) -> Double {
        let delta = isPlaying ? max(0, date.timeIntervalSince(updatedAt)) * rate : 0
        return min(max(0, elapsed + delta), max(0, duration))
    }
}

struct PanelGeometry {
    let screenFrame: CGRect
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    var compactSize: CGSize { CGSize(width: max(260, cameraWidth + 88), height: max(32, cameraHeight)) }
    var expandedSize: CGSize { CGSize(width: min(624, screenFrame.width - 40), height: 394) }
    func frame(expanded: Bool) -> CGRect {
        let size = expanded ? expandedSize : compactSize
        return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
