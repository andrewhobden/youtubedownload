import Foundation
import PythonKit

struct YouTubeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Typed Swift API over `youtube_core.probe`. Always probes flat (does not
/// resolve every playlist entry) so it stays fast.
enum YouTubeProbe {

    static func probe(_ url: URL) throws -> ProbeResult {
        let cookieFile = YouTubeAuth.currentCookieFilePath()
        return try PythonBridge.shared.run { mod in
            let followPlaylist = Sanitize.isPlaylistOnlyURL(url.absoluteString)
            let raw = mod.probe(url.absoluteString,
                                follow_playlist: followPlaylist,
                                cookiefile: cookieFile)

            // The Python layer wraps every result in an envelope so any
            // yt-dlp exception is reported as data, not a Python exception
            // (which would crash PythonKit's non-throwing call site).
            if Bool(raw["ok"]) != true {
                let msg = String(raw["error"]) ?? "Unknown probe error"
                throw YouTubeError(message: msg)
            }

            let title = String(raw["title"]) ?? "Unknown"
            let isPlaylist = Bool(raw["is_playlist"]) ?? false
            let entryCount = Int(raw["entry_count"]) ?? 1
            let chapterCount = Int(raw["chapter_count"]) ?? 0
            let durationSec = Double(raw["duration"]) ?? 0
            let thumb = String(raw["thumbnail"]) ?? ""
            let thumbURL = thumb.isEmpty ? nil : URL(string: thumb)

            return ProbeResult(
                title: title,
                isPlaylist: isPlaylist,
                entryCount: entryCount,
                chapterCount: chapterCount,
                durationSec: durationSec,
                thumbnailURL: thumbURL,
                sourceURL: url
            )
        }
    }
}
