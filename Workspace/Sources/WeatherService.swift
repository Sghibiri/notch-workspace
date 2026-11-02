// SPDX-License-Identifier: GPL-3.0
import Combine
import Foundation

@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var place: WeatherPlace
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var unit: WeatherUnit { didSet { defaults.set(unit.rawValue, forKey: "weatherUnit") } }
    @Published var effectsEnabled: Bool { didSet { defaults.set(effectsEnabled, forKey: "weatherEffects") } }
    let preview: Bool
    private let defaults: UserDefaults
    private let cacheFile: URL
    private let session: URLSession
    private var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?

    init(defaults: UserDefaults = .standard, directory: URL? = nil, preview: Bool = false) {
        self.defaults = defaults
        self.preview = preview
        unit = WeatherUnit(rawValue: defaults.string(forKey: "weatherUnit") ?? "") ?? .celsius
        effectsEnabled = defaults.object(forKey: "weatherEffects") as? Bool ?? true
        if let data = defaults.data(forKey: "weatherPlace"), let saved = try? JSONDecoder().decode(WeatherPlace.self, from: data), saved.valid { place = saved }
        else { place = .estoril }
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notch Workspace", isDirectory: true)
        cacheFile = folder.appendingPathComponent("weather.json")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        session = URLSession(configuration: config)
        if preview { place = .estoril; snapshot = .preview() }
        else if let data = try? Data(contentsOf: cacheFile), let saved = try? JSONDecoder().decode(WeatherSnapshot.self, from: data), saved.place == place { snapshot = saved }
    }
    static func forecastURL(for place: WeatherPlace) throws -> URL {
        guard place.valid else { throw WeatherDataError.invalidLocation }
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            .init(name: "latitude", value: String(place.latitude)), .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max"),
            .init(name: "timezone", value: "auto"), .init(name: "timeformat", value: "unixtime"), .init(name: "forecast_days", value: "7"),
            .init(name: "temperature_unit", value: "celsius"), .init(name: "wind_speed_unit", value: "kmh"), .init(name: "precipitation_unit", value: "mm")
        ]
        guard let url = parts.url else { throw WeatherDataError.invalidLocation }
        return url
    }
    static func fetch(place: WeatherPlace, session: URLSession = .shared) async throws -> WeatherSnapshot {
        let (data, response) = try await session.data(from: forecastURL(for: place))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else { throw WeatherDataError.badResponse }
        return try JSONDecoder().decode(WeatherAPIResponse.self, from: data).snapshot(place: place)
    }
    func refresh(force: Bool = false) {
        guard !preview, !isLoading else { return }
        if !force, let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < 900 { return }
        isLoading = true
        error = nil
        let requestedPlace = place
        let id = UUID()
        refreshID = id
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.refreshID == id { self.isLoading = false; self.refreshTask = nil; self.refreshID = nil } }
            do {
                let next = try await Self.fetch(place: requestedPlace, session: self.session)
                guard !Task.isCancelled, self.refreshID == id, self.place == requestedPlace else { return }
                self.snapshot = next
                if let data = try? JSONEncoder().encode(next) {
                    try? FileManager.default.createDirectory(at: self.cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: self.cacheFile, options: .atomic)
                }
            } catch {
                guard !Task.isCancelled, self.refreshID == id, self.place == requestedPlace else { return }
                self.error = self.snapshot == nil ? "Weather could not be loaded. Check your connection and try again." : "Could not refresh. Showing the last saved forecast."
            }
        }
    }
    func search(_ query: String) async throws -> [WeatherPlace] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return [] }
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        parts.queryItems = [.init(name: "name", value: value), .init(name: "count", value: "6"), .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        guard let url = parts.url else { throw WeatherDataError.invalidLocation }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw WeatherDataError.badResponse }
        struct Result: Decodable { let results: [WeatherPlace]? }
        return try JSONDecoder().decode(Result.self, from: data).results?.filter(\.valid) ?? []
    }
    func select(_ next: WeatherPlace) {
        guard next.valid else { return }
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        isLoading = false
        place = next
        snapshot = nil
        error = nil
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: "weatherPlace") }
        refresh(force: true)
    }
    func stop() { refreshTask?.cancel(); session.invalidateAndCancel() }
}
