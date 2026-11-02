// SPDX-License-Identifier: GPL-3.0
import SwiftUI

struct WeatherBackdrop: View {
    let condition: WeatherCondition
    var animate = false
    private var colors: [Color] {
        switch condition.mood {
        case .rain, .storm: return [Color(red: 0.17, green: 0.23, blue: 0.34), Color(red: 0.07, green: 0.09, blue: 0.18)]
        case .snow: return [Color(red: 0.27, green: 0.37, blue: 0.48), Color(red: 0.10, green: 0.16, blue: 0.26)]
        case .fog: return [Color(red: 0.27, green: 0.33, blue: 0.39), Color(red: 0.12, green: 0.17, blue: 0.23)]
        default: return condition.isDay ? [Color(red: 0.17, green: 0.42, blue: 0.62), Color(red: 0.08, green: 0.18, blue: 0.34)] : [Color(red: 0.12, green: 0.16, blue: 0.32), Color(red: 0.035, green: 0.05, blue: 0.12)]
        }
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in atmosphere(time: context.date.timeIntervalSinceReferenceDate) }
            } else { atmosphere(time: 0) }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
    private func atmosphere(time: Double) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let rain = condition.mood == .rain || condition.mood == .storm
            let snow = condition.mood == .snow
            if rain || snow {
                let count = snow ? 34 : 44
                for index in 0..<count {
                    let seed = Double(index)
                    let x = (seed * 83.17 + time * (snow ? 9 : 23)).truncatingRemainder(dividingBy: size.width + 80) - 40
                    let y = (seed * 97.31 + time * (snow ? 23 : 240)).truncatingRemainder(dividingBy: size.height + 80) - 40
                    let alpha = 0.10 + Double(index % 5) * 0.035
                    if snow {
                        context.fill(Path(ellipseIn: CGRect(x: x + sin(time * 0.5 + seed) * 12, y: y, width: 2 + seed.truncatingRemainder(dividingBy: 3), height: 2 + seed.truncatingRemainder(dividingBy: 3))), with: .color(.white.opacity(alpha + 0.15)))
                    } else {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x - 5, y: y + 18 + seed.truncatingRemainder(dividingBy: 12)))
                        context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 0.7)
                    }
                }
            } else if !condition.isDay {
                for index in 0..<27 {
                    let x = (Double(index) * 137.31 + 41).truncatingRemainder(dividingBy: max(1, size.width))
                    let y = (Double(index) * 73.43 + 19).truncatingRemainder(dividingBy: max(1, size.height * 0.65))
                    let alpha = 0.13 + 0.16 * abs(sin(time * 0.25 + Double(index)))
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: index % 3 == 0 ? 2 : 1, height: index % 3 == 0 ? 2 : 1)), with: .color(.white.opacity(alpha)))
                }
            }
            let glow = CGPoint(x: size.width * 0.8, y: size.height * 0.1)
            context.fill(Path(ellipseIn: CGRect(x: glow.x - size.width * 0.5, y: glow.y - size.width * 0.5, width: size.width, height: size.width)), with: .radialGradient(Gradient(colors: [(condition.isDay ? Color.orange : Color.blue).opacity(0.14), .clear]), center: glow, startRadius: 0, endRadius: size.width * 0.5))
            if condition.mood == .clouds || condition.mood == .fog || rain || snow {
                for index in 0..<4 {
                    let drift = sin(time * 0.035 + Double(index)) * size.width * 0.08
                    let rect = CGRect(x: Double(index) * size.width / 3 - size.width * 0.2 + drift, y: -100 + Double(index % 2) * 90, width: size.width * 0.7, height: size.height * 0.47)
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [.white.opacity(condition.mood == .fog ? 0.10 : 0.045), .clear]), center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: rect.width * 0.5))
                }
            }
        }
    }
}

