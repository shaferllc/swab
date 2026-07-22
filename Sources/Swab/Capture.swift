import AppKit
import Foundation

/// Screenshots and screen recordings, via the system `screencapture` tool.
///
/// Using the built-in tool rather than ScreenCaptureKit is deliberate: it needs
/// no extra entitlement from Swab, it writes the same file formats the rest of
/// macOS does, and the Screen Recording permission prompt it triggers is the
/// familiar system one.
@MainActor
final class Capture: ObservableObject {
    static let toolPath = "/usr/sbin/screencapture"

    /// Captures land here rather than the Desktop — which is, after all,
    /// usually hidden while Swab is staged.
    static var outputDirectory: URL {
        let base = FileManager.default.urls(for: .picturesDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Swab", isDirectory: true)
    }

    @Published private(set) var isRecording = false
    @Published private(set) var lastOutput: URL?

    private var recorder: Process?

    private static func timestampedURL(extension ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Swab \(formatter.string(from: Date())).\(ext)"
        return outputDirectory.appendingPathComponent(name)
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: outputDirectory,
                                                 withIntermediateDirectories: true)
    }

    /// Full-screen screenshot. `showCursor` maps to screencapture's `-C`, which
    /// is off by default — so the cursor is excluded unless asked for.
    @discardableResult
    func screenshot(showCursor: Bool) -> URL? {
        Self.ensureDirectory()
        let url = Self.timestampedURL(extension: "png")
        var arguments = ["-x"]                  // -x: no camera sound
        if showCursor { arguments.append("-C") }
        arguments.append(url.path)
        guard Shell.run(Self.toolPath, arguments).status == 0 else { return nil }
        lastOutput = url
        return url
    }

    /// Starts a full-screen recording. macOS shows its own Screen Recording
    /// permission prompt the first time; until it's granted the file comes out
    /// empty, which `stopRecording` reports.
    @discardableResult
    func startRecording(showCursor: Bool) -> Bool {
        guard !isRecording else { return false }
        Self.ensureDirectory()
        let url = Self.timestampedURL(extension: "mov")
        var arguments = ["-v"]                  // -v: video
        if showCursor { arguments.append("-C") }
        arguments.append(url.path)
        guard let process = Shell.launch(Self.toolPath, arguments) else { return false }
        recorder = process
        lastOutput = url
        isRecording = true
        return true
    }

    /// Stops the recording. screencapture finalises the movie on SIGINT — a
    /// plain terminate would leave an unplayable file.
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording, let process = recorder else { return nil }
        process.interrupt()
        process.waitUntilExit()
        recorder = nil
        isRecording = false
        return lastOutput
    }

    func revealLastOutput() {
        guard let url = lastOutput,
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
