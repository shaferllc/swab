import AppKit
import Combine
import SwiftUI

@main
struct SwabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var stageMenuItem: NSMenuItem?
    private var restoreMenuItem: NSMenuItem?
    private var presetsMenuItem: NSMenuItem?
    private var screenshotMenuItem: NSMenuItem?
    private var recordMenuItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []

    /// Follow the system light/dark setting. Accessory apps launched outside
    /// a normal session don't always inherit it, which strands windows in the
    /// wrong appearance.
    static func syncAppearance() {
        let style = UserDefaults.standard
            .persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String
        let isDark = style?.lowercased().contains("dark") ?? false
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppDelegate.syncAppearance()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppDelegate.syncAppearance() }
        }

        setupStatusItem()
        Stager.shared.onStateChange = { [weak self] in
            self?.updateMenuState()
        }
        // The countdown and recording state change without a stage/restore, so
        // keep the menu honest about both.
        Stager.shared.$secondsRemaining
            .sink { [weak self] _ in self?.updateMenuState() }
            .store(in: &cancellables)
        Stager.shared.capture.$isRecording
            .sink { [weak self] _ in self?.updateMenuState() }
            .store(in: &cancellables)
        Stager.shared.presets.$presets
            .sink { [weak self] _ in self?.rebuildPresetsMenu() }
            .store(in: &cancellables)

        // A leftover snapshot means the last session never restored (crash or
        // force-quit) — arm Restore with it.
        Stager.shared.adoptPersistedSnapshotIfAny()
        updateMenuState()
        rebuildPresetsMenu()
        showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the desk staged: quit always puts things back.
        Stager.shared.restoreIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// `swab://…` from the CLI shim.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            CommandLineBridge.handle(url)
        }
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles",
                                     accessibilityDescription: "Swab")

        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "Open Swab",
                              action: #selector(openWindow), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let stage = NSMenuItem(title: "Stage",
                               action: #selector(stageNow), keyEquivalent: "s")
        stage.target = self
        menu.addItem(stage)
        stageMenuItem = stage

        let restore = NSMenuItem(title: "Restore",
                                 action: #selector(restoreNow), keyEquivalent: "r")
        restore.target = self
        menu.addItem(restore)
        restoreMenuItem = restore

        let presets = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        presets.submenu = NSMenu()
        menu.addItem(presets)
        presetsMenuItem = presets

        menu.addItem(.separator())

        let shot = NSMenuItem(title: "Take Screenshot",
                              action: #selector(screenshotNow), keyEquivalent: "")
        shot.target = self
        menu.addItem(shot)
        screenshotMenuItem = shot

        let record = NSMenuItem(title: "Start Recording",
                                action: #selector(toggleRecording), keyEquivalent: "")
        record.target = self
        menu.addItem(record)
        recordMenuItem = record

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Swab",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func rebuildPresetsMenu() {
        guard let submenu = presetsMenuItem?.submenu else { return }
        submenu.removeAllItems()
        let presets = Stager.shared.presets.presets
        guard !presets.isEmpty else {
            let empty = NSMenuItem(title: "No presets saved", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            presetsMenuItem?.isEnabled = true
            return
        }
        for preset in presets {
            let item = NSMenuItem(title: preset.name,
                                  action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.name
            submenu.addItem(item)
        }
    }

    private func updateMenuState() {
        let stager = Stager.shared
        let staged = stager.isStaged
        stageMenuItem?.isEnabled = !staged
        restoreMenuItem?.isEnabled = staged
        restoreMenuItem?.title = stager.countdownLabel.map { "Restore  (\($0))" } ?? "Restore"

        screenshotMenuItem?.isEnabled = true
        recordMenuItem?.title = stager.capture.isRecording
            ? "Stop Recording" : "Start Recording"

        statusItem?.button?.image = NSImage(
            systemSymbolName: staged ? "sparkles.rectangle.stack.fill" : "sparkles",
            accessibilityDescription: "Swab")
        // Show the countdown right in the menu bar, where it's visible while
        // you're recording something else.
        statusItem?.button?.title = stager.countdownLabel.map { " \($0)" } ?? ""
    }

    // MARK: Window

    private func showWindow() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: StagingView().environmentObject(Stager.shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Swab"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Actions

    @objc private func openWindow() { showWindow() }
    @objc private func stageNow() { Stager.shared.stage() }
    @objc private func restoreNow() { Stager.shared.restore() }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        _ = Stager.shared.applyPreset(named: name)
    }

    @objc private func screenshotNow() {
        let stager = Stager.shared
        stager.capture.screenshot(showCursor: stager.showCursorInCaptures)
    }

    @objc private func toggleRecording() {
        let stager = Stager.shared
        if stager.capture.isRecording {
            stager.capture.stopRecording()
        } else {
            stager.capture.startRecording(showCursor: stager.showCursorInCaptures)
        }
    }
}
