// SPDX-License-Identifier: GPL-3.0
import Foundation

struct WeatherPlace: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
    let timezone: String?
    var subtitle: String { [admin1, country].compactMap { $0 }.joined(separator: ", ") }
    var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    static let estoril = WeatherPlace(id: 2268436, name: "Estoril", latitude: 38.70571, longitude: -9.39773, country: "Portugal", admin1: "Lisbon District", timezone: "Europe/Lisbon")
}

enum WeatherUnit: String, CaseIterable {
    case celsius, fahrenheit
    var label: String { self == .celsius ? "°C" : "°F" }
    func value(_ celsius: Double) -> Double { self == .celsius ? celsius : celsius * 9 / 5 + 32 }
    func format(_ celsius: Double, suffix: Bool = false) -> String {
        guard celsius.isFinite else { return "—" }
        return "\(Int(value(celsius).rounded()))\(suffix ? label : "°")"
    }
}

enum WeatherMood: String { case clear, clouds, fog, rain, snow, storm, unknown }

struct WeatherCondition {
    let code: Int
    let isDay: Bool
    var mood: WeatherMood {
        switch code {
        case 0, 1: return .clear
        case 2, 3: return .clouds
        case 45, 48: return .fog
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95, 96, 99: return .storm
        default: return .unknown
        }
    }
    var title: String {
        switch code {
        case 0: return "Clear skies"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57, 66, 67: return "Freezing rain"
        case 61, 63: return "Rain"
        case 65: return "Heavy rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorms"
        default: return "Weather unavailable"
        }
    }
    var symbol: String {
        switch mood {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .clouds: return code == 3 ? "cloud.fill" : isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .fog: return "cloud.fog.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .storm: return "cloud.bolt.rain.fill"
        case .unknown: return "cloud"
        }
    }
}

struct WeatherHour: Codable, Identifiable {
    let time: Date
    let temperature: Double
    let precipitationChance: Int?
    let code: Int
    let isDay: Bool
    var id: Date { time }
    var condition: WeatherCondition { .init(code: code, isDay: isDay) }
}

struct WeatherDay: Codable, Identifiable {
    let time: Date
    let low: Double
    let high: Double
    let code: Int
    let sunrise: Date?
    let sunset: Date?
    let precipitationChance: Int?
    let uv: Double?
    var id: Date { time }
    var condition: WeatherCondition { .init(code: code, isDay: true) }
}

struct WeatherSnapshot: Codable {
    let place: WeatherPlace
    let fetchedAt: Date
    let observedAt: Date
    let timezone: String
    let temperature: Double
    let feelsLike: Double
    let humidity: Int
    let wind: Double
    let code: Int
    let isDay: Bool
    let hours: [WeatherHour]
    let days: [WeatherDay]
    var condition: WeatherCondition { .init(code: code, isDay: isDay) }
    var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .gmt }
    func upcomingHours(at date: Date = Date(), count: Int = 12) -> [WeatherHour] {
        Array(hours.filter { $0.time >= date.addingTimeInterval(-1800) }.prefix(count))
    }
    func clock(_ date: Date) -> String {
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = timeZone
        return date.formatted(format)
    }
    func weekday(_ date: Date) -> String {
        var format = Date.FormatStyle().weekday(.abbreviated)
        format.timeZone = timeZone
        return date.formatted(format)
    }
    func isToday(_ date: Date, at now: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: now)
    }
    static func preview(at date: Date = Date()) -> Self {
        let hours = (0..<24).map { index in
            WeatherHour(time: date.addingTimeInterval(Double(index) * 3600), temperature: 17 + 3 * sin(Double(index) / 4), precipitationChance: max(0, 65 - index * 5), code: index < 4 ? 61 : 2, isDay: index > 7 && index < 18)
        }
        let days = (0..<7).map { index in
            WeatherDay(time: date.addingTimeInterval(Double(index) * 86400), low: Double(13 + index % 3), high: Double(19 + index % 4), code: [61, 2, 0, 3, 80, 1, 2][index], sunrise: date.addingTimeInterval(7 * 3600), sunset: date.addingTimeInterval(17 * 3600), precipitationChance: [65, 20, 5, 35, 70, 10, 15][index], uv: 3)
        }
        return Self(place: .estoril, fetchedAt: date, observedAt: date, timezone: "Europe/Lisbon", temperature: 17, feelsLike: 16, humidity: 78, wind: 14, code: 61, isDay: false, hours: hours, days: days)
    }
}

