import Foundation
import SwiftData
import PythonKit

/// State of a single download job.
enum DownloadJobState: Equatable {
    case queued
    case probing
    case downloading(progress: Double)         // 0…1
    case postProcessing(stage: String)         // e.g. "converting", "splitting"
    case finished
    case failed(message: String)
}

/// One per add-URL row. Drives a job from probe → classify → download →
/// post-process → SwiftData write.
@MainActor
final class DownloadCoordinator: ObservableObject, Identifiable {

    let id = UUID()
    let url: URL
    let destination: LibraryDestination

    @Published private(set) var state: DownloadJobState = .queued
    @Published private(set) var inferredMode: DownloadMode?
    @Published private(set) var title: String = ""

    private let context: ModelContext
    private let mediaRoot: MediaRoot

    init(
        url: URL,
        destination: LibraryDestination,
        context: ModelContext,
        mediaRoot: MediaRoot
    ) {
        self.url = url
        self.destination = destination
        self.context = context
        self.mediaRoot = mediaRoot
    }

    /// Start the job. Returns when the job finishes or fails. Do not call
    /// twice on the same coordinator.
    func start() async {
        do {
            try await runJob()
        } catch {
            state = .failed(message: String(describing: error))
        }
    }

    // MARK: – Pipeline

    private func runJob() async throws {
        state = .probing
        let probe = try await Task.detached(priority: .userInitiated) { [url] in
            try YouTubeProbe.probe(url)
        }.value

        title = probe.title
        let mode = URLClassifier.classify(probe: probe, destination: destination)
        inferredMode = mode

        switch mode {
        case .ambiguousWatchAndList:
            // The UI is expected to resolve this and re-create the coordinator
            // with either Videos→single or Music→playlist semantics. We surface
            // a failed state with a marker the UI can detect.
            state = .failed(message: "AMBIGUOUS")
            return

        case .singleVideoMP4:
            try await downloadSingleVideo(probe: probe, asAudio: false)
        case .singleVideoMP3:
            try await downloadSingleVideo(probe: probe, asAudio: true)
        case .chaptersMP3:
            try await downloadChaptersAlbum(probe: probe)
        case .autosplitMP3:
            try await downloadAutosplitAlbum(probe: probe)
        case .playlistMP4:
            try await downloadPlaylist(probe: probe, asAudio: false)
        case .playlistMP3:
            try await downloadPlaylist(probe: probe, asAudio: true)
        }

        state = .finished
    }

    // MARK: – Single-video flows

    private func downloadSingleVideo(probe: ProbeResult, asAudio: Bool) async throws {
        let safe = Sanitize.filename(probe.title)
        let outDir = try mediaRoot.subfolder(named: asAudio ? safe : "Videos")
        let result = try await pythonDownload(
            outDir: outDir, audioOnly: asAudio, followPlaylist: false
        )
        guard let first = result.paths.first else {
            throw CoordinatorError.noFileProduced
        }
        let fileURL = URL(fileURLWithPath: first)

        state = .postProcessing(stage: "finishing")
        if asAudio {
            // Convert downloaded m4a/webm to mp3 192k.
            let mp3 = outDir.appendingPathComponent("\(safe).mp3")
            try FFmpegOps.extractMP3(input: fileURL, output: mp3)
            try? FileManager.default.removeItem(at: fileURL)

            let dur = (try? FFmpegOps.duration(of: mp3)) ?? probe.durationSec
            let album = Album(
                title: safe, sourceURL: probe.sourceURL,
                sourceKind: .single, coverRelPath: nil
            )
            context.insert(album)
            context.insert(Track(
                album: album,
                trackNumber: 1,
                title: safe,
                fileRelPath: relPath(of: mp3),
                durationSec: dur
            ))
        } else {
            let dur = (try? FFmpegOps.duration(of: fileURL)) ?? probe.durationSec
            context.insert(VideoItem(
                title: safe,
                sourceURL: probe.sourceURL,
                fileRelPath: relPath(of: fileURL),
                thumbnailRelPath: nil,
                durationSec: dur
            ))
        }
        try? context.save()
    }

    // MARK: – Chapter / autosplit album flows

