import Foundation
import SwiftData

/// Backfills cover art for `Album`s that were downloaded before music
/// single-video downloads saved a cover. Uses YouTube's predictable thumbnail
/// URL (derived from the album's source URL) so no metadata probe is needed,
/// then stores the image next to the album's tracks and sets `coverRelPath`.
///
/// Safe to call repeatedly: it only touches albums whose `coverRelPath` is nil
/// and whose source is a recognisable YouTube video, and it no-ops once the
/// cover exists on disk.
enum CoverArtBackfill {

    @MainActor
    static func run(context: ModelContext, mediaRoot: MediaRoot) async {
        guard mediaRoot.rootURL != nil else { return }

        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.coverRelPath == nil }
        )
        guard let albums = try? context.fetch(descriptor), !albums.isEmpty else { return }

        var didChange = false
        for album in albums {
            guard let videoID = YouTubeThumbnail.videoID(from: album.sourceURL),
                  let folderRel = albumFolderRel(for: album) else { continue }

            let rel = "\(folderRel)/cover.jpg"
            guard let dest = mediaRoot.resolve(rel) else { continue }

            // Already on disk (e.g. a prior partial run) — just relink.
            if FileManager.default.fileExists(atPath: dest.path) {
                album.coverRelPath = rel
                didChange = true
                continue
            }

            guard let src = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") else {
                continue
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: src)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) { continue }
                guard !data.isEmpty else { continue }
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: dest)
                album.coverRelPath = rel
                didChange = true
            } catch {
                continue
            }
        }
        if didChange { try? context.save() }
    }

    /// Relative folder of an album, derived from its first track's file path.
    @MainActor
    private static func albumFolderRel(for album: Album) -> String? {
        guard let trackRel = album.orderedTracks.first?.fileRelPath else { return nil }
        let dir = (trackRel as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }
}

/// Extracts a YouTube video ID from the common URL shapes we store.
enum YouTubeThumbnail {
    static func videoID(from url: URL) -> String? {
        if url.host?.contains("youtu.be") == true {
            let id = url.lastPathComponent
            return id.isEmpty || id == "/" ? nil : id
        }
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
           !v.isEmpty {
            return v
        }
        let parts = url.pathComponents
        if let idx = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "v" }),
           idx + 1 < parts.count {
            return parts[idx + 1]
        }
        return nil
    }
}