struct WeatherQuickView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var weather: WeatherService
    var body: some View {
        ZStack {
            WeatherBackdrop(condition: weather.snapshot?.condition ?? .init(code: 0, isDay: false))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(weather.place.name, systemImage: "location.fill").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button { weather.refresh(force: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }.disabled(weather.isLoading).accessibilityLabel("Refresh weather")
                }
                if let snapshot = weather.snapshot {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(weather.unit.format(snapshot.temperature)).font(.system(size: 53, weight: .thin, design: .rounded))
                            Text(snapshot.condition.title).font(.system(size: 13, weight: .medium))
                            Text("Feels like \(weather.unit.format(snapshot.feelsLike)) · Wind \(Int(snapshot.wind.rounded())) km/h").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Image(systemName: snapshot.condition.symbol).symbolRenderingMode(.hierarchical).font(.system(size: 47, weight: .ultraLight)).foregroundStyle(.white.opacity(0.8)).padding(.trailing, 12)
                    }
                    HStack(spacing: 0) {
                        ForEach(snapshot.upcomingHours(count: 5)) { hour in
                            VStack(spacing: 6) {
                                Text(snapshot.clock(hour.time)).font(.system(size: 8)).foregroundStyle(.white.opacity(0.55))
                                Image(systemName: hour.condition.symbol).font(.system(size: 12)).frame(height: 17)
                                Text(weather.unit.format(hour.temperature)).font(.system(size: 10, weight: .medium))
                            }.frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    EmptyCard(symbol: "cloud.sun", title: weather.isLoading ? "Checking the skies…" : "Weather, within reach", detail: weather.error ?? "Your forecast will appear here.")
                }
                Spacer(minLength: 0)
                HStack {
                    Text(weather.preview ? "Sample forecast" : weather.error != nil ? "Saved forecast" : "Open-Meteo")
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Button { model.requestWeatherWindow?() } label: { Label("Open full weather", systemImage: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .medium)) }
                }
            }.padding(18)
        }.clipShape(RoundedRectangle(cornerRadius: 19)).buttonStyle(.plain)
            .task {
                while !Task.isCancelled {
                    weather.refresh()
                    do { try await Task.sleep(for: .seconds(900)) } catch { return }
                }
            }
    }
}

struct WeatherHomeBadge: View {
    @ObservedObject var weather: WeatherService
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: weather.snapshot?.condition.symbol ?? "cloud.sun")
                Text(weather.snapshot.map { weather.unit.format($0.temperature) } ?? "Weather")
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
        }.buttonStyle(.plain).help("Weather in \(weather.place.name)").accessibilityLabel("Weather in \(weather.place.name)")
            .task {
                while !Task.isCancelled {
                    weather.refresh()
                    do { try await Task.sleep(for: .seconds(900)) } catch { return }
                }
            }
    }
}