    private func downloadChaptersAlbum(probe: ProbeResult) async throws {
        let safe = Sanitize.filename(probe.title)
        let outDir = try mediaRoot.subfolder(named: safe)
        let result = try await pythonDownload(
            outDir: outDir, audioOnly: true, followPlaylist: false
        )
        guard let raw = result.paths.first else { throw CoordinatorError.noFileProduced }
        let rawURL = URL(fileURLWithPath: raw)

        state = .postProcessing(stage: "converting")
        let fullMP3 = outDir.appendingPathComponent("\(safe).mp3")
        try FFmpegOps.extractMP3(input: rawURL, output: fullMP3)
        try? FileManager.default.removeItem(at: rawURL)

        state = .postProcessing(stage: "slicing chapters")
        let coverRel = try await maybeWriteThumbnail(
            url: probe.thumbnailURL, into: outDir, baseName: safe
        )

        let album = Album(
            title: safe, sourceURL: probe.sourceURL,
            sourceKind: .chapters, coverRelPath: coverRel
        )
        context.insert(album)

        for (i, chapter) in result.chapters.enumerated() {
            let chTitle = Sanitize.filename(chapter.title.isEmpty
                                            ? "Chapter \(i+1)" : chapter.title)
            let outName = String(
                format: "%03d%@_%@.mp3", i + 1, safe, chTitle
            )
            let outURL = outDir.appendingPathComponent(outName)
            try FFmpegOps.slice(
                input: fullMP3,
                start: chapter.startSec,
                end: chapter.endSec,
                output: outURL
            )
            context.insert(Track(
                album: album,
                trackNumber: i + 1,
                title: chTitle,
                fileRelPath: relPath(of: outURL),
                durationSec: chapter.endSec - chapter.startSec
            ))
        }
        try? FileManager.default.removeItem(at: fullMP3)
        try? context.save()
    }

    private func downloadAutosplitAlbum(probe: ProbeResult) async throws {
        let safe = Sanitize.filename(probe.title)
        let outDir = try mediaRoot.subfolder(named: safe)
        let result = try await pythonDownload(
            outDir: outDir, audioOnly: true, followPlaylist: false
        )
        guard let raw = result.paths.first else { throw CoordinatorError.noFileProduced }
        let rawURL = URL(fileURLWithPath: raw)

        state = .postProcessing(stage: "converting")
        let fullMP3 = outDir.appendingPathComponent("\(safe).mp3")
        try FFmpegOps.extractMP3(input: rawURL, output: fullMP3)
        try? FileManager.default.removeItem(at: rawURL)

        state = .postProcessing(stage: "detecting silence")
        let duration = (try? FFmpegOps.duration(of: fullMP3)) ?? probe.durationSec
        let coverRel = try await maybeWriteThumbnail(
            url: probe.thumbnailURL, into: outDir, baseName: safe
        )

        let trackNames = try SilenceSplitter.splitByGaps(
            mp3: fullMP3,
            outDir: outDir,
            baseName: safe,
            totalDuration: duration
        )

        let album = Album(
            title: safe, sourceURL: probe.sourceURL,
            sourceKind: trackNames.isEmpty ? .single : .autosplit,
            coverRelPath: coverRel
        )
        context.insert(album)

        if trackNames.isEmpty {
            // Fallback: keep the full file as a single track.
            context.insert(Track(
                album: album,
                trackNumber: 1,
                title: safe,
                fileRelPath: relPath(of: fullMP3),
                durationSec: duration
            ))
        } else {
            for (i, name) in trackNames.enumerated() {
                let trackURL = outDir.appendingPathComponent(name)
                let dur = (try? FFmpegOps.duration(of: trackURL)) ?? 0
                context.insert(Track(
                    album: album,
                    trackNumber: i + 1,
                    title: "Track \(i+1)",
                    fileRelPath: relPath(of: trackURL),
                    durationSec: dur
                ))
            }
            try? FileManager.default.removeItem(at: fullMP3)
        }
        try? context.save()
    }

    // MARK: – Playlist flow

