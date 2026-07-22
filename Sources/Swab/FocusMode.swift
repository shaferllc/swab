import Foundation

/// Focus modes, honestly.
///
/// macOS still exposes no API for setting a Focus mode — the README has said so
/// since the first version, and that hasn't changed. What macOS *does* expose
/// is the `shortcuts` CLI, and the Shortcuts app has a supported "Set Focus"
/// action. So Swab doesn't pretend to flip Focus itself: you build two
/// shortcuts, Swab runs them by name at stage and restore. If the shortcuts
/// aren't there, the step is skipped with a message rather than failing
/// silently.
enum FocusMode {
    static let toolPath = "/usr/bin/shortcuts"

    static var isAvailable: Bool { Shell.exists(toolPath) }

    /// Every shortcut in the user's library, for the picker. Returns an empty
    /// list if the CLI is missing or the user has no shortcuts.
    static func availableShortcuts() -> [String] {
        guard isAvailable else { return [] }
        let result = Shell.run(toolPath, ["list"])
        guard result.status == 0 else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Runs a shortcut by name. Returns false if the CLI is missing or the
    /// shortcut errored — the caller turns that into a visible note.
    @discardableResult
    static func run(_ name: String) -> Bool {
        guard isAvailable, !name.isEmpty else { return false }
        return Shell.run(toolPath, ["run", name]).status == 0
    }
}
