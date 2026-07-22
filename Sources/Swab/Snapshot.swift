import Foundation

/// Everything Swab changed, recorded BEFORE it changed anything, so Restore
/// (or a relaunch after a crash) can put the desk back exactly as it was.
struct Snapshot: Codable {
    var takenAt: Date
    var backdropShown: Bool = false
    var finder: FinderSnapshot?
    var displays: [DisplaySnapshot] = []
    var window: WindowSnapshot?
    var focus: FocusSnapshot?
    var clickHighlightShown: Bool = false

    init(takenAt: Date) {
        self.takenAt = takenAt
    }

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

    /// Swab can't read Focus state, so it records only what it *did*: which
    /// shortcut it ran on stage, and which one to run on restore.
    struct FocusSnapshot: Codable {
        var onShortcut: String
        var offShortcut: String
    }

    // MARK: Codable

    // `displays` replaced a single `display` field. A snapshot written by an
    // older build may still be sitting in Application Support after a crash —
    // the whole point of the file — so decode the legacy shape too rather than
    // throwing away a recovery the user is counting on.
    private enum CodingKeys: String, CodingKey {
        case takenAt, backdropShown, finder, displays, window, focus, clickHighlightShown
        case display   // legacy, single-display
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takenAt = try container.decode(Date.self, forKey: .takenAt)
        backdropShown = try container.decodeIfPresent(Bool.self, forKey: .backdropShown) ?? false
        finder = try container.decodeIfPresent(FinderSnapshot.self, forKey: .finder)
        window = try container.decodeIfPresent(WindowSnapshot.self, forKey: .window)
        focus = try container.decodeIfPresent(FocusSnapshot.self, forKey: .focus)
        clickHighlightShown = try container
            .decodeIfPresent(Bool.self, forKey: .clickHighlightShown) ?? false

        if let list = try container.decodeIfPresent([DisplaySnapshot].self, forKey: .displays) {
            displays = list
        } else if let legacy = try container.decodeIfPresent(DisplaySnapshot.self, forKey: .display) {
            displays = [legacy]
        } else {
            displays = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(takenAt, forKey: .takenAt)
        try container.encode(backdropShown, forKey: .backdropShown)
        try container.encodeIfPresent(finder, forKey: .finder)
        try container.encode(displays, forKey: .displays)
        try container.encodeIfPresent(window, forKey: .window)
        try container.encodeIfPresent(focus, forKey: .focus)
        try container.encode(clickHighlightShown, forKey: .clickHighlightShown)
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

    static var presetsURL: URL {
        directory.appendingPathComponent("presets.json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("Swab: failed to write \(url.lastPathComponent): \(error)")
        }
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func saveSnapshot(_ snapshot: Snapshot) { write(snapshot, to: snapshotURL) }
    static func loadSnapshot() -> Snapshot? { read(Snapshot.self, from: snapshotURL) }
    static func deleteSnapshot() { try? FileManager.default.removeItem(at: snapshotURL) }
}