    private func downloadPlaylist(probe: ProbeResult, asAudio: Bool) async throws {
        let safe = Sanitize.filename(probe.title)
        let outDir = try mediaRoot.subfolder(named: safe)
        let result = try await pythonDownload(
            outDir: outDir, audioOnly: asAudio, followPlaylist: true
        )

        if asAudio {
            let coverRel = try await maybeWriteThumbnail(
                url: probe.thumbnailURL, into: outDir, baseName: safe
            )
            let album = Album(
                title: safe, sourceURL: probe.sourceURL,
                sourceKind: .playlist, coverRelPath: coverRel
            )
            context.insert(album)

            // Convert each downloaded file to mp3 if it isn't already, and
            // assign a track number from the leading "NNN_" prefix.
            for (i, path) in result.paths.sorted().enumerated() {
                let src = URL(fileURLWithPath: path)
                let stem = src.deletingPathExtension().lastPathComponent
                let mp3 = outDir.appendingPathComponent("\(stem).mp3")
                if src.pathExtension.lowercased() != "mp3" {
                    try FFmpegOps.extractMP3(input: src, output: mp3)
                    try? FileManager.default.removeItem(at: src)
                }
                let dur = (try? FFmpegOps.duration(of: mp3)) ?? 0
                context.insert(Track(
                    album: album,
                    trackNumber: i + 1,
                    title: stem,
                    fileRelPath: relPath(of: mp3),
                    durationSec: dur
                ))
            }
        } else {
            // Each file becomes its own VideoItem.
            for path in result.paths {
                let fileURL = URL(fileURLWithPath: path)
                let dur = (try? FFmpegOps.duration(of: fileURL)) ?? 0
                context.insert(VideoItem(
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    sourceURL: probe.sourceURL,
                    fileRelPath: relPath(of: fileURL),
                    thumbnailRelPath: nil,
                    durationSec: dur
                ))
            }
        }
        try? context.save()
    }

    // MARK: – Helpers

    private func pythonDownload(
        outDir: URL, audioOnly: Bool, followPlaylist: Bool
    ) async throws -> PythonDownloadResult {
        state = .downloading(progress: 0)
        return try await Task.detached(priority: .userInitiated) {
            [url] in
            try PythonBridge.shared.run { mod in
                let dict = mod.download_raw(
                    url.absoluteString,
                    outDir.path,
                    audio_only: audioOnly,
                    follow_playlist: followPlaylist,
                    progress_cb: Python.None
                )
                // youtube_core wraps every response in an envelope — any
                // yt-dlp / network failure surfaces here as `ok: false`.
                if Bool(dict["ok"]) != true {
                    let msg = String(dict["error"]) ?? "Unknown download error"
                    throw YouTubeError(message: msg)
                }
                return PythonDownloadResult(dict: dict)
            }
        }.value
    }

    private func maybeWriteThumbnail(
        url: URL?, into dir: URL, baseName: String
    ) async throws -> String? {
        guard let url else { return nil }
        let dest = dir.appendingPathComponent("\(baseName).png")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Save raw then convert via ffmpeg-kit (handles webp/jpg → png).
            let tmp = dir.appendingPathComponent("\(baseName)_raw")
            try data.write(to: tmp)
            try FFmpegOps.convertImage(input: tmp, output: dest)
            try? FileManager.default.removeItem(at: tmp)
            return relPath(of: dest)
        } catch {
            return nil
        }
    }

    private func relPath(of file: URL) -> String {
        guard let root = mediaRoot.rootURL else { return file.lastPathComponent }
        let rootPath = root.path
        let filePath = file.path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return file.lastPathComponent
    }
}

// MARK: – Bridge helpers

private enum CoordinatorError: Error {
    case noFileProduced
}

/// Minimal Swift mirror of the dict returned by youtube_core.download_raw.
private struct PythonDownloadResult {
    let paths: [String]
    let title: String
    let chapters: [ChapterInfo]
    let duration: Double

    init(dict: PythonObject) {
        self.paths = Array(dict["paths"]).compactMap { String($0) }
        self.title = String(dict["title"]) ?? ""
        self.duration = Double(dict["duration"]) ?? 0
        self.chapters = Array(dict["chapters"]).map { ch in
            ChapterInfo(
                title: String(ch["title"]) ?? "",
                startSec: Double(ch["start_time"]) ?? 0,
                endSec: Double(ch["end_time"]) ?? 0
            )
        }
    }
}

private struct ChapterInfo {
    let title: String
    let startSec: Double
    let endSec: Double
}