struct WeatherWindowView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var weather: WeatherService
    @ObservedObject var controller: WeatherWindowController
    @State private var choosingLocation = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var body: some View {
        ZStack {
            WeatherBackdrop(condition: weather.snapshot?.condition ?? .init(code: 0, isDay: false), animate: controller.animationActive && weather.effectsEnabled && !model.reduceMotion && !lowPower)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    toolbar
                    if let snapshot = weather.snapshot {
                        hero(snapshot)
                        hourly(snapshot)
                        HStack(alignment: .top, spacing: 16) {
                            daily(snapshot).frame(maxWidth: .infinity)
                            details(snapshot).frame(width: 246)
                        }
                    } else {
                        EmptyCard(symbol: "cloud.sun", title: weather.isLoading ? "Checking the skies…" : "Weather is taking a moment", detail: weather.error ?? "Loading your forecast.").frame(height: 380)
                    }
                    footer
                }.padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 22)
            }.accessibilityHidden(choosingLocation)
            if choosingLocation {
                Color.black.opacity(0.55).onTapGesture { choosingLocation = false }
                WeatherLocationView(weather: weather, onDone: { choosingLocation = false })
                    .padding(24).frame(width: 440).background(Color(red: 0.08, green: 0.10, blue: 0.15), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)))
                    .shadow(color: .black.opacity(0.3), radius: 30)
            }
        }.preferredColorScheme(.dark)
            .onExitCommand { if choosingLocation { choosingLocation = false } else { controller.dismiss() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
            .task(id: controller.visible) {
                guard controller.visible else { return }
                while !Task.isCancelled {
                    weather.refresh()
                    do { try await Task.sleep(for: .seconds(900)) } catch { return }
                }
            }
    }
    private var toolbar: some View {
        HStack {
            Label("WEATHER", systemImage: "cloud.sun").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Button { choosingLocation = true } label: { Label("Change city", systemImage: "location").font(.system(size: 11)) }.buttonStyle(QuietButton())
            Button { weather.unit = weather.unit == .celsius ? .fahrenheit : .celsius } label: { Text(weather.unit.label).font(.system(size: 11, weight: .medium)) }.buttonStyle(QuietButton()).accessibilityLabel("Change temperature unit")
            Button { weather.effectsEnabled.toggle() } label: { Image(systemName: weather.effectsEnabled ? "sparkles" : "moon.zzz").font(.system(size: 12)) }.buttonStyle(QuietButton()).help("Toggle weather effects").accessibilityLabel("Toggle weather effects")
            Button { controller.toggleFullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11)) }.buttonStyle(QuietButton()).help("Full screen weather").accessibilityLabel("Full screen weather")
            Button { weather.refresh(force: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12)) }.buttonStyle(QuietButton()).disabled(weather.isLoading).accessibilityLabel("Refresh forecast")
        }
    }
    private func hero(_ snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.place.name).font(.system(size: 32, weight: .medium, design: .rounded))
                Text(snapshot.place.country ?? "").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(weather.unit.format(snapshot.temperature)).font(.system(size: 89, weight: .ultraLight, design: .rounded)).monospacedDigit()
                    VStack(alignment: .leading, spacing: 7) {
                        Text(snapshot.condition.title).font(.system(size: 20, weight: .medium))
                        if let day = snapshot.days.first {
                            Text("H: \(weather.unit.format(day.high))   L: \(weather.unit.format(day.low))").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
            }
            Spacer()
            Image(systemName: snapshot.condition.symbol).symbolRenderingMode(.hierarchical).font(.system(size: 106, weight: .ultraLight)).foregroundStyle(.white.opacity(0.8)).padding(.trailing, 38)
        }.padding(.vertical, 4)
    }
    private func hourly(_ snapshot: WeatherSnapshot) -> some View {
        weatherCard {
            VStack(alignment: .leading, spacing: 14) {
                heading("NEXT 24 HOURS", symbol: "clock")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 26) {
                        ForEach(snapshot.upcomingHours(count: 24)) { hour in
                            VStack(spacing: 9) {
                                Text(snapshot.clock(hour.time)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                                Image(systemName: hour.condition.symbol).font(.system(size: 19)).frame(height: 24)
                                Text(weather.unit.format(hour.temperature)).font(.system(size: 15, weight: .medium))
                                Text(hour.precipitationChance.map { "\($0)%" } ?? "—").font(.system(size: 9)).foregroundStyle(WorkspaceTheme.mint)
                            }.frame(width: 42)
                        }
                    }
                }
            }
        }
    }
    private func daily(_ snapshot: WeatherSnapshot) -> some View {
        weatherCard {
            VStack(alignment: .leading, spacing: 12) {
                heading("7-DAY FORECAST", symbol: "calendar")
                ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { index, day in
                    HStack(spacing: 13) {
                        Text(snapshot.isToday(day.time) ? "Today" : snapshot.weekday(day.time)).frame(width: 44, alignment: .leading)
                        Image(systemName: day.condition.symbol).frame(width: 23)
                        Text(day.precipitationChance.map { "\($0)%" } ?? "—").font(.system(size: 9)).foregroundStyle(WorkspaceTheme.mint).frame(width: 32)
                        Spacer(minLength: 4)
                        Text(weather.unit.format(day.low)).foregroundStyle(.white.opacity(0.45)).frame(width: 29, alignment: .trailing)
                        GeometryReader { geometry in
                            let minimum = snapshot.days.map(\.low).min() ?? day.low
                            let maximum = snapshot.days.map(\.high).max() ?? day.high
                            let span = max(1, maximum - minimum)
                            Capsule().fill(.white.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(LinearGradient(colors: [.cyan.opacity(0.8), .yellow.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(3, (day.high - day.low) / span * geometry.size.width))
                                        .offset(x: (day.low - minimum) / span * geometry.size.width)
                                }
                        }.frame(width: 62, height: 4)
                        Text(weather.unit.format(day.high)).frame(width: 29, alignment: .trailing)
                    }.font(.system(size: 12, weight: .medium)).frame(height: 23)
                }
            }
        }
    }
    private func details(_ snapshot: WeatherSnapshot) -> some View {
        VStack(spacing: 12) {
            weatherCard {
                VStack(alignment: .leading, spacing: 12) {
                    heading("RIGHT NOW", symbol: "thermometer.medium")
                    detail("Feels like", value: weather.unit.format(snapshot.feelsLike), symbol: "thermometer.medium")
                    detail("Humidity", value: "\(snapshot.humidity)%", symbol: "humidity")
                    detail("Wind", value: "\(Int(snapshot.wind.rounded())) km/h", symbol: "wind")
                }
            }
            if let day = snapshot.days.first {
                weatherCard {
                    VStack(alignment: .leading, spacing: 12) {
                        heading("DAYLIGHT", symbol: "sun.horizon")
                        if let sunrise = day.sunrise { detail("Sunrise", value: snapshot.clock(sunrise), symbol: "sunrise") }
                        if let sunset = day.sunset { detail("Sunset", value: snapshot.clock(sunset), symbol: "sunset") }
                    }
                }
            }
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = weather.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange.opacity(0.85)) }
            HStack {
                if weather.preview { Text("SAMPLE FORECAST").font(.system(size: 9, weight: .medium)).tracking(1) }
                else if let snapshot = weather.snapshot {
                    Text("Updated \(snapshot.fetchedAt, style: .relative) ago · \(snapshot.timezone)").font(.system(size: 10))
                }
                Spacer()
                Link("Weather: Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                Text("·")
                Link("Locations: GeoNames", destination: URL(string: "https://www.geonames.org/")!)
            }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
        }
    }
    private func heading(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.white.opacity(0.45))
    }
    private func detail(_ title: String, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
        }.font(.system(size: 11))
    }
    private func weatherCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
    }
}

