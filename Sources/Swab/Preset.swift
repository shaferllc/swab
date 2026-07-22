import Foundation

/// A whole staged setup, saved under a name. Presets capture the *intent*
/// (which steps, which look, which resolutions) — never the pre-stage state,
/// which is what Snapshot is for.
struct StagePreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String

    var hideIcons: Bool = true
    var useBackdrop: Bool = true
    var backdrop: BackdropConfig = BackdropConfig()

    var changeResolution: Bool = false
    /// displayID (as a string, so it survives JSON round-tripping cleanly)
    /// → target ioDisplayModeID.
    var displayTargets: [String: Int32] = [:]

    var placeWindow: Bool = false
    var placement: PlacementPreset = .centered16x10
    /// Bundle ID rather than pid — pids churn between sessions.
    var targetBundleID: String?

    var pairFocus: Bool = false
    var autoRestore: Bool = false
    var autoRestoreMinutes: Int = 10

    var showCursorInCaptures: Bool = false
    var highlightClicks: Bool = false

    /// One-line summary for the preset list.
    var summary: String {
        var parts: [String] = []
        if hideIcons { parts.append("icons hidden") }
        if useBackdrop { parts.append(backdrop.label.lowercased()) }
        if changeResolution, !displayTargets.isEmpty {
            parts.append(displayTargets.count == 1
                         ? "1 display" : "\(displayTargets.count) displays")
        }
        if placeWindow { parts.append("window placed") }
        if pairFocus { parts.append("focus paired") }
        if autoRestore { parts.append("auto-restore \(autoRestoreMinutes)m") }
        return parts.isEmpty ? "no steps enabled" : parts.joined(separator: " · ")
    }
}

/// The saved presets, plus the per-app frame memory. Both live in one file so
/// there's a single thing to back up or delete.
struct PresetLibrary: Codable {
    var presets: [StagePreset] = []
    /// bundleID → the placement last used for that app, so picking an app
    /// recalls the frame you liked for it.
    var windowPresets: [String: PlacementPreset] = [:]
}

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [StagePreset] = []
    @Published private(set) var windowPresets: [String: PlacementPreset] = [:]

    init() {
        let library = Storage.read(PresetLibrary.self, from: Storage.presetsURL)
            ?? PresetLibrary()
        presets = library.presets
        windowPresets = library.windowPresets
    }

    private func persist() {
        Storage.write(PresetLibrary(presets: presets, windowPresets: windowPresets),
                      to: Storage.presetsURL)
    }

    /// Saves under `name`, replacing an existing preset with the same name so
    /// re-saving a tweaked setup doesn't pile up duplicates.
    func save(_ preset: StagePreset) {
        var entry = preset
        if let index = presets.firstIndex(where: {
            $0.name.compare(entry.name, options: .caseInsensitive) == .orderedSame
        }) {
            entry.id = presets[index].id
            presets[index] = entry
        } else {
            presets.append(entry)
        }
        presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    func preset(named name: String) -> StagePreset? {
        presets.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    // MARK: Per-app window memory

    func rememberPlacement(_ placement: PlacementPreset, for bundleID: String) {
        guard windowPresets[bundleID] != placement else { return }
        windowPresets[bundleID] = placement
        persist()
    }

    func placement(for bundleID: String) -> PlacementPreset? {
        windowPresets[bundleID]
    }
}
