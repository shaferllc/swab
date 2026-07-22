import AppKit
import QuartzCore

/// Draws an expanding ring wherever you click, so a viewer watching the
/// recording can see what you pressed.
///
/// The ring lives in a borderless, click-through overlay window above
/// everything else. Clicks are observed with a global NSEvent monitor — a
/// read-only observer that can't alter or swallow the event, so the click still
/// lands normally in whatever app is underneath.
@MainActor
final class ClickHighlighter {
    private var window: NSWindow?
    private var monitor: Any?
    private var ring: CAShapeLayer?

    private let diameter: CGFloat = 90

    private(set) var isActive = false

    func start() {
        guard !isActive else { return }
        makeWindow()
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.flash(at: NSEvent.mouseLocation)
            }
            _ = event
        }
        isActive = true
    }

    func stop() {
        guard isActive else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        ring = nil
        isActive = false
    }

    private func makeWindow() {
        let frame = NSRect(x: 0, y: 0, width: diameter, height: diameter)
        let w = NSWindow(contentRect: frame,
                         styleMask: .borderless,
                         backing: .buffered,
                         defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let host = NSView(frame: frame)
        host.wantsLayer = true

        let shape = CAShapeLayer()
        let inset: CGFloat = 4
        shape.path = CGPath(ellipseIn: frame.insetBy(dx: inset, dy: inset), transform: nil)
        shape.fillColor = NSColor.systemYellow.withAlphaComponent(0.22).cgColor
        shape.strokeColor = NSColor.systemYellow.cgColor
        shape.lineWidth = 3
        shape.opacity = 0
        // Scale about the middle so the ring grows out of the click point.
        shape.frame = frame
        host.layer?.addSublayer(shape)

        w.contentView = host
        window = w
        ring = shape
    }

    /// `point` is a global Cocoa (bottom-left origin) location, which is what
    /// both NSEvent.mouseLocation and NSWindow.setFrameOrigin speak.
    private func flash(at point: NSPoint) {
        guard let window, let ring else { return }
        window.setFrameOrigin(NSPoint(x: point.x - diameter / 2,
                                      y: point.y - diameter / 2))
        window.orderFrontRegardless()

        ring.removeAllAnimations()

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.35
        scale.toValue = 1.0

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = true

        ring.add(group, forKey: "click")
    }
}
