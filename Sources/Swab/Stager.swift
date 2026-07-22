import AppKit
import ApplicationServices
import Combine
import Foundation

/// The heart of Swab: snapshots current state, runs the enabled staging steps
/// in order, and restores them all in reverse. The snapshot is written to disk
/// BEFORE anything is touched, so a crash mid-session can still be undone on
/// the next launch.
@MainActor
final class Stager: ObservableObject {
    static let shared = Stager()

    // MARK: Step configuration (persisted in UserDefaults)

    @Published var hideIcons: Bool {
        didSet { defaults.set(hideIcons, forKey: "step.hideIcons") }
    }
    @Published var useBackdrop: Bool {
        didSet { defaults.set(useBackdrop, forKey: "step.backdrop") }
    }
    @Published var backdrop: BackdropConfig {
        didSet {
            store(backdrop, forKey: "backdrop.config")
            // Live-swap while staged, so editing the look is instant.
            if isStaged, backdropController.isShowing, backdrop.isRenderable {
                backdropController.show(config: backdrop)
            }
        }
    }
    @Published var changeResolution: Bool {
        didSet { defaults.set(changeResolution, forKey: "step.resolution") }
    }
    /// displayID (stringified) → target ioDisplayModeID. Displays absent from
    /// the map are left alone.
    @Published var displayTargets: [String: Int32] {
        didSet { store(displayTargets, forKey: "resolution.targets") }
    }
    @Published var placeWindow: Bool {
        didSet { defaults.set(placeWindow, forKey: "step.placeWindow") }
    }
    @Published var targetAppPid: pid_t? {  // deliberately not persisted; pids churn
        didSet { if !isApplyingPreset { recallPlacementForTargetApp() } }
    }
    @Published var placement: PlacementPreset {
        didSet {
            defaults.set(placement.rawValue, forKey: "placement.preset")
            rememberPlacementForTargetApp()
        }
    }

    @Published var pairFocus: Bool {
        didSet { defaults.set(pairFocus, forKey: "step.focus") }
    }
    @Published var focusOnShortcut: String {
        didSet { defaults.set(focusOnShortcut, forKey: "focus.on") }
    }
    @Published var focusOffShortcut: String {
        didSet { defaults.set(focusOffShortcut, forKey: "focus.off") }
    }

    @Published var autoRestore: Bool {
        didSet {
            defaults.set(autoRestore, forKey: "step.autoRestore")
            isStaged ? startCountdown() : stopCountdown()
        }
    }
    @Published var autoRestoreMinutes: Int {
        didSet { defaults.set(autoRestoreMinutes, forKey: "autoRestore.minutes") }
    }

    @Published var showCursorInCaptures: Bool {
        didSet { defaults.set(showCursorInCaptures, forKey: "capture.showCursor") }
    }
    @Published var highlightClicks: Bool {
        didSet {
            defaults.set(highlightClicks, forKey: "capture.highlightClicks")
            // Toggling mid-session takes effect immediately.
            if isStaged {
                highlightClicks ? clickHighlighter.start() : clickHighlighter.stop()
            }
        }
    }

    @Published var hotkeyEnabled: Bool {
        didSet {
            defaults.set(hotkeyEnabled, forKey: "hotkey.enabled")
            applyHotkey()
        }
    }
    @Published var hotkeyBinding: HotkeyBinding {
        didSet {
            store(hotkeyBinding, forKey: "hotkey.binding")
            applyHotkey()
        }
    }

    // MARK: Live state

    @Published private(set) var isStaged = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var runningApps: [AppChoice] = []
    @Published private(set) var axTrusted = false
    @Published private(set) var focusShortcuts: [String] = []
    @Published private(set) var hotkeyConflict = false
    /// Seconds until auto-restore fires, or nil when no countdown is running.
    @Published private(set) var secondsRemaining: Int?

    let presets = PresetStore()
    let capture = Capture()

    /// Lets the AppDelegate keep the status-bar menu in sync without KVO or
    /// Combine plumbing.
    var onStateChange: (() -> Void)?

    private var snapshot: Snapshot?
    private let backdropController = BackdropController()
    private let clickHighlighter = ClickHighlighter()
    private let defaults = UserDefaults.standard
    private var countdownTimer: Timer?
    /// Set while `apply(_:)` is writing a preset in, so the per-app frame
    /// memory doesn't fight the preset for control of `placement`.
    private var isApplyingPreset = false

