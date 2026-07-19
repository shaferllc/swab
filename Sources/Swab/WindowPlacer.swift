import AppKit
import ApplicationServices

struct AppChoice: Identifiable, Hashable {
    let pid: pid_t
    let name: String
    let bundleID: String?
    var id: pid_t { pid }
}

enum PlacementPreset: String, CaseIterable {
    case centered16x10 = "Centered 16:10"
    case centered16x9 = "Centered 16:9"
    case goldenLeft = "Golden-ratio left"

    /// Target frame in Accessibility coordinates (top-left origin, global),
    /// computed against the main screen's visible area.
    @MainActor
    func axRect() -> CGRect? {
        guard let screen = NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        let cocoa: CGRect
        switch self {
        case .centered16x10: cocoa = Self.centered(aspect: 16.0 / 10.0, in: visible)
        case .centered16x9: cocoa = Self.centered(aspect: 16.0 / 9.0, in: visible)
        case .goldenLeft:
            cocoa = CGRect(x: visible.minX,
                           y: visible.minY,
                           width: (visible.width * 0.618).rounded(),
                           height: visible.height)
        }
        // Cocoa (bottom-left origin) → AX (top-left origin, relative to the
        // top of the primary screen).
        let globalTop = NSScreen.screens.first?.frame.maxY ?? cocoa.maxY
        return CGRect(x: cocoa.minX.rounded(),
                      y: (globalTop - cocoa.maxY).rounded(),
                      width: cocoa.width.rounded(),
                      height: cocoa.height.rounded())
    }

    private static func centered(aspect: CGFloat, in visible: CGRect) -> CGRect {
        var width = visible.width * 0.85
        var height = width / aspect
        if height > visible.height * 0.92 {
            height = visible.height * 0.92
            width = height * aspect
        }
        return CGRect(x: visible.midX - width / 2,
                      y: visible.midY - height / 2,
                      width: width,
                      height: height)
    }
}

/// Moves and sizes another app's frontmost window through the Accessibility
/// API. Requires the user to grant Accessibility access to Swab; everything
/// here degrades to a no-op (with an honest status message upstream) if that
/// permission is missing.
enum WindowPlacer {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt directing the user to Privacy & Security →
    /// Accessibility.
    static func requestTrust() {
        // kAXTrustedCheckOptionPrompt is a mutable global under Swift 6
        // strict concurrency; its value is the stable literal below.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func regularApps() -> [AppChoice] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap { app in
                guard let name = app.localizedName else { return nil }
                return AppChoice(pid: app.processIdentifier,
                                 name: name,
                                 bundleID: app.bundleIdentifier)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func frontWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            return (value as! AXUIElement)
        }
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement],
           let first = windows.first {
            return first
        }
        return nil
    }

    /// Current frame in AX coordinates, for the snapshot.
    static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID(),
              AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID(),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    @discardableResult
    static func setFrame(_ rect: CGRect, of window: AXUIElement) -> Bool {
        var position = rect.origin
        var size = rect.size
        var ok = true
        if let value = AXValueCreate(.cgPoint, &position) {
            ok = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success && ok
        } else { ok = false }
        if let value = AXValueCreate(.cgSize, &size) {
            ok = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success && ok
        } else { ok = false }
        // Some apps clamp position after a resize; setting position once more
        // keeps the final frame where it was asked to be.
        if let value = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        return ok
    }
}
