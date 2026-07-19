import Foundation

/// Everything Swab changed, recorded BEFORE it changed anything, so Restore
/// (or a relaunch after a crash) can put the desk back exactly as it was.
struct Snapshot: Codable {
    var takenAt: Date
    var backdropShown: Bool = false
    var finder: FinderSnapshot?
    var display: DisplaySnapshot?
    var window: WindowSnapshot?

    struct FinderSnapshot: Codable {
        /// `defaults read com.apple.finder CreateDesktop` had no value at all
        /// (which macOS treats as "true"). Restore then deletes the key rather
        /// than writing one that was never there.
        var keyWasAbsent: Bool
        var createDesktop: Bool
    }

    struct DisplaySnapshot: Codable {
        var displayID: UInt32
        var modeID: Int32
    }

    struct WindowSnapshot: Codable {
        var pid: Int32
        var bundleID: String?
        var appName: String?
        // Original frame in Accessibility (top-left origin) coordinates.
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }
}

enum Storage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appendingPathComponent("Swab", isDirectory: true)
    }

    static var snapshotURL: URL {
        directory.appendingPathComponent("snapshot.json")
    }

    static func saveSnapshot(_ snapshot: Snapshot) {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
        } catch {
            NSLog("Swab: failed to persist snapshot: \(error)")
        }
    }

    static func loadSnapshot() -> Snapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func deleteSnapshot() {
        try? FileManager.default.removeItem(at: snapshotURL)
    }
}
