import Foundation
import SwiftData
import PythonKit
import os.log

private let coordLog = Logger(subsystem: "com.anhobden.youtubelibrary", category: "DownloadCoordinator")

/// State of a single download job.
enum DownloadJobState: Equatable {
    case queued
    case probing
    case downloading(progress: Double)         // 0…1
    case paused(progress: Double)              // yielded to a foreground search
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
    /// Set by `requestResume()` to break a paused download out of its wait
    /// immediately (manual restart).
    private var forceResumeRequested = false

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
            try await FFmpegOps.extractMP3Async(input: fileURL, output: mp3)
            try? FileManager.default.removeItem(at: fileURL)

            let dur = (try? await FFmpegOps.durationAsync(of: mp3)) ?? probe.durationSec
            // Save the video thumbnail as the album / audiobook cover art.
            let coverRel = try? await maybeWriteThumbnail(
                url: probe.thumbnailURL, into: outDir, baseName: safe
            )
            let container = makeContainer(
                title: safe, sourceURL: probe.sourceURL,
                sourceKind: .single, coverRelPath: coverRel
            )
            let track = container.makeTrack(
                trackNumber: 1, title: safe,
                fileRelPath: relPath(of: mp3), durationSec: dur
            )
            context.insert(track)
            container.append(track)
            container.finalize()
        } else {
            let dur = (try? await FFmpegOps.durationAsync(of: fileURL)) ?? probe.durationSec
            let thumbRel = try? await maybeWriteThumbnail(
                url: probe.thumbnailURL, into: outDir, baseName: safe
            )
            context.insert(VideoItem(
                title: safe,
                sourceURL: probe.sourceURL,
                fileRelPath: relPath(of: fileURL),
                thumbnailRelPath: thumbRel,
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
        try await FFmpegOps.extractMP3Async(input: rawURL, output: fullMP3)
        try? FileManager.default.removeItem(at: rawURL)

        state = .postProcessing(stage: "slicing chapters")
        let coverRel = try await maybeWriteThumbnail(
            url: probe.thumbnailURL, into: outDir, baseName: safe
        )

        let container = makeContainer(
            title: safe, sourceURL: probe.sourceURL,
            sourceKind: .chapters, coverRelPath: coverRel
        )

        var sliced = 0
        var failed: [Int] = []
        for (i, chapter) in result.chapters.enumerated() {
            let chTitle = Sanitize.filename(chapter.title.isEmpty
                                            ? "Chapter \(i+1)" : chapter.title)
            let outName = String(
                format: "%03d%@_%@.mp3", i + 1, safe, chTitle
            )
            let outURL = outDir.appendingPathComponent(outName)
            let accepted = await Self.sliceChapterAccepting(
                input: fullMP3,
                start: chapter.startSec,
                end: chapter.endSec,
                output: outURL,
                index: i + 1
            )
            if !accepted {
                failed.append(i + 1)
                continue
            }
            // Insert the track explicitly on both sides of the relationship
            // and save now — SwiftData's inverse auto-population is flaky
            // for back-to-back inserts and we've seen tracks created with a
            // nil parent, which makes them invisible in the detail view.
            let track = container.makeTrack(
                trackNumber: i + 1,
                title: chTitle,
                fileRelPath: relPath(of: outURL),
                durationSec: chapter.endSec - chapter.startSec
            )
            context.insert(track)
            container.append(track)
            do { try context.save() } catch {
                coordLog.error("Chapter \(i+1) context.save failed: \(String(describing: error), privacy: .public)")
            }
            sliced += 1
        }
        if sliced == 0 {
            throw CoordinatorError.noFileProduced
        }
        if !failed.isEmpty {
            coordLog.notice("ChaptersAlbum: \(failed.count) chapter(s) failed: \(failed.map(String.init).joined(separator: ","), privacy: .public)")
        }
        container.finalize()
        try? context.save()
        try? FileManager.default.removeItem(at: fullMP3)
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
        try await FFmpegOps.extractMP3Async(input: rawURL, output: fullMP3)
        try? FileManager.default.removeItem(at: rawURL)

        state = .postProcessing(stage: "detecting silence")
        let duration = (try? await FFmpegOps.durationAsync(of: fullMP3)) ?? probe.durationSec
        let coverRel = try await maybeWriteThumbnail(
            url: probe.thumbnailURL, into: outDir, baseName: safe
        )

        let trackNames = try await SilenceSplitter.splitByGapsAsync(
            mp3: fullMP3,
            outDir: outDir,
            baseName: safe,
            totalDuration: duration
        )

        let container = makeContainer(
            title: safe, sourceURL: probe.sourceURL,
            sourceKind: trackNames.isEmpty ? .single : .autosplit,
            coverRelPath: coverRel
        )

        if trackNames.isEmpty {
            // Fallback: keep the full file as a single track.
            let track = container.makeTrack(
                trackNumber: 1, title: safe,
                fileRelPath: relPath(of: fullMP3), durationSec: duration
            )
            context.insert(track)
            container.append(track)
        } else {
            for (i, name) in trackNames.enumerated() {
                let trackURL = outDir.appendingPathComponent(name)
                let dur = (try? await FFmpegOps.durationAsync(of: trackURL)) ?? 0
                let track = container.makeTrack(
                    trackNumber: i + 1, title: "Track \(i+1)",
                    fileRelPath: relPath(of: trackURL), durationSec: dur
                )
                context.insert(track)
                container.append(track)
            }
            try? FileManager.default.removeItem(at: fullMP3)
        }
        container.finalize()
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
            let container = makeContainer(
                title: safe, sourceURL: probe.sourceURL,
                sourceKind: .playlist, coverRelPath: coverRel
            )

            // Convert each downloaded file to mp3 if it isn't already, and
            // assign a track number from the leading "NNN_" prefix.
            for (i, path) in result.paths.sorted().enumerated() {
                let src = URL(fileURLWithPath: path)
                let stem = src.deletingPathExtension().lastPathComponent
                let mp3 = outDir.appendingPathComponent("\(stem).mp3")
                if src.pathExtension.lowercased() != "mp3" {
                    try await FFmpegOps.extractMP3Async(input: src, output: mp3)
                    try? FileManager.default.removeItem(at: src)
                }
                let dur = (try? await FFmpegOps.durationAsync(of: mp3)) ?? 0
                let track = container.makeTrack(
                    trackNumber: i + 1, title: stem,
                    fileRelPath: relPath(of: mp3), durationSec: dur
                )
                context.insert(track)
                container.append(track)
            }
            container.finalize()
        } else {
            // Each file becomes its own VideoItem.
            for path in result.paths {
                let fileURL = URL(fileURLWithPath: path)
                let dur = (try? await FFmpegOps.durationAsync(of: fileURL)) ?? 0
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

    /// Create the destination container for an audio download, routing to the
    /// Audiobooks section when requested and Music (Album) otherwise.
    private func makeContainer(
        title: String,
        sourceURL: URL,
        sourceKind: AlbumSourceKind,
        coverRelPath: String?
    ) -> AudioContainer {
        if destination == .audiobook {
            let book = Audiobook(
                title: title, sourceURL: sourceURL,
                sourceKind: sourceKind, coverRelPath: coverRelPath
            )
            context.insert(book)
            return .audiobook(book)
        } else {
            let album = Album(
                title: title, sourceURL: sourceURL,
                sourceKind: sourceKind, coverRelPath: coverRelPath
            )
            context.insert(album)
            return .album(album)
        }
    }

    /// Slice one chapter off the main thread, with the flaky-return-code
    /// retry (FFmpegKit sometimes reports a non-success code before the file
    /// is flushed). Waits up to ~3s for the output file to appear. Returns
    /// true if the file is present afterward. `static` so the off-main work
    /// captures no actor-isolated state.
    private static func sliceChapterAccepting(
        input: URL, start: Double, end: Double, output: URL, index: Int
    ) async -> Bool {
        let path = output.path
        let result = try? await FFmpegOps.runDetached { () -> Bool in
            do {
                try FFmpegOps.slice(input: input, start: start, end: end, output: output)
                return true
            } catch {
                let fm = FileManager.default
                for _ in 0..<30 {
                    if fm.fileExists(atPath: path) {
                        coordLog.info("Chapter \(index) reported error but file is present, accepting")
                        return true
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                coordLog.error("Chapter \(index) slice failed (no output file at \(path, privacy: .public)): \(String(describing: error), privacy: .public)")
                return false
            }
        }
        return result ?? false
    }

    private func pythonDownload(
        outDir: URL, audioOnly: Bool, followPlaylist: Bool
    ) async throws -> PythonDownloadResult {
        // Files present before the FIRST attempt. Passed to youtube_core on
        // every (including resumed) call so already-completed files survive a
        // pause/resume cycle and aren't dropped from the produced list.
        let baseline = Self.existingFilePaths(in: outDir)
        let progress = ProgressHolder()
        let cookieFile = YouTubeAuth.currentCookieFilePath()

        while true {
            state = .downloading(progress: progress.fraction)

            // Reflect live transfer progress on the UI while the (blocking)
            // download runs on the Python thread.
            let poller = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self, !Task.isCancelled else { break }
                    if case .downloading = self.state {
                        self.state = .downloading(progress: progress.fraction)
                    }
                }
            }

            let result: PythonDownloadResult
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    [url, cookieFile] in
                    try PythonBridge.shared.run { mod in
                        // Abort the transfer when a foreground search needs the
                        // shared Python thread (read on the Python thread here).
                        let shouldPause = PythonFunction { (_: [PythonObject]) in
                            PythonWorkArbiter.shared.isForegroundActive
                        }.pythonObject
                        let progressCb = PythonFunction { (args: [PythonObject]) -> PythonConvertible in
                            if args.count >= 3 {
                                progress.update(
                                    downloaded: Double(args[1]) ?? 0,
                                    total: Double(args[2]) ?? 0
                                )
                            }
                            return Python.None
                        }.pythonObject

                        let dict = mod.download_raw(
                            url.absoluteString,
                            outDir.path,
                            audio_only: audioOnly,
                            follow_playlist: followPlaylist,
                            progress_cb: progressCb,
                            should_pause: shouldPause,
                            baseline_paths: baseline,
                            cookiefile: cookieFile
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
            } catch {
                poller.cancel()
                throw error
            }
            poller.cancel()

            if result.paused {
                // Self-healing wait: resume once no foreground search needs the
                // Python thread (a stale/leaked foreground flag auto-expires via
                // isForegroundActive), or immediately when the user taps restart.
                // This never parks forever, so a download can't get stuck paused.
                state = .paused(progress: progress.fraction)
                while PythonWorkArbiter.shared.isForegroundActive && !forceResumeRequested {
                    try? await Task.sleep(for: .seconds(1))
                }
                forceResumeRequested = false
                continue
            }
            return result
        }
    }

    /// Break a paused download out of its wait so it resumes now (manual restart).
    func requestResume() {
        forceResumeRequested = true
    }

    /// Absolute paths of the files currently in `dir` (used as the produced-file
    /// baseline so resumes don't drop earlier-completed files).
    private static func existingFilePaths(in dir: URL) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.compactMap { name in
            let full = dir.appendingPathComponent(name).path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { return nil }
            return full
        }
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
            try await FFmpegOps.convertImageAsync(input: tmp, output: dest)
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

/// Target library section for an audio download — a music `Album` or an
/// `Audiobook`. Lets the single / chapter / autosplit / playlist audio flows
/// write to the correct section based on the chosen `LibraryDestination`.
private enum AudioContainer {
    case album(Album)
    case audiobook(Audiobook)

    /// Build a `Track` wired to the correct parent relationship.
    func makeTrack(
        trackNumber: Int, title: String,
        fileRelPath: String, durationSec: Double
    ) -> Track {
        switch self {
        case .album(let album):
            return Track(album: album, trackNumber: trackNumber,
                         title: title, fileRelPath: fileRelPath, durationSec: durationSec)
        case .audiobook(let book):
            return Track(audiobook: book, trackNumber: trackNumber,
                         title: title, fileRelPath: fileRelPath, durationSec: durationSec)
        }
    }

    /// Explicitly append to the parent's tracks. SwiftData's inverse
    /// population is unreliable for back-to-back inserts (see chapter flow).
    func append(_ track: Track) {
        switch self {
        case .album(let album): album.tracks.append(track)
        case .audiobook(let book): book.tracks.append(track)
        }
    }

    /// Roll up total duration (drives the audiobook progress UI; no-op for albums).
    func finalize() {
        if case .audiobook(let book) = self {
            book.totalDuration = book.tracks.reduce(0) { $0 + $1.durationSec }
        }
    }
}

/// Minimal Swift mirror of the dict returned by youtube_core.download_raw.
private struct PythonDownloadResult {
    let paths: [String]
    let title: String
    let chapters: [ChapterInfo]
    let duration: Double
    let paused: Bool

    init(dict: PythonObject) {
        self.paths = Array(dict["paths"]).compactMap { String($0) }
        self.title = String(dict["title"]) ?? ""
        self.duration = Double(dict["duration"]) ?? 0
        self.paused = Bool(dict["paused"]) ?? false
        self.chapters = Array(dict["chapters"]).map { ch in
            ChapterInfo(
                title: String(ch["title"]) ?? "",
                startSec: Double(ch["start_time"]) ?? 0,
                endSec: Double(ch["end_time"]) ?? 0
            )
        }
    }
}

/// Thread-safe holder for live download progress. Written from the yt-dlp
/// progress hook (Python thread) and read from the UI poller (main actor).
private final class ProgressHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _fraction: Double = 0

    var fraction: Double {
        lock.lock(); defer { lock.unlock() }
        return _fraction
    }

    func update(downloaded: Double, total: Double) {
        guard total > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        _fraction = min(1, max(0, downloaded / total))
    }
}

private struct ChapterInfo {
    let title: String
    let startSec: Double
    let endSec: Double
}