    private init() {
        defaults.register(defaults: [
            "step.hideIcons": true,
            "step.backdrop": true,
            "step.resolution": false,
            "step.placeWindow": false,
            "step.focus": false,
            "step.autoRestore": false,
            "autoRestore.minutes": 10,
            "placement.preset": PlacementPreset.centered16x10.rawValue,
            "capture.showCursor": false,
            "capture.highlightClicks": false,
            "hotkey.enabled": false,
        ])
        hideIcons = defaults.bool(forKey: "step.hideIcons")
        useBackdrop = defaults.bool(forKey: "step.backdrop")
        backdrop = Stager.load(BackdropConfig.self, forKey: "backdrop.config",
                               from: defaults) ?? BackdropConfig()
        changeResolution = defaults.bool(forKey: "step.resolution")
        displayTargets = Stager.load([String: Int32].self, forKey: "resolution.targets",
                                     from: defaults) ?? [:]
        placeWindow = defaults.bool(forKey: "step.placeWindow")
        placement = PlacementPreset(rawValue: defaults.string(forKey: "placement.preset") ?? "")
            ?? .centered16x10
        pairFocus = defaults.bool(forKey: "step.focus")
        focusOnShortcut = defaults.string(forKey: "focus.on") ?? ""
        focusOffShortcut = defaults.string(forKey: "focus.off") ?? ""
        autoRestore = defaults.bool(forKey: "step.autoRestore")
        autoRestoreMinutes = max(1, defaults.integer(forKey: "autoRestore.minutes"))
        showCursorInCaptures = defaults.bool(forKey: "capture.showCursor")
        highlightClicks = defaults.bool(forKey: "capture.highlightClicks")
        hotkeyEnabled = defaults.bool(forKey: "hotkey.enabled")
        hotkeyBinding = Stager.load(HotkeyBinding.self, forKey: "hotkey.binding",
                                    from: defaults) ?? .defaultToggle

        refresh()
        applyHotkey()
    }

    // MARK: Small persistence helpers

    private func store<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String,
                                           from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: Refresh pickers / permission state

    func refresh() {
        displays = Resolution.displays()
        // Drop targets for displays that are gone, or modes they no longer offer.
        displayTargets = displayTargets.filter { key, modeID in
            guard let display = displays.first(where: { String($0.id) == key })
            else { return false }
            return display.modes.contains { $0.id == modeID }
        }
        runningApps = WindowPlacer.regularApps()
        if let pid = targetAppPid, !runningApps.contains(where: { $0.pid == pid }) {
            targetAppPid = nil
        }
        axTrusted = WindowPlacer.isTrusted
    }

    func refreshFocusShortcuts() {
        focusShortcuts = FocusMode.availableShortcuts()
    }

    func requestAccessibility() {
        WindowPlacer.requestTrust()
        axTrusted = WindowPlacer.isTrusted
    }

    // MARK: Hotkey

    private func applyHotkey() {
        guard hotkeyEnabled else {
            HotkeyCenter.shared.unregister(slot: "toggle")
            hotkeyConflict = false
            return
        }
        let ok = HotkeyCenter.shared.register(hotkeyBinding, slot: "toggle") { [weak self] in
            self?.toggle()
        }
        // Registration fails when another app already owns the combination.
        hotkeyConflict = !ok
    }

    /// What the hotkey, the menu-bar item and the CLI all call.
    func toggle() {
        isStaged ? restore() : stage()
    }

    // MARK: Presets

    /// The current configuration, ready to be saved under a name.
    func currentPreset(named name: String) -> StagePreset {
        StagePreset(name: name,
                    hideIcons: hideIcons,
                    useBackdrop: useBackdrop,
                    backdrop: backdrop,
                    changeResolution: changeResolution,
                    displayTargets: displayTargets,
                    placeWindow: placeWindow,
                    placement: placement,
                    targetBundleID: targetAppBundleID,
                    pairFocus: pairFocus,
                    autoRestore: autoRestore,
                    autoRestoreMinutes: autoRestoreMinutes,
                    showCursorInCaptures: showCursorInCaptures,
                    highlightClicks: highlightClicks)
    }

