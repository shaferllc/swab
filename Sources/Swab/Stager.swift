import AppKit
import ApplicationServices
import Combine

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
    @Published var backdropStyle: BackdropStyle {
        didSet {
            defaults.set(backdropStyle.rawValue, forKey: "backdrop.style")
            // Live-swap the color while staged, so picking a preset is instant.
            if isStaged, backdrop.isShowing { backdrop.show(style: backdropStyle) }
        }
    }
    @Published var changeResolution: Bool {
        didSet { defaults.set(changeResolution, forKey: "step.resolution") }
    }
    @Published var targetModeID: Int32? {
        didSet { defaults.set(Int(targetModeID ?? 0), forKey: "resolution.modeID") }
    }
    @Published var placeWindow: Bool {
        didSet { defaults.set(placeWindow, forKey: "step.placeWindow") }
    }
    @Published var targetAppPid: pid_t?   // deliberately not persisted; pids churn
    @Published var placement: PlacementPreset {
        didSet { defaults.set(placement.rawValue, forKey: "placement.preset") }
    }

    // MARK: Live state

    @Published private(set) var isStaged = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var modeChoices: [DisplayModeChoice] = []
    @Published private(set) var currentModeID: Int32?
    @Published private(set) var runningApps: [AppChoice] = []
    @Published private(set) var axTrusted = false

    /// Lets the AppDelegate keep the status-bar menu in sync without KVO or
    /// Combine plumbing.
    var onStateChange: (() -> Void)?

    private var snapshot: Snapshot?
    private let backdrop = BackdropController()
    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "step.hideIcons": true,
            "step.backdrop": true,
            "backdrop.style": BackdropStyle.graphite.rawValue,
            "step.resolution": false,
            "step.placeWindow": false,
            "placement.preset": PlacementPreset.centered16x10.rawValue,
        ])
        hideIcons = defaults.bool(forKey: "step.hideIcons")
        useBackdrop = defaults.bool(forKey: "step.backdrop")
        backdropStyle = BackdropStyle(rawValue: defaults.string(forKey: "backdrop.style") ?? "")
            ?? .graphite
        changeResolution = defaults.bool(forKey: "step.resolution")
        let storedMode = defaults.integer(forKey: "resolution.modeID")
        targetModeID = storedMode == 0 ? nil : Int32(storedMode)
        placeWindow = defaults.bool(forKey: "step.placeWindow")
        placement = PlacementPreset(rawValue: defaults.string(forKey: "placement.preset") ?? "")
            ?? .centered16x10
        refresh()
    }

    // MARK: Refresh pickers / permission state

    func refresh() {
        let display = CGMainDisplayID()
        modeChoices = Resolution.choices(for: display)
        currentModeID = Resolution.currentModeID(of: display)
        if let target = targetModeID, !modeChoices.contains(where: { $0.id == target }) {
            targetModeID = nil
        }
        runningApps = WindowPlacer.regularApps()
        if let pid = targetAppPid, !runningApps.contains(where: { $0.pid == pid }) {
            targetAppPid = nil
        }
        axTrusted = WindowPlacer.isTrusted
    }

    func requestAccessibility() {
        WindowPlacer.requestTrust()
        axTrusted = WindowPlacer.isTrusted
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
        snap.backdropShown = useBackdrop
        if changeResolution, let target = targetModeID {
            let display = CGMainDisplayID()
            if let current = Resolution.currentModeID(of: display), current != target {
                snap.display = .init(displayID: display, modeID: current)
            }
        } else if changeResolution {
            notes.append("No target resolution chosen — skipped.")
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

        // 2. Persist the snapshot BEFORE mutating anything.
        Storage.saveSnapshot(snap)
        snapshot = snap

        // 3. Run the steps, in order.
        if snap.finder != nil {
            DesktopIcons.hideIcons()
        }
        if snap.backdropShown {
            backdrop.show(style: backdropStyle)
        }
        if let displaySnap = snap.display, let target = targetModeID {
            if !Resolution.apply(modeID: target, to: displaySnap.displayID) {
                notes.append("The display refused that resolution.")
            }
        }
        if let windowSnap = snap.window,
           let window = WindowPlacer.frontWindow(of: windowSnap.pid),
           let rect = placement.axRect() {
            if !WindowPlacer.setFrame(rect, of: window) {
                notes.append("The app didn't accept the window frame.")
            }
        }

        isStaged = true
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

        // Undo in reverse order of staging.
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
        if let displaySnap = snap.display {
            if !Resolution.apply(modeID: displaySnap.modeID, to: displaySnap.displayID) {
                notes.append("Couldn't restore the original resolution.")
            }
        }
        backdrop.hide()
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
