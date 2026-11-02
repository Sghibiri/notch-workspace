// SPDX-License-Identifier: GPL-3.0
import AppKit
import Combine
import SwiftUI

@MainActor
final class WeatherWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    @Published private(set) var visible = false
    @Published private(set) var animationActive = false
    private weak var model: WorkspaceModel?
    init(model: WorkspaceModel) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Weather"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 820, height: 650)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1)
        window.collectionBehavior = [.fullScreenPrimary]
        super.init(window: window)
        self.model = model
        window.delegate = self
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivityChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivityChanged), name: NSApplication.didResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    func open() {
        if window?.contentViewController == nil, let model {
            let frame = window?.frame
            window?.contentViewController = NSHostingController(rootView: WeatherWindowView(model: model, weather: model.weather, controller: self))
            if let frame { window?.setFrame(frame, display: false) }
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        updateVisibility()
    }
    func toggleFullScreen() { window?.toggleFullScreen(nil) }
    func dismiss() {
        if window?.styleMask.contains(.fullScreen) == true { toggleFullScreen() }
        else { close() }
    }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    func windowDidBecomeKey(_ notification: Notification) { updateVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { updateVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }
    func windowWillClose(_ notification: Notification) {
        visible = false
        animationActive = false
        window?.contentViewController = nil
        window?.contentView = nil
    }
    @objc private func applicationActivityChanged() { updateVisibility() }
    private func updateVisibility() {
        let next = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
        if visible != next { visible = next }
        let animate = next && NSApp.isActive
        if animationActive != animate { animationActive = animate }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
