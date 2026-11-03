// SPDX-License-Identifier: GPL-3.0
import AppKit
import Combine
import ServiceManagement

enum AppInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0"
    static let repository = URL(string: "https://github.com/Sghibiri/notch-workspace")!
    static let releases = repository.appendingPathComponent("releases")
}

@MainActor
final class LoginItemService: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var error: String?
    let canRegister: Bool
    private let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        canRegister = !preview && (path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/"))
    }
    func refresh() {
        guard !preview else { return }
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
    func setEnabled(_ value: Bool) {
        guard !preview else { return }
        guard !value || canRegister else {
            error = "Move Notch Workspace to Applications first, then reopen it."
            return
        }
        error = nil
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "macOS could not change launch at login. Review Login Items in System Settings and try again."
        }
        refresh()
    }
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

/// Numeric releases are compared component by component; prereleases follow
/// SemVer ordering, so 0.10.0 is newer than 0.9.0 and beta.10 follows beta.2.
struct AppVersion: Comparable, Equatable {
    let numbers: [Int]
    let prerelease: [String]

    init?(_ text: String) {
        var value = text
        if value.hasPrefix("v") { value.removeFirst() }
        let buildParts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else { return nil }
        if buildParts.count == 2, !Self.validIdentifiers(String(buildParts[1]), prerelease: false) { return nil }
        let releaseParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let components = releaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }
        var result: [Int] = []
        for component in components {
            guard !component.isEmpty, component.utf8.allSatisfy({ (48...57).contains($0) }),
                  component.count == 1 || component.first != "0", let number = Int(component) else { return nil }
            result.append(number)
        }
        numbers = result
        if releaseParts.count == 2 {
            let suffix = String(releaseParts[1])
            guard Self.validIdentifiers(suffix, prerelease: true) else { return nil }
            prerelease = suffix.split(separator: ".").map(String.init)
        } else { prerelease = [] }
    }
    private static func validIdentifiers(_ text: String, prerelease: Bool) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { return false }
            let numeric = part.utf8.allSatisfy { (48...57).contains($0) }
            return !prerelease || !numeric || part.count == 1 || part.first != "0"
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.numbers, rhs.numbers) where left != right { return left < right }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = left.utf8.allSatisfy { (48...57).contains($0) }
            let rightNumeric = right.utf8.allSatisfy { (48...57).contains($0) }
            if leftNumeric && rightNumeric { return left.count == right.count ? left < right : left.count < right.count }
            if leftNumeric != rightNumeric { return leftNumeric }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct WorkspaceRelease: Decodable, Equatable {
    let tag_name: String
    let draft: Bool
    var version: AppVersion? { AppVersion(tag_name) }
    // Construct the destination from the fixed repository and validated tag,
    // rather than following a URL supplied in a network response.
    var url: URL { AppInfo.releases.appendingPathComponent("tag").appendingPathComponent(tag_name) }
    static func newest(in releases: [Self]) -> Self? {
        releases.filter { !$0.draft && $0.version != nil }.max { $0.version! < $1.version! }
    }
}

@MainActor
final class UpdateService: ObservableObject {
    enum State: Equatable {
        case idle, checking, current, available(WorkspaceRelease), failed
    }
    @Published private(set) var state = State.idle
    private var task: Task<Void, Never>?
    let preview: Bool
    init(preview: Bool = false) { self.preview = preview }

    func check() {
        guard !preview, state != .checking else { return }
        state = .checking
        task = Task { [weak self] in
            do {
                let release = try await Self.fetchNewest()
                guard !Task.isCancelled, let self else { return }
                if let installed = AppVersion(AppInfo.version), let remote = release.version, remote > installed {
                    state = .available(release)
                } else { state = .current }
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed
            }
        }
    }
    static func fetchNewest() async throws -> WorkspaceRelease {
        let url = URL(string: "https://api.github.com/repos/Sghibiri/notch-workspace/releases?per_page=20")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchWorkspace/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 1_000_000 else {
            throw URLError(.badServerResponse)
        }
        let releases = try JSONDecoder().decode([WorkspaceRelease].self, from: data)
        guard let newest = WorkspaceRelease.newest(in: releases) else { throw URLError(.cannotParseResponse) }
        return newest
    }
    func stop() { task?.cancel(); task = nil }
}
