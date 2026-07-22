import Foundation

/// Tiny process runner. `run` is synchronous and used for the short commands
/// Swab depends on (`defaults`, `killall`, `shortcuts`, `screencapture -x`),
/// all of which return in milliseconds. `launch` starts a long-running process
/// (a screen recording) and hands back the handle so it can be stopped later.
enum Shell {
    struct Result {
        let status: Int32
        let stdout: String
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      stdout: String(data: data, encoding: .utf8) ?? "")
    }

    /// Starts a process without waiting for it. Returns nil if it wouldn't
    /// start at all. The caller owns the handle and is responsible for
    /// terminating it.
    static func launch(_ path: String, _ arguments: [String]) -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            NSLog("Swab: failed to launch \(path): \(error)")
            return nil
        }
        return process
    }

    /// True when the executable exists and is runnable — used to degrade
    /// gracefully when an optional tool (`shortcuts`) isn't present.
    static func exists(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
