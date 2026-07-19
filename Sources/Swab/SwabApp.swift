import AppKit
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
        // A leftover snapshot means the last session never restored (crash or
        // force-quit) — arm Restore with it.
        Stager.shared.adoptPersistedSnapshotIfAny()
        updateMenuState()
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

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Swab",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func updateMenuState() {
        let staged = Stager.shared.isStaged
        stageMenuItem?.isEnabled = !staged
        restoreMenuItem?.isEnabled = staged
        statusItem?.button?.image = NSImage(
            systemSymbolName: staged ? "sparkles.rectangle.stack.fill" : "sparkles",
            accessibilityDescription: "Swab")
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
}
