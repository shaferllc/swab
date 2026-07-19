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

/// Display-mode enumeration and switching for the main display, via Core
/// Graphics. Changes are applied `.forSession` inside a display-configuration
/// transaction; the pre-stage mode ID is snapshotted so Restore is exact.
enum Resolution {
    private static var options: CFDictionary {
        [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    }

    private static func rawModes(for display: CGDirectDisplayID) -> [CGDisplayMode] {
        (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
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
}
