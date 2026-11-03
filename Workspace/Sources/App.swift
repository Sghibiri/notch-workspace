// Notch Workspace · local Boring Notch derivative, modified 2026-11-02.
// SPDX-License-Identifier: GPL-3.0
import AppKit
import Carbon
import Combine
import SwiftUI

final class WorkspacePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class WorkspaceDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: WorkspacePanel!
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private var weatherWindow: WeatherWindowController?
    private var hoverTask: Task<Void, Never>?
    private var suppressHoverUntilExit = false
    private var lastKeyboardToggle = Date.distantPast
    private var changingFrame = false
    private var geometry: PanelGeometry!
    private var hotkey: EventHotKeyRef?
    private var hotkeyHandler: EventHandlerRef?
    private var localKeyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private let model: WorkspaceModel

    init(preview: Bool = false) {
        let temporary = preview ? FileManager.default.temporaryDirectory.appendingPathComponent("NotchWorkspace-Preview-\(UUID().uuidString)") : nil
        let defaults = preview ? UserDefaults(suiteName: "NotchWorkspace.Preview")! : .standard
        model = WorkspaceModel(preview: preview, storageDirectory: temporary, defaults: defaults)
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.requestToggle = { [weak self] in self?.setExpanded(!(self?.model.expanded ?? false), activate: true) }
        model.requestExpand = { [weak self] tab in self?.model.tab = tab; self?.setExpanded(true) }
        model.pointerChanged = { [weak self] inside in self?.pointerChanged(inside) }
        model.requestWeatherWindow = { [weak self] in self?.openWeather() }
        model.requestLayoutUpdate = { [weak self] in self?.reanchorPanel() }
        model.requestPreferences = { [weak self] in self?.openPreferences() }
        setupPanel()
        setupMenu()
        registerHotkey()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScreen() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.pomodoro.reconcileAfterWake() }
        }
        if model.preview { model.pinned = true; setExpanded(true, activate: true) }
        if !UserDefaults.standard.bool(forKey: "hasLaunchedWorkspace"), !model.preview {
            UserDefaults.standard.set(true, forKey: "hasLaunchedWorkspace")
            setExpanded(true)
        }
    }
    private func setupPanel() {
        panel = WorkspacePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hosting = NSHostingView(rootView: WorkspaceView(model: model, music: model.music))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        updateScreen()
        panel.orderFrontRegardless()
    }
    private func updateScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        var cameraWidth: CGFloat = 186
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(100, right.minX - left.maxX)
        }
        geometry = PanelGeometry(screenFrame: screen.frame, cameraWidth: cameraWidth, cameraHeight: max(30, screen.safeAreaInsets.top))
        model.cameraWidth = cameraWidth
        model.cameraHeight = geometry.cameraHeight
        panel?.setFrame(geometry.frame(expanded: model.expanded, showsTimer: model.pomodoro.active), display: true)
    }
    private func pointerChanged(_ inside: Bool) {
        hoverTask?.cancel()
        if !inside { suppressHoverUntilExit = false }
        if inside && suppressHoverUntilExit { return }
        guard panel != nil, geometry != nil else { return }
        guard inside ? !model.expanded : model.expanded else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(inside ? 180 : 750))
            guard !Task.isCancelled, let self else { return }
            if !inside {
                guard !self.model.pinned, !self.model.showActionEditor,
                      self.panel.attachedSheet == nil, NSApp.modalWindow == nil,
                      !NSApp.windows.contains(where: { $0 is NSOpenPanel && $0.isVisible }) else { return }
            }
            self.setExpanded(inside)
        }
    }
    private func setExpanded(_ expanded: Bool, activate: Bool = false) {
        guard panel != nil, geometry != nil else { return }
        let frame = geometry.frame(expanded: expanded, showsTimer: model.pomodoro.active)
        changingFrame = true
        if !expanded { panel.makeFirstResponder(nil); panel.resignKey() }
        if model.reduceMotion {
            model.expanded = expanded
            panel.setFrame(frame, display: true)
            changingFrame = false
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.87)) { model.expanded = expanded }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.23
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self] in
                Task { @MainActor in self?.changingFrame = false; self?.reanchorPanel() }
            })
        }
        if expanded {
            panel.orderFrontRegardless()
            if activate { NSApp.activate(ignoringOtherApps: true); panel.makeKey() }
        }
    }
    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { reanchorPanel() }
    }
    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { reanchorPanel() }
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === preferencesWindow {
            window.contentView = nil
            preferencesWindow = nil
        }
    }
    private func reanchorPanel() {
        guard !changingFrame, let panel, let geometry else { return }
        let expected = geometry.frame(expanded: model.expanded, showsTimer: model.pomodoro.active)
        guard !NSEqualRects(panel.frame, expected) else { return }
        changingFrame = true
        panel.setFrame(expected, display: true)
        changingFrame = false
    }
    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Notch Workspace")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Workspace    ⌃⌥Space", action: #selector(togglePanel), keyEquivalent: "")
        for tab in WorkspaceTab.allCases {
            let item = NSMenuItem(title: tab.title, action: #selector(openTab(_:)), keyEquivalent: "")
            item.representedObject = tab.rawValue
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Notch Workspace", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.target == nil { item.target = self }
        statusItem.menu = menu
        let appMenu = NSMenu(title: "Notch Workspace")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(updateItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Notch Workspace", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        let rootMenu = NSMenu()
        let rootItem = NSMenuItem(title: "Notch Workspace", action: nil, keyEquivalent: "")
        rootItem.submenu = appMenu
        rootMenu.addItem(rootItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        rootMenu.addItem(fileItem)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            if title == "Cut" { editMenu.addItem(.separator()) }
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        rootMenu.addItem(editItem)
        NSApp.mainMenu = rootMenu
    }
    @objc private func togglePanel() {
        // Carbon and an app-targeted synthetic key event can both be delivered.
        // Coalesce them, and keep hover from immediately undoing a close.
        let now = Date()
        guard now.timeIntervalSince(lastKeyboardToggle) > 0.3 else { return }
        lastKeyboardToggle = now
        if model.expanded { suppressHoverUntilExit = true }
        setExpanded(!model.expanded, activate: true)
    }
    @objc private func openTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = WorkspaceTab(rawValue: raw) else { return }
        model.tab = tab
        setExpanded(true, activate: true)
    }
    private func openWeather() {
        if weatherWindow == nil { weatherWindow = WeatherWindowController(model: model) }
        suppressHoverUntilExit = true
        setExpanded(false)
        weatherWindow?.open()
    }
    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let controller = NSHostingController(rootView: PreferencesView(model: model, clipboard: model.clipboard))
            let window = NSWindow(contentViewController: controller)
            window.title = "Notch Workspace Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func checkForUpdates() { openPreferences(); model.updates.check() }
    @objc private func quit() { NSApp.terminate(nil) }
    private func registerHotkey() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Space), event.modifierFlags.contains(.control), event.modifierFlags.contains(.option), !event.modifierFlags.contains(.command) {
                self?.togglePanel()
                return nil
            }
            return event
        }
        let id = EventHotKeyID(signature: OSType(0x4E57534B), id: 1)
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<WorkspaceDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.togglePanel() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &hotkeyHandler)
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotkey)
        if result != noErr { model.notify("⌃⌥Space is in use. Open Workspace from its menu bar icon.") }
    }
    func applicationWillTerminate(_ notification: Notification) {
        hoverTask?.cancel()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let hotkeyHandler { RemoveEventHandler(hotkeyHandler) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        model.stop()
        weatherWindow?.close()
    }
}

@main
struct NotchWorkspaceMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { exit(WorkspaceTests.run()) }
        if CommandLine.arguments.contains("--weather-check") {
            Task {
                do {
                    let forecast = try await WeatherService.fetch(place: .estoril)
                    print("Weather live check: \(forecast.place.name), \(forecast.hours.count) hours, \(forecast.days.count) days, time zone \(forecast.timezone)")
                    exit(0)
                } catch { print("Weather live check failed: \(error)"); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        let app = NSApplication.shared
        let delegate = WorkspaceDelegate(preview: CommandLine.arguments.contains("--preview"))
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
