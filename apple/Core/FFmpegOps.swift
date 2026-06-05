import Foundation
// ffmpeg-kit is added as a binary XCFramework (see README). Importing under
// its module name. Until the framework is present the project builds with
// `optional: true` on the XCFramework reference, but every FFmpegOps call
// will trap at runtime — link the framework before running.
#if canImport(ffmpegkit)
import ffmpegkit
#endif

enum FFmpegError: Error {
    case ffmpegKitMissing
    case nonZeroExit(code: Int32, command: String, log: String)
}

/// Tiny wrapper around `FFmpegKit.execute(command:)` plus a handful of
/// convenience functions that mirror what the Python CLI used to do via
/// `subprocess`. All methods are synchronous and *must* be called off the
/// main thread.
enum FFmpegOps {

    /// Run a raw ffmpeg command. Returns the captured log output (stdout +
    /// stderr) so callers can parse it (e.g. silencedetect).
    @discardableResult
    static func run(_ command: String) throws -> String {
        #if canImport(ffmpegkit)
        let session = FFmpegKit.execute(command)
        guard let session else {
            throw FFmpegError.nonZeroExit(code: -1, command: command, log: "")
        }
        let code = session.getReturnCode()
        let log = session.getAllLogsAsString() ?? ""
        if !ReturnCode.isSuccess(code) {
            throw FFmpegError.nonZeroExit(
                code: code?.getValue() ?? -1, command: command, log: log
            )
        }
        return log
        #else
        throw FFmpegError.ffmpegKitMissing
        #endif
    }

    // MARK: – Specific post-processing helpers

    /// Convert any audio file to a 192 kbps MP3 at `out`.
    static func extractMP3(input: URL, output: URL) throws {
        try run("-y -i \"\(input.path)\" -vn -c:a libmp3lame -b:a 192k \"\(output.path)\"")
    }

    /// Slice a media file into [start, end] (seconds) using `-c copy` (fast,
    /// no re-encode). The container must be one where stream-copy works at
    /// arbitrary offsets — fine for MP3 and MP4 with `-c copy`.
    static func slice(
        input: URL, start: Double, end: Double, output: URL
    ) throws {
        let cmd = String(
            format: "-y -i \"%@\" -ss %.3f -to %.3f -c copy \"%@\"",
            input.path, start, end, output.path
        )
        try run(cmd)
    }

    /// Convert webp/jpg → png next to the source.
    static func convertImage(input: URL, output: URL) throws {
        try run("-y -i \"\(input.path)\" \"\(output.path)\"")
    }

    /// Probe a file's duration in seconds. Implemented via ffmpeg (not
    /// ffprobe) so we don't add a second binding.
    static func duration(of url: URL) throws -> Double {
        // ffmpeg writes "Duration: HH:MM:SS.ms" to stderr when given -i.
        let log: String
        do {
            log = try run("-i \"\(url.path)\" -hide_banner -f null -")
        } catch let FFmpegError.nonZeroExit(_, _, captured) {
            // ffmpeg may exit non-zero when given no output; the log still
            // contains the Duration line we want.
            log = captured
        }
        let pattern = #"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)"#
        guard let r = log.range(of: pattern, options: .regularExpression) else {
            return 0
        }
        let match = String(log[r])
        let parts = match.replacingOccurrences(of: "Duration: ", with: "")
            .split(separator: ":")
            .map { Double($0) ?? 0 }
        guard parts.count == 3 else { return 0 }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}
