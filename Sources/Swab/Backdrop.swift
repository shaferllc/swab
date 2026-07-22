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

/// How the backdrop is filled. Presets stay the one-click path; the other three
/// kinds are the custom escape hatch.
enum BackdropKind: String, CaseIterable, Codable {
    case preset = "Preset"
    case solid = "Solid"
    case gradient = "Gradient"
    case image = "Image"
}

/// The full backdrop choice, persisted with presets so a saved setup restores
/// its exact look.
struct BackdropConfig: Codable, Equatable {
    var kind: BackdropKind = .preset
    var preset: BackdropStyle = .graphite
    /// sRGB hex, `#RRGGBB`. `top` alone is the solid fill.
    var topHex: String = "#2E3138"
    var bottomHex: String = "#1A1C21"
    var imagePath: String?

    /// Colors to draw, top first. An empty result means "draw the image".
    var colors: [NSColor] {
        switch kind {
        case .preset:
            return preset.nsColors
        case .solid:
            return [NSColor(hex: topHex) ?? .darkGray]
        case .gradient:
            return [NSColor(hex: topHex) ?? .darkGray,
                    NSColor(hex: bottomHex) ?? .black]
        case .image:
            return []
        }
    }

    var swiftUIColors: [Color] {
        let resolved = colors
        if resolved.isEmpty { return [.gray, .gray] }
        return (resolved.count == 1 ? [resolved[0], resolved[0]] : resolved)
            .map(Color.init(nsColor:))
    }

    /// A short human label for the status line and preset summaries.
    var label: String {
        switch kind {
        case .preset: return preset.rawValue
        case .solid: return "Solid \(topHex)"
        case .gradient: return "Gradient \(topHex) → \(bottomHex)"
        case .image:
            guard let path = imagePath else { return "Image (none chosen)" }
            return "Image · \(URL(fileURLWithPath: path).lastPathComponent)"
        }
    }

    /// The backdrop can't draw an image that isn't there — the UI uses this to
    /// warn instead of silently showing an empty screen.
    var isRenderable: Bool {
        guard kind == .image else { return true }
        guard let path = imagePath else { return false }
        return FileManager.default.isReadableFile(atPath: path)
    }
}

extension NSColor {
    /// Parses `#RRGGBB` / `RRGGBB`. Returns nil on anything else so callers can
    /// fall back rather than draw a surprise color.
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                  green: CGFloat((value >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(value & 0xFF) / 255.0,
                  alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

final class BackdropView: NSView {
    var colors: [NSColor] = [] {
        didSet { needsDisplay = true }
    }
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let image {
            // Aspect-fill: cover the whole display, cropping the overflow.
            let size = image.size
            guard size.width > 0, size.height > 0 else { return }
            let scale = max(bounds.width / size.width, bounds.height / size.height)
            let drawn = NSRect(x: bounds.midX - size.width * scale / 2,
                               y: bounds.midY - size.height * scale / 2,
                               width: size.width * scale,
                               height: size.height * scale)
            NSColor.black.setFill()
            bounds.fill()
            image.draw(in: drawn)
        } else if colors.count >= 2 {
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

    func show(config: BackdropConfig) {
        hide()
        // Load the image once and share it across displays.
        let image: NSImage? = {
            guard config.kind == .image, let path = config.imagePath else { return nil }
            return NSImage(contentsOfFile: path)
        }()
        let colors = config.colors

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
            view.colors = colors
            view.image = image
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
