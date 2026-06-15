import Foundation
import os.log
// ffmpeg-kit is added as a binary XCFramework (see README). Importing under
// its module name. Until the framework is present the project builds with
// `optional: true` on the XCFramework reference, but every FFmpegOps call
// will trap at runtime — link the framework before running.
#if canImport(ffmpegkit)
import ffmpegkit
#endif

private let ffLog = Logger(subsystem: "com.anhobden.youtubelibrary", category: "FFmpegOps")

enum FFmpegError: Error {
    case ffmpegKitMissing
    case nonZeroExit(code: Int32, command: String, log: String)
}

/// Tiny wrapper around `FFmpegKit.execute(command:)` plus a handful of
/// convenience functions that mirror what the Python CLI used to do via
/// `subprocess`. All methods are synchronous and *must* be called off the
/// main thread.
enum FFmpegOps {

    /// Serial queue that absorbs the blocking `run` semaphore wait off the
    /// main thread (and off the Swift concurrency cooperative pool). ffmpeg
    /// sessions run one at a time to avoid concurrent-session issues.
    private static let queue = DispatchQueue(
        label: "com.anhobden.youtubelibrary.ffmpeg", qos: .userInitiated
    )

    /// Run a blocking `FFmpegOps`/`SilenceSplitter` closure on the dedicated
    /// background queue, suspending (not blocking) the caller. Use this from
    /// `@MainActor` contexts so the UI stays responsive while ffmpeg works.
    static func runDetached<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Run a raw ffmpeg command as an array of arguments (no shell
    /// tokenisation, so paths with spaces / parens / quotes are safe).
    /// Returns the captured log output (stdout + stderr).
    ///
    /// Implementation note: we use the **async** entry point and block on
    /// a semaphore. The synchronous `execute(withArguments:)` returns
    /// before ffmpeg actually finishes when called repeatedly in tight
    /// succession (observed during chapter slicing — most slices came back
    /// with non-success return codes even though the inputs were valid).
    /// The async + completion-callback pattern guarantees the session is
    /// complete by the time we inspect its return code.
    @discardableResult
    static func run(_ args: [String]) throws -> String {
        #if canImport(ffmpegkit)
        let semaphore = DispatchSemaphore(value: 0)
        // The completion callback parameter is concretely typed as
        // FFmpegSession in the Obj-C header; binding to `any Session`
        // silently fails on some Swift bridges. Use the concrete type.
        nonisolated(unsafe) var finished: FFmpegSession?
        FFmpegKit.execute(
            withArgumentsAsync: args,
            withCompleteCallback: { session in
                finished = session
                semaphore.signal()
            }
        )
        semaphore.wait()

        guard let session = finished else {
            ffLog.error("run: callback fired with nil session for \(args.joined(separator: " "), privacy: .public)")
            throw FFmpegError.nonZeroExit(
                code: -1, command: args.joined(separator: " "), log: ""
            )
        }
        let code = session.getReturnCode()
        let log = session.getAllLogsAsString() ?? ""
        if !ReturnCode.isSuccess(code) {
            let codeValue = code?.getValue().description ?? "nil"
            let stateRaw = session.getState().rawValue
            ffLog.error("run: non-success code=\(codeValue, privacy: .public) stateRaw=\(stateRaw, privacy: .public) args=\(args.joined(separator: " "), privacy: .public)")
            throw FFmpegError.nonZeroExit(
                code: code?.getValue() ?? -1,
                command: args.joined(separator: " "),
                log: log
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
        try run([
            "-y",
            "-i", input.path,
            "-vn",
            "-c:a", "libmp3lame",
            "-b:a", "192k",
            output.path,
        ])
    }

    /// Slice a media file into [start, end] (seconds) using `-c copy` (fast,
    /// no re-encode). The container must be one where stream-copy works at
    /// arbitrary offsets — fine for MP3 and MP4 with `-c copy`.
    static func slice(
        input: URL, start: Double, end: Double, output: URL
    ) throws {
        try run([
            "-y",
            "-i", input.path,
            "-ss", String(format: "%.3f", start),
            "-to", String(format: "%.3f", end),
            "-c", "copy",
            output.path,
        ])
    }

    /// Convert webp/jpg → png next to the source.
    static func convertImage(input: URL, output: URL) throws {
        try run(["-y", "-i", input.path, output.path])
    }

    /// Probe a file's duration in seconds. Implemented via ffmpeg (not
    /// ffprobe) so we don't add a second binding.
    ///
    /// Uses `ffmpeg -i <file>` with **no output**: ffmpeg prints the container
    /// metadata (including the `Duration:` line) and then exits non-zero with
    /// "At least one output file must be specified" — *without decoding any
    /// media*. We parse the duration from that captured log. (A previous
    /// `-f null -` form forced a full-file decode, pegging the CPU for tens of
    /// seconds on long media.)
    static func duration(of url: URL) throws -> Double {
        let args = ["-i", url.path, "-hide_banner"]
        let log: String
        do {
            log = try run(args)
        } catch let FFmpegError.nonZeroExit(_, _, captured) {
            // Expected: no output file specified. The log still contains the
            // Duration line we want.
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

    // MARK: – Off-main async variants

    /// Async, off-main version of `run`. Frees the calling actor while ffmpeg works.
    @discardableResult
    static func runAsync(_ args: [String]) async throws -> String {
        try await runDetached { try run(args) }
    }

    /// Async, off-main version of `extractMP3`.
    static func extractMP3Async(input: URL, output: URL) async throws {
        try await runDetached { try extractMP3(input: input, output: output) }
    }

    /// Async, off-main version of `slice`.
    static func sliceAsync(
        input: URL, start: Double, end: Double, output: URL
    ) async throws {
        try await runDetached { try slice(input: input, start: start, end: end, output: output) }
    }

    /// Async, off-main version of `convertImage`.
    static func convertImageAsync(input: URL, output: URL) async throws {
        try await runDetached { try convertImage(input: input, output: output) }
    }

    /// Async, off-main version of `duration`.
    static func durationAsync(of url: URL) async throws -> Double {
        try await runDetached { try duration(of: url) }
    }
}
