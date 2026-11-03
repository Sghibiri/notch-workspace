// SPDX-License-Identifier: GPL-3.0
import SwiftUI

enum WorkspaceTheme {
    static let accent = Color(red: 0.73, green: 0.65, blue: 1)
    static let mint = Color(red: 0.62, green: 0.89, blue: 0.78)
    static let dim = Color.white.opacity(0.58)
    static let card = Color.white.opacity(0.065)
    static let line = Color.white.opacity(0.10)
    static let blue = Color(red: 0.63, green: 0.79, blue: 1)
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16)
            .background(LinearGradient(colors: [WorkspaceTheme.card, Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceTheme.line))
    }
}

struct QuietButton: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .modifier(HoverFeedback(pressed: configuration.isPressed, radius: 9))
    }
}

struct HoverButton: ButtonStyle {
    var radius: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(HoverFeedback(pressed: configuration.isPressed, radius: radius))
    }
}

private struct HoverFeedback: ViewModifier {
    let pressed: Bool
    let radius: CGFloat
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(pressed ? 0.10 : hovered ? 0.045 : 0), in: RoundedRectangle(cornerRadius: radius))
            .opacity(pressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovered = $0 }
    }
}

struct EmptyCard: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
                .frame(width: 58, height: 58).background(WorkspaceTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18)).padding(.bottom, 3)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.dim).multilineTextAlignment(.center).lineSpacing(3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Artwork: View {
    let data: Data?
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.37, green: 0.31, blue: 0.61), Color(red: 0.12, green: 0.14, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "waveform").font(.system(size: size * 0.35, weight: .light)).foregroundStyle(.white.opacity(0.8))
                    Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1).frame(width: size * 0.85, height: size * 0.85).offset(x: size * 0.3, y: size * 0.25)
                }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.19))
    }
}

struct Waveform: View {
    var playing: Bool
    var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var animating: Bool { playing && !reduceMotion && !systemReduceMotion && !lowPower }
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: !animating)) { context in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<5) { index in
                    let phase = context.date.timeIntervalSinceReferenceDate * 4 + Double(index) * 1.4
                    Capsule().fill(WorkspaceTheme.accent).frame(width: 2.5, height: animating ? 5 + 11 * abs(sin(phase)) : CGFloat([5, 10, 15, 10, 5][index]))
                }
            }.frame(width: 23, height: 20)
        }.accessibilityLabel(playing ? "Music playing" : "Music paused")
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}

func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = max(0, Int(seconds))
    return String(format: "%d:%02d", value / 60, value % 60)
}
