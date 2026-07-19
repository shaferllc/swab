import Foundation

/// Tiny synchronous process runner for the two commands Swab needs
/// (`defaults` and `killall`). Both return in milliseconds.
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
}
