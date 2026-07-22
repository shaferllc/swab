import AppKit
import Foundation

/// `swab stage` / `swab restore` from a terminal, a Makefile, or CI.
///
/// The CLI is a three-line shell script that calls `open -g swab://…`; the app
/// itself does the work. That keeps a single copy of the logic in one process
/// that already holds the snapshot, and means the command works whether or not
/// Swab is running — `open` launches it if needed.
enum CommandLineBridge {
    static let scheme = "swab"

    /// Preferred location first. `/usr/local/bin` is on the default PATH but
    /// isn't writable on a stock machine; `~/.local/bin` always is.
    static var installDirectories: [URL] {
        [URL(fileURLWithPath: "/usr/local/bin"),
         FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent(".local/bin", isDirectory: true)]
    }

    static var installedPath: URL? {
        installDirectories
            .map { $0.appendingPathComponent("swab") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static let script = """
    #!/bin/sh
    # swab — command-line control for Swab.app. Installed by Swab itself.
    # Every command is handed to the running app through its URL scheme.
    set -eu

    usage() {
      cat <<'EOF'
    usage: swab <command>

      stage             stage the desktop
      restore           put everything back
      toggle            stage if clear, restore if staged
      shot              take a screenshot
      record            start a screen recording
      stop              stop the screen recording
      preset <name>     load a saved preset
    EOF
    }

    cmd="${1:-toggle}"
    case "$cmd" in
      stage|restore|toggle|shot|record|stop)
        exec /usr/bin/open -g "swab://$cmd"
        ;;
      preset)
        [ $# -ge 2 ] || { echo "swab: preset needs a name" >&2; exit 2; }
        name=$(/usr/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$2")
        exec /usr/bin/open -g "swab://preset/$name"
        ;;
      -h|--help|help)
        usage
        ;;
      *)
        echo "swab: unknown command '$cmd'" >&2
        usage >&2
        exit 2
        ;;
    esac
    """

    /// Writes the script to the first writable directory. Returns the path, or
    /// nil if neither location could be written.
    @discardableResult
    static func install() -> URL? {
        for directory in installDirectories {
            let target = directory.appendingPathComponent("swab")
            do {
                try FileManager.default.createDirectory(at: directory,
                                                        withIntermediateDirectories: true)
                try script.write(to: target, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                      ofItemAtPath: target.path)
                return target
            } catch {
                continue
            }
        }
        return nil
    }

    /// True when the chosen directory isn't on PATH, so the UI can say so
    /// instead of leaving the user with a command the shell can't find.
    static func isOnPath(_ url: URL) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").contains { $0 == url.deletingLastPathComponent().path }
    }

    // MARK: URL routing

    /// Handles one `swab://…` URL. Returns a short description of what ran, for
    /// logging; unknown commands are ignored rather than guessed at.
    @MainActor
    @discardableResult
    static func handle(_ url: URL) -> String? {
        guard url.scheme == scheme, let command = url.host else { return nil }
        let stager = Stager.shared

        switch command {
        case "stage":
            stager.stage()
            return "stage"
        case "restore":
            stager.restore()
            return "restore"
        case "toggle":
            stager.toggle()
            return "toggle"
        case "shot":
            stager.capture.screenshot(showCursor: stager.showCursorInCaptures)
            return "shot"
        case "record":
            stager.capture.startRecording(showCursor: stager.showCursorInCaptures)
            return "record"
        case "stop":
            stager.capture.stopRecording()
            return "stop"
        case "preset":
            // swab://preset/Demo%20Mode — pathComponents already decodes the
            // escaping, so don't decode a second time or a preset with a
            // literal % in its name would come out mangled.
            let name = url.pathComponents
                .filter { $0 != "/" }
                .joined(separator: "/")
            guard !name.isEmpty else { return nil }
            return stager.applyPreset(named: name) ? "preset \(name)" : nil
        default:
            return nil
        }
    }
}
