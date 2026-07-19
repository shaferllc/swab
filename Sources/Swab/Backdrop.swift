import AppKit
import SwiftUI

/// A clean stand-in wallpaper: one borderless, click-through window per
/// display, floated just above the desktop picture (kCGDesktopWindowLevel + 1)
/// but below the icon layer. Nothing about the real wallpaper is touched —
/// closing the windows is the whole restore. The windows use the default
/// sharing type on purpose: they SHOULD show up in screenshots and recordings.
enum BackdropStyle: String, CaseIterable, Codable {
    case graphite = "Graphite"
    case midnight = "Midnight"
    case ocean = "Ocean"
    case dawn = "Dawn"
    case paper = "Paper"

    /// Top color first; single entry means a solid fill.
    var nsColors: [NSColor] {
        switch self {
        case .graphite:
            return [NSColor(srgbRed: 0.18, green: 0.19, blue: 0.21, alpha: 1),
                    NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)]
        case .midnight:
            return [NSColor(srgbRed: 0.08, green: 0.11, blue: 0.23, alpha: 1),
                    NSColor(srgbRed: 0.03, green: 0.04, blue: 0.11, alpha: 1)]
        case .ocean:
            return [NSColor(srgbRed: 0.11, green: 0.38, blue: 0.47, alpha: 1),
                    NSColor(srgbRed: 0.04, green: 0.16, blue: 0.31, alpha: 1)]
        case .dawn:
            return [NSColor(srgbRed: 0.96, green: 0.80, blue: 0.70, alpha: 1),
                    NSColor(srgbRed: 0.77, green: 0.65, blue: 0.85, alpha: 1)]
        case .paper:
            return [NSColor(srgbRed: 0.93, green: 0.92, blue: 0.90, alpha: 1)]
        }
    }

    var swiftUIColors: [Color] {
        let colors = nsColors
        return (colors.count == 1 ? [colors[0], colors[0]] : colors).map(Color.init(nsColor:))
    }
}

final class BackdropView: NSView {
    var colors: [NSColor] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if colors.count >= 2 {
            NSGradient(colors: colors)?.draw(in: bounds, angle: -90)
        } else if let solid = colors.first {
            solid.setFill()
            bounds.fill()
        }
    }
}

@MainActor
final class BackdropController {
    private var windows: [NSWindow] = []

    var isShowing: Bool { !windows.isEmpty }

    func show(style: BackdropStyle) {
        hide()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: .borderless,
                                  backing: .buffered,
                                  defer: false)
            window.level = NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let view = BackdropView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.colors = style.nsColors
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFront(nil)
            windows.append(window)
        }
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }
}