enum WeatherDataError: Error { case badResponse, invalidLocation, invalidForecast }

// Open-Meteo is requested with Unix timestamps and metric units. Convert display
// units locally, and format all forecasts in the location's own time zone.
struct WeatherAPIResponse: Decodable {
    struct Current: Decodable {
        let time: Double
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Int
        let wind_speed_10m: Double
        let weather_code: Int
        let is_day: Int
    }
    struct Hourly: Decodable {
        let time: [Double]
        let temperature_2m: [Double?]
        let precipitation_probability: [Int?]
        let weather_code: [Int?]
        let is_day: [Int?]
    }
    struct Daily: Decodable {
        let time: [Double]
        let temperature_2m_min: [Double?]
        let temperature_2m_max: [Double?]
        let weather_code: [Int?]
        let sunrise: [Double?]
        let sunset: [Double?]
        let precipitation_probability_max: [Int?]
        let uv_index_max: [Double?]
    }
    let timezone: String
    let current: Current
    let hourly: Hourly
    let daily: Daily
    func snapshot(place: WeatherPlace, fetchedAt: Date = Date()) throws -> WeatherSnapshot {
        guard place.valid, TimeZone(identifier: timezone) != nil, current.temperature_2m.isFinite,
              current.apparent_temperature.isFinite, current.wind_speed_10m.isFinite else { throw WeatherDataError.invalidForecast }
        func item<T>(_ values: [T], _ index: Int) -> T? { values.indices.contains(index) ? values[index] : nil }
        let hours: [WeatherHour] = hourly.time.enumerated().compactMap { index, time in
            guard let temperature = item(hourly.temperature_2m, index) ?? nil, temperature.isFinite,
                  let code = item(hourly.weather_code, index) ?? nil else { return nil }
            return WeatherHour(time: Date(timeIntervalSince1970: time), temperature: temperature, precipitationChance: item(hourly.precipitation_probability, index) ?? nil, code: code, isDay: (item(hourly.is_day, index) ?? 0) == 1)
        }
        let days: [WeatherDay] = daily.time.enumerated().compactMap { index, time in
            guard let low = item(daily.temperature_2m_min, index) ?? nil, let high = item(daily.temperature_2m_max, index) ?? nil,
                  let code = item(daily.weather_code, index) ?? nil, low.isFinite, high.isFinite, high >= low else { return nil }
            let sunrise = (item(daily.sunrise, index) ?? nil).map { Date(timeIntervalSince1970: $0) }
            let sunset = (item(daily.sunset, index) ?? nil).map { Date(timeIntervalSince1970: $0) }
            return WeatherDay(time: Date(timeIntervalSince1970: time), low: low, high: high, code: code, sunrise: sunrise, sunset: sunset, precipitationChance: item(daily.precipitation_probability_max, index) ?? nil, uv: item(daily.uv_index_max, index) ?? nil)
        }
        guard !hours.isEmpty, !days.isEmpty else { throw WeatherDataError.invalidForecast }
        return WeatherSnapshot(place: place, fetchedAt: fetchedAt, observedAt: Date(timeIntervalSince1970: current.time), timezone: timezone, temperature: current.temperature_2m, feelsLike: current.apparent_temperature, humidity: min(100, max(0, current.relative_humidity_2m)), wind: max(0, current.wind_speed_10m), code: current.weather_code, isDay: current.is_day == 1, hours: hours, days: days)
    }
}
