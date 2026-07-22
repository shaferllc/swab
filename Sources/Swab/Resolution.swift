import AppKit
import CoreGraphics
import Foundation

struct DisplayModeChoice: Identifiable, Hashable {
    let id: Int32          // ioDisplayModeID — stable enough to restore by
    let width: Int
    let height: Int
    let refresh: Double
    let isHiDPI: Bool

    var isRecordingFriendly: Bool {
        (width == 1920 && height == 1080) || (width == 1280 && height == 800)
    }

    var label: String {
        var text = "\(width) × \(height)"
        if isHiDPI { text += "  ·  HiDPI" }
        if isRecordingFriendly { text += "  ★ recording-friendly" }
        return text
    }
}

/// One attached display, with the modes it can be switched to.
struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let modes: [DisplayModeChoice]
    let currentModeID: Int32?

    var currentLabel: String {
        guard let current = currentModeID,
              let mode = modes.first(where: { $0.id == current }) else { return "—" }
        return "\(mode.width) × \(mode.height)"
    }
}

/// Display-mode enumeration and switching, via Core Graphics. Changes are
/// applied `.forSession` inside a display-configuration transaction; every
/// display's pre-stage mode ID is snapshotted so Restore is exact.
enum Resolution {
    private static var options: CFDictionary {
        [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    }

    private static func rawModes(for display: CGDirectDisplayID) -> [CGDisplayMode] {
        (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
    }

    /// Every active display, main first, then left-to-right.
    @MainActor
    static func displays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        let main = CGMainDisplayID()
        return ids.prefix(Int(count)).map { id in
            DisplayInfo(id: id,
                        name: name(of: id),
                        isMain: id == main,
                        modes: choices(for: id),
                        currentModeID: currentModeID(of: id))
        }
        .sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// NSScreen carries the human-readable name; CGDirectDisplayID is the key
    /// that links the two.
    @MainActor
    private static func name(of display: CGDirectDisplayID) -> String {
        let match = NSScreen.screens.first { screen in
            (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value == display
        }
        if let name = match?.localizedName, !name.isEmpty { return name }
        return CGDisplayIsBuiltin(display) != 0 ? "Built-in Display" : "Display \(display)"
    }

    /// Usable desktop modes, deduped per width×height (preferring HiDPI, then
    /// higher refresh), sorted large-to-small.
    static func choices(for display: CGDirectDisplayID) -> [DisplayModeChoice] {
        var best: [String: DisplayModeChoice] = [:]
        for mode in rawModes(for: display) where mode.isUsableForDesktopGUI() {
            let choice = DisplayModeChoice(id: mode.ioDisplayModeID,
                                           width: mode.width,
                                           height: mode.height,
                                           refresh: mode.refreshRate,
                                           isHiDPI: mode.pixelWidth > mode.width)
            let key = "\(choice.width)x\(choice.height)"
            if let existing = best[key] {
                let better = (choice.isHiDPI && !existing.isHiDPI)
                    || (choice.isHiDPI == existing.isHiDPI && choice.refresh > existing.refresh)
                if better { best[key] = choice }
            } else {
                best[key] = choice
            }
        }
        return best.values.sorted {
            ($0.width, $0.height) > ($1.width, $1.height)
        }
    }

    static func currentModeID(of display: CGDirectDisplayID) -> Int32? {
        CGDisplayCopyDisplayMode(display)?.ioDisplayModeID
    }

    @discardableResult
    static func apply(modeID: Int32, to display: CGDirectDisplayID) -> Bool {
        guard let mode = rawModes(for: display).first(where: { $0.ioDisplayModeID == modeID })
        else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config
        else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, display, mode, nil) == .success
        else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    /// Applies several displays in ONE transaction, so the screens reconfigure
    /// together instead of flickering one after another. Returns the IDs that
    /// were refused.
    static func applyAll(_ targets: [(display: CGDirectDisplayID, modeID: Int32)]) -> [CGDirectDisplayID] {
        guard !targets.isEmpty else { return [] }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config
        else { return targets.map(\.display) }

        var refused: [CGDirectDisplayID] = []
        for target in targets {
            guard let mode = rawModes(for: target.display)
                .first(where: { $0.ioDisplayModeID == target.modeID }),
                CGConfigureDisplayWithDisplayMode(config, target.display, mode, nil) == .success
            else {
                refused.append(target.display)
                continue
            }
        }
        if refused.count == targets.count {
            CGCancelDisplayConfiguration(config)
            return refused
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            return targets.map(\.display)
        }
        return refused
    }
}
