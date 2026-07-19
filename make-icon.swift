#!/usr/bin/env swift
// Generates AppIcon.icns programmatically: a teal-to-deep-blue squircle, a
// clean white "screen" rectangle, a mop sweeping across it, and a sparkle.
// Usage: swift make-icon.swift  (run from the swab dir)

import AppKit
import Foundation

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func star4(center: NSPoint, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let inner = radius * 0.30
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 + .pi / 2
        let r = i % 2 == 0 ? radius : inner
        let pt = NSPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
    }
    path.close()
    return path
}

func makePNG(size px: Int) -> Data? {
    let pf = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
    else { return nil }
    rep.size = NSSize(width: pf, height: pf)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    // Squircle background: teal → deep ocean blue.
    let radius = pf * 0.225
    let squircle = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: pf, height: pf),
                                xRadius: radius, yRadius: radius)
    squircle.addClip()
    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.15, green: 0.62, blue: 0.64, alpha: 1),
        NSColor(srgbRed: 0.05, green: 0.22, blue: 0.42, alpha: 1),
    ])!
    grad.draw(in: NSRect(x: 0, y: 0, width: pf, height: pf), angle: -90)

    // The clean rectangle — a freshly swabbed "screen".
    let rw = pf * 0.64
    let rh = pf * 0.44
    let rx = (pf - rw) / 2
    let ry = pf * 0.16
    let screen = NSBezierPath(roundedRect: NSRect(x: rx, y: ry, width: rw, height: rh),
                              xRadius: pf * 0.055, yRadius: pf * 0.055)
    NSColor(srgbRed: 0.99, green: 0.99, blue: 0.985, alpha: 1).setFill()
    screen.fill()

    // Mop: a gold handle sweeping in from the top right, fringe brushing the
    // clean rectangle.
    let headPoint = NSPoint(x: pf * 0.545, y: pf * 0.475)
    let handleTop = NSPoint(x: pf * 0.845, y: pf * 0.895)
    let handle = NSBezierPath()
    handle.move(to: handleTop)
    handle.line(to: headPoint)
    handle.lineWidth = max(1.5, pf * 0.052)
    handle.lineCapStyle = .round
    NSColor(srgbRed: 0.94, green: 0.72, blue: 0.30, alpha: 1).setStroke()
    handle.stroke()

    // Mop collar: a small dark band where fringe meets handle.
    let collarR = pf * 0.045
    let collar = NSBezierPath(ovalIn: NSRect(x: headPoint.x - collarR,
                                             y: headPoint.y - collarR,
                                             width: collarR * 2, height: collarR * 2))
    NSColor(srgbRed: 0.07, green: 0.28, blue: 0.44, alpha: 1).setFill()
    collar.fill()

    // Fringe: strands fanning down-left across the white rectangle.
    let fringe = NSBezierPath()
    let strandLength = pf * 0.17
    let baseAngle = CGFloat.pi * 1.22   // pointing down-left
    for i in 0..<5 {
        let spread = (CGFloat(i) - 2) * 0.16
        let angle = baseAngle + spread
        let end = NSPoint(x: headPoint.x + cos(angle) * strandLength,
                          y: headPoint.y + sin(angle) * strandLength)
        fringe.move(to: headPoint)
        // Slight bow in each strand so it reads as soft rope, not a rake.
        let mid = NSPoint(x: (headPoint.x + end.x) / 2 + pf * 0.012,
                          y: (headPoint.y + end.y) / 2 - pf * 0.012)
        fringe.curve(to: end, controlPoint1: mid, controlPoint2: mid)
    }
    fringe.lineWidth = max(1, pf * 0.030)
    fringe.lineCapStyle = .round
    NSColor(srgbRed: 0.10, green: 0.36, blue: 0.52, alpha: 1).setStroke()
    fringe.stroke()

    // Sparkles: the freshly cleaned gleam.
    NSColor.white.setFill()
    star4(center: NSPoint(x: pf * 0.255, y: pf * 0.78), radius: pf * 0.085).fill()
    NSColor(calibratedWhite: 1, alpha: 0.85).setFill()
    star4(center: NSPoint(x: pf * 0.40, y: pf * 0.685), radius: pf * 0.042).fill()

    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = makePNG(size: px) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path,
                  "-o", here.appendingPathComponent("AppIcon.icns").path]
try proc.run()
proc.waitUntilExit()
print("Wrote AppIcon.icns")
