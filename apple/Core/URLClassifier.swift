import Foundation

/// Where the user is adding a URL.
enum LibraryDestination: Equatable {
    case videos
    case music
    case audiobook
}

/// Result of probing a YouTube URL (the subset of yt-dlp's info we care about).
struct ProbeResult {
    let title: String
    let isPlaylist: Bool               // /playlist?list=… or top-level kind=playlist
    let entryCount: Int                // 1 for single video, N for playlist
    let chapterCount: Int              // 0 if no chapters
    let durationSec: Double            // 0 if unknown / playlist
    let thumbnailURL: URL?
    let sourceURL: URL
}

/// Choice the classifier emits. The download coordinator consumes this.
enum DownloadMode: Equatable {
    case singleVideoMP4
    case singleVideoMP3                // single track album (one mp3)
    case playlistMP4                   // many VideoItems
    case playlistMP3                   // one Album whose Tracks come from playlist entries
    case chaptersMP3                   // one Album whose Tracks come from chapter splits
    case autosplitMP3                  // one Album whose Tracks come from silence detection
    case ambiguousWatchAndList         // UI must prompt user
}

enum URLClassifier {

    /// Threshold below which we don't bother trying autosplit. Kept in sync
    /// with the plan ("20 min").
    static let autosplitMinDuration: TimeInterval = 20 * 60

    /// Minimum chapter count to treat a video as chaptered (avoid splitting
    /// videos with just an intro/outro chapter marker).
    static let minChapters: Int = 3

    static func classify(
        probe: ProbeResult,
        destination: LibraryDestination
    ) -> DownloadMode {
        let url = probe.sourceURL.absoluteString
        let isPlaylistOnly = Sanitize.isPlaylistOnlyURL(url)
        let isWatchWithList = Sanitize.isWatchWithList(url)

        switch destination {
        case .videos:
            // Videos: never auto-follow a playlist found alongside a video URL.
            if isPlaylistOnly { return .playlistMP4 }
            return .singleVideoMP4

        case .music:
            if isPlaylistOnly {
                return .playlistMP3
            }
            if isWatchWithList {
                // Genuinely ambiguous — the UI prompts.
                return .ambiguousWatchAndList
            }
            // Pure /watch?v=… URL.
            if probe.chapterCount >= minChapters {
                return .chaptersMP3
            }
            if probe.durationSec >= autosplitMinDuration {
                return .autosplitMP3
            }
            return .singleVideoMP3
            
        case .audiobook:
            // Audiobooks: prefer chapter-based or autosplit for long content
            if isPlaylistOnly {
                return .playlistMP3
            }
            if probe.chapterCount >= 1 {
                return .chaptersMP3
            }
            if probe.durationSec >= autosplitMinDuration {
                return .autosplitMP3
            }
            return .singleVideoMP3
        }
    }
}