struct WeatherLocationView: View {
    @ObservedObject var weather: WeatherService
    let onDone: () -> Void
    @State private var query = ""
    @State private var places: [WeatherPlace] = []
    @State private var searching = false
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("Find your skies").font(.system(size: 21, weight: .semibold)); Spacer(); Button("Cancel", action: onDone).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent) }
            Text("Search a city. Your device location is never requested.").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                TextField("City, optionally followed by country", text: $query).textFieldStyle(.roundedBorder).onSubmit(search).accessibilityLabel("Search weather city")
                Button(searching ? "Searching…" : "Search", action: search).disabled(searching || query.trimmingCharacters(in: .whitespaces).count < 2)
            }
            if let message { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
            ForEach(places) { place in
                Button {
                    weather.select(place)
                    onDone()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(place.name).font(.system(size: 13, weight: .medium)); Text(place.subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent)
                    }.padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
            }
        }.onDisappear { searchTask?.cancel() }
    }
    private func search() {
        searchTask?.cancel()
        searching = true
        message = nil
        let requested = query
        searchTask = Task {
            do {
                let result = try await weather.search(requested)
                guard !Task.isCancelled else { return }
                places = result
                message = result.isEmpty ? "No cities found. Try adding a country name." : nil
            } catch { if !Task.isCancelled { message = "City search could not connect. Try again." } }
            if !Task.isCancelled { searching = false }
        }
    }
}
