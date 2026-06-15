import Foundation

/// Pure Swift port of `detect_silence_gaps` and `split_audio_by_silence`
/// from download.py. Kept thresholds 1:1 with the CLI defaults so behaviour
/// matches what we tested at the terminal.
enum SilenceSplitter {

    static let defaultNoiseDb: Double = -30.0
    static let defaultMinSilence: Double = 1.5
    static let defaultMinTrack: Double = 30.0

    /// `(silence_start, silence_end)` pairs, in seconds.
    static func detectGaps(
        in mp3: URL,
        noiseDb: Double = defaultNoiseDb,
        minSilence: Double = defaultMinSilence
    ) throws -> [(Double, Double)] {
        let args = [
            "-hide_banner", "-nostats",
            "-i", mp3.path,
            "-af", String(format: "silencedetect=noise=%.1fdB:d=%.2f", noiseDb, minSilence),
            "-f", "null", "-",
        ]
        let log: String
        do {
            log = try FFmpegOps.run(args)
        } catch let FFmpegError.nonZeroExit(_, _, captured) {
            // silencedetect writes to stderr; non-zero exit is OK here too.
            log = captured
        }

        let starts = scrapeFloats(in: log, pattern: #"silence_start:\s*([0-9.]+)"#)
        let ends   = scrapeFloats(in: log, pattern: #"silence_end:\s*([0-9.]+)"#)
        let n = min(starts.count, ends.count)
        return (0..<n).map { (starts[$0], ends[$0]) }
    }

    /// Split `mp3` into tracks at the detected silences. Writes one file per
    /// track into `outDir`, named `NNN<baseName>.mp3`.
    ///
    /// Returns the relative filenames in order.
    static func splitByGaps(
        mp3: URL,
        outDir: URL,
        baseName: String,
        totalDuration: Double,
        noiseDb: Double = defaultNoiseDb,
        minSilence: Double = defaultMinSilence,
        minTrack: Double = defaultMinTrack
    ) throws -> [String] {
        let silences = try detectGaps(in: mp3, noiseDb: noiseDb, minSilence: minSilence)

        // Walk silences building (start, end) track ranges. Skip ranges
        // shorter than minTrack so leading/trailing silence and false
        // positives between songs don't become "tracks".
        var ranges: [(Double, Double)] = []
        var cursor: Double = 0
        for (sStart, sEnd) in silences {
            let end = sStart
            if end - cursor >= minTrack {
                ranges.append((cursor, end))
            }
            cursor = sEnd
        }
        if totalDuration - cursor >= minTrack {
            ranges.append((cursor, totalDuration))
        }

        var produced: [String] = []
        for (i, (start, end)) in ranges.enumerated() {
            let name = String(format: "%03d%@.mp3", i + 1, baseName)
            let outURL = outDir.appendingPathComponent(name)
            try FFmpegOps.slice(input: mp3, start: start, end: end, output: outURL)
            produced.append(name)
        }
        return produced
    }

    /// Async, off-main version of `splitByGaps` (runs the whole detect+slice
    /// on the shared ffmpeg queue so the UI stays responsive).
    static func splitByGapsAsync(
        mp3: URL,
        outDir: URL,
        baseName: String,
        totalDuration: Double,
        noiseDb: Double = defaultNoiseDb,
        minSilence: Double = defaultMinSilence,
        minTrack: Double = defaultMinTrack
    ) async throws -> [String] {
        try await FFmpegOps.runDetached {
            try splitByGaps(
                mp3: mp3, outDir: outDir, baseName: baseName,
                totalDuration: totalDuration, noiseDb: noiseDb,
                minSilence: minSilence, minTrack: minTrack
            )
        }
    }

    private static func scrapeFloats(in haystack: String, pattern: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = haystack as NSString
        let matches = regex.matches(in: haystack, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            guard m.numberOfRanges >= 2 else { return nil }
            return Double(ns.substring(with: m.range(at: 1)))
        }
    }
}
