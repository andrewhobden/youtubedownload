import Foundation
import PythonKit

/// Pipeline smoke test: bootstrap Python → probe URL → download → extract
/// MP3 via ffmpeg-kit → log everything. Triggered with the launch arg
/// `--smoke-test <youtube_url>`, intended for simulator/device validation
/// without depending on the SwiftUI Add sheet.
enum SmokeTest {

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--smoke-test"),
              idx + 1 < args.count else { return }

        let urlString = args[idx + 1]
        print("[SmokeTest] start url=\(urlString)")

        Task.detached(priority: .userInitiated) {
            do {
                try await runPipeline(urlString)
            } catch {
                print("[SmokeTest] FAILED: \(error)")
            }
        }
    }

    private static func runPipeline(_ urlString: String) async throws {
        try PythonBridge.shared.bootstrap()
        guard let url = URL(string: urlString) else {
            print("[SmokeTest] invalid url")
            return
        }

        // 1. Probe
        let probe = try YouTubeProbe.probe(url)
        print("[SmokeTest] probe: title=\"\(probe.title)\" " +
              "dur=\(Int(probe.durationSec))s chapters=\(probe.chapterCount) " +
              "playlist=\(probe.isPlaylist) entries=\(probe.entryCount)")

        // 2. Download into the app's tmp dir (writable on iOS).
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smoke-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(
            at: tmpDir, withIntermediateDirectories: true
        )
        print("[SmokeTest] outDir=\(tmpDir.path)")

        let cookieFile = YouTubeAuth.currentCookieFilePath()
        let paths: [String] = try PythonBridge.shared.run { mod in
            let result = mod.download_raw(
                url.absoluteString,
                tmpDir.path,
                audio_only: true,
                follow_playlist: false,
                progress_cb: Python.None,
                cookiefile: cookieFile
            )
            if Bool(result["ok"]) != true {
                let msg = String(result["error"]) ?? "Unknown"
                throw YouTubeError(message: msg)
            }
            return Array(result["paths"]).compactMap { String($0) }
        }
        print("[SmokeTest] downloaded \(paths.count) file(s):")
        for p in paths { print("  - \(p)") }
        guard let firstPath = paths.first else {
            print("[SmokeTest] no file produced — aborting before ffmpeg step")
            return
        }

        // 3. ffmpeg-kit smoke test: convert to mp3.
        let raw = URL(fileURLWithPath: firstPath)
        let mp3 = tmpDir.appendingPathComponent("\(raw.deletingPathExtension().lastPathComponent).mp3")
        do {
            try FFmpegOps.extractMP3(input: raw, output: mp3)
            let size = (try? mp3.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            print("[SmokeTest] mp3 produced: \(mp3.lastPathComponent) (\(size) bytes)")
            let dur = (try? FFmpegOps.duration(of: mp3)) ?? 0
            print("[SmokeTest] mp3 duration: \(dur)s")
        } catch {
            print("[SmokeTest] ffmpeg-kit FAILED: \(error)")
        }
        print("[SmokeTest] done")
    }
}