    func saveCurrentAsPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets.save(currentPreset(named: trimmed))
        statusMessage = "Saved preset “\(trimmed)”."
    }

    /// Loads a preset into the current configuration. Deliberately does NOT
    /// stage — you can review what you're about to do first.
    func apply(_ preset: StagePreset) {
        // Choosing the app would otherwise recall that app's remembered frame
        // and quietly overrule the placement the preset actually saved.
        isApplyingPreset = true
        defer { isApplyingPreset = false }

        hideIcons = preset.hideIcons
        useBackdrop = preset.useBackdrop
        backdrop = preset.backdrop
        changeResolution = preset.changeResolution
        displayTargets = preset.displayTargets
        placeWindow = preset.placeWindow
        placement = preset.placement
        pairFocus = preset.pairFocus
        autoRestore = preset.autoRestore
        autoRestoreMinutes = preset.autoRestoreMinutes
        showCursorInCaptures = preset.showCursorInCaptures
        highlightClicks = preset.highlightClicks

        // Re-bind the saved app by bundle ID, since the pid will have changed.
        if let bundleID = preset.targetBundleID,
           let match = runningApps.first(where: { $0.bundleID == bundleID }) {
            targetAppPid = match.pid
        } else {
            targetAppPid = nil
        }
        refresh()
        statusMessage = "Loaded preset “\(preset.name)”."
        onStateChange?()
    }

    func applyPreset(named name: String) -> Bool {
        guard let preset = presets.preset(named: name) else { return false }
        apply(preset)
        return true
    }

    private var targetAppBundleID: String? {
        guard let pid = targetAppPid else { return nil }
        return runningApps.first(where: { $0.pid == pid })?.bundleID
    }

    /// Feature: per-app window memory. Selecting an app recalls the frame you
    /// last used for it.
    private func recallPlacementForTargetApp() {
        guard let bundleID = targetAppBundleID,
              let remembered = presets.placement(for: bundleID),
              remembered != placement
        else { return }
        placement = remembered
    }

    private func rememberPlacementForTargetApp() {
        guard let bundleID = targetAppBundleID else { return }
        presets.rememberPlacement(placement, for: bundleID)
    }

    // MARK: Countdown

    private func startCountdown() {
        stopCountdown()
        guard autoRestore else { return }
        secondsRemaining = max(1, autoRestoreMinutes) * 60
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        secondsRemaining = nil
    }

    private func tick() {
        guard let remaining = secondsRemaining else { return }
        if remaining <= 1 {
            stopCountdown()
            restore()
            statusMessage = "Auto-restored after \(autoRestoreMinutes) minute\(autoRestoreMinutes == 1 ? "" : "s")."
        } else {
            secondsRemaining = remaining - 1
        }
    }

    /// Adds time without restarting the whole countdown.
    func extendCountdown(byMinutes minutes: Int) {
        guard let remaining = secondsRemaining else { return }
        secondsRemaining = remaining + minutes * 60
    }

    var countdownLabel: String? {
        guard let remaining = secondsRemaining else { return nil }
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    // MARK: Stage

    func stage() {
        guard !isStaged else { return }
        refresh()

        var snap = Snapshot(takenAt: Date())
        var notes: [String] = []

        // 1. Record everything we are about to change.
        if hideIcons {
            let prior = DesktopIcons.readCreateDesktop()
            snap.finder = .init(keyWasAbsent: prior == nil,
                                createDesktop: prior ?? true)
        }
        if useBackdrop {
            if backdrop.isRenderable {
                snap.backdropShown = true
            } else {
                notes.append("Backdrop skipped: the chosen image is missing.")
            }
        }

        var resolutionTargets: [(display: CGDirectDisplayID, modeID: Int32)] = []
        if changeResolution {
            if displayTargets.isEmpty {
                notes.append("No target resolution chosen — skipped.")
            }
            for display in displays {
                guard let target = displayTargets[String(display.id)],
                      let current = display.currentModeID,
                      current != target
                else { continue }
                snap.displays.append(.init(displayID: display.id, modeID: current))
                resolutionTargets.append((display: display.id, modeID: target))
            }
        }

        if placeWindow {
            if !axTrusted {
                notes.append("Window placement skipped: Swab needs Accessibility access.")
            } else if let pid = targetAppPid {
                if let window = WindowPlacer.frontWindow(of: pid),
                   let frame = WindowPlacer.frame(of: window) {
                    let app = NSRunningApplication(processIdentifier: pid)
                    snap.window = .init(pid: pid,
                                        bundleID: app?.bundleIdentifier,
                                        appName: app?.localizedName,
                                        x: frame.minX, y: frame.minY,
                                        w: frame.width, h: frame.height)
                } else {
                    notes.append("Couldn't find a window for the chosen app.")
                }
            } else {
                notes.append("No app chosen for window placement — skipped.")
            }
        }

        if pairFocus {
            let on = focusOnShortcut.trimmingCharacters(in: .whitespaces)
            let off = focusOffShortcut.trimmingCharacters(in: .whitespaces)
            if !FocusMode.isAvailable {
                notes.append("Focus pairing skipped: the Shortcuts CLI isn't available.")
            } else if on.isEmpty || off.isEmpty {
                notes.append("Focus pairing skipped: pick both an on and an off shortcut.")
            } else {
                snap.focus = .init(onShortcut: on, offShortcut: off)
            }
        }

        snap.clickHighlightShown = highlightClicks

        // 2. Persist the snapshot BEFORE mutating anything.
        Storage.saveSnapshot(snap)
        snapshot = snap

        // 3. Run the steps, in order.
        if snap.finder != nil {
            DesktopIcons.hideIcons()
        }
        if snap.backdropShown {
            backdropController.show(config: backdrop)
        }
        if !resolutionTargets.isEmpty {
            let refused = Resolution.applyAll(resolutionTargets)
            if !refused.isEmpty {
                let names = refused.compactMap { id in
                    displays.first(where: { $0.id == id })?.name
                }
                notes.append("Refused that resolution: \(names.joined(separator: ", ")).")
            }
        }
        if let windowSnap = snap.window,
           let window = WindowPlacer.frontWindow(of: windowSnap.pid),
           let rect = placement.axRect() {
            if !WindowPlacer.setFrame(rect, of: window) {
                notes.append("The app didn't accept the window frame.")
            }
        }
        if let focusSnap = snap.focus {
            if !FocusMode.run(focusSnap.onShortcut) {
                notes.append("The shortcut “\(focusSnap.onShortcut)” didn't run.")
            }
        }
        if snap.clickHighlightShown {
            clickHighlighter.start()
        }

        isStaged = true
        if autoRestore { startCountdown() }

        statusMessage = notes.isEmpty
            ? "Deck swabbed. Restore puts everything back."
            : notes.joined(separator: " ")
        onStateChange?()
    }

    // MARK: Restore

    func restore() {
        guard let snap = snapshot ?? Storage.loadSnapshot() else {
            statusMessage = "Nothing to restore."
            return
        }
        var notes: [String] = []

        stopCountdown()
        // A recording started while staged would otherwise keep running with
        // nothing left to record.
        if capture.isRecording { capture.stopRecording() }

        // Undo in reverse order of staging.
        clickHighlighter.stop()

        if let focusSnap = snap.focus {
            if !FocusMode.run(focusSnap.offShortcut) {
                notes.append("The shortcut “\(focusSnap.offShortcut)” didn't run.")
            }
        }
        if let windowSnap = snap.window {
            if WindowPlacer.isTrusted,
               let pid = resolvePid(for: windowSnap),
               let window = WindowPlacer.frontWindow(of: pid) {
                let rect = CGRect(x: windowSnap.x, y: windowSnap.y,
                                  width: windowSnap.w, height: windowSnap.h)
                WindowPlacer.setFrame(rect, of: window)
            } else {
                let name = windowSnap.appName ?? "the app"
                notes.append("Couldn't restore \(name)'s window frame.")
            }
        }
        if !snap.displays.isEmpty {
            let refused = Resolution.applyAll(
                snap.displays.map { (display: $0.displayID, modeID: $0.modeID) })
            if !refused.isEmpty {
                notes.append("Couldn't restore the original resolution on \(refused.count) display(s).")
            }
        }
        backdropController.hide()
        if let finderSnap = snap.finder {
            DesktopIcons.restore(finderSnap)
        }

        Storage.deleteSnapshot()
        snapshot = nil
        isStaged = false
        statusMessage = notes.isEmpty
            ? "Everything back where it was."
            : notes.joined(separator: " ")
        refresh()
        onStateChange?()
    }

    /// Best-effort restore for app quit — no UI updates needed.
    func restoreIfNeeded() {
        if isStaged { restore() }
    }

    // MARK: Crash recovery

    /// Called at launch. If a snapshot survives on disk, a previous session
    /// staged and never restored (crash, force-quit) — arm Restore with it.
    func adoptPersistedSnapshotIfAny() {
        guard snapshot == nil, let saved = Storage.loadSnapshot() else { return }
        snapshot = saved
        isStaged = true
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        statusMessage = "Found an unrestored setup from \(formatter.string(from: saved.takenAt)). Restore puts it back."
        onStateChange?()
    }

    private func resolvePid(for snap: Snapshot.WindowSnapshot) -> pid_t? {
        if let app = NSRunningApplication(processIdentifier: snap.pid),
           !app.isTerminated {
            return snap.pid
        }
        if let bundleID = snap.bundleID,
           let app = NSWorkspace.shared.runningApplications
               .first(where: { $0.bundleIdentifier == bundleID }) {
            return app.processIdentifier
        }
        return nil
    }
}
