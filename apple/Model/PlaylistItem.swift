import Foundation
import SwiftData

/// Join model linking playlists to media items with ordering and custom metadata.
@Model
final class PlaylistItem {
    @Attribute(.unique) var id: UUID
    var playlist: Playlist?
    var sortOrder: Int                     // Position in playlist (0-based)
    var addedAt: Date
    var addedBy: String?                   // User identifier for collaborative playlists
    
    // Polymorphic reference to the actual media item
    // Only one of these will be non-nil
    var videoItemID: UUID?
    var albumID: UUID?
    var trackID: UUID?
    var audiobookID: UUID?
    
    // Cached metadata for performance (avoid joins when displaying playlist)
    var title: String
    var duration: TimeInterval
    var thumbnailRelPath: String?
    
    // Custom metadata per playlist item
    var note: String?                      // User note about why this was added
    
    init(
        id: UUID = UUID(),
        playlist: Playlist? = nil,
        sortOrder: Int = 0,
        title: String,
        duration: TimeInterval,
        thumbnailRelPath: String? = nil,
        addedAt: Date = .now,
        addedBy: String? = nil
    ) {
        self.id = id
        self.playlist = playlist
        self.sortOrder = sortOrder
        self.title = title
        self.duration = duration
        self.thumbnailRelPath = thumbnailRelPath
        self.addedAt = addedAt
        self.addedBy = addedBy
    }
    
    @MainActor func thumbnailURL(in root: MediaRoot) -> URL? {
        guard let rel = thumbnailRelPath else { return nil }
        return root.resolve(rel)
    }
}

// MARK: - Playlist Item Creation Helpers

extension PlaylistItem {
    /// Create a playlist item from a VideoItem.
    static func from(video: VideoItem) -> PlaylistItem {
        let item = PlaylistItem(
            title: video.title,
            duration: video.durationSec,
            thumbnailRelPath: video.thumbnailRelPath
        )
        item.videoItemID = video.id
        return item
    }
    
    /// Create a playlist item from an Album.
    static func from(album: Album) -> PlaylistItem {
        let totalDuration = album.tracks.reduce(0) { $0 + $1.durationSec }
        let item = PlaylistItem(
            title: album.title,
            duration: totalDuration,
            thumbnailRelPath: album.coverRelPath
        )
        item.albumID = album.id
        return item
    }
    
    /// Create a playlist item from a Track.
    static func from(track: Track) -> PlaylistItem {
        let item = PlaylistItem(
            title: track.title,
            duration: track.durationSec,
            thumbnailRelPath: track.album?.coverRelPath
        )
        item.trackID = track.id
        return item
    }
    
    /// Create a playlist item from an Audiobook.
    static func from(audiobook: Audiobook) -> PlaylistItem {
        let item = PlaylistItem(
            title: audiobook.title,
            duration: audiobook.totalDuration,
            thumbnailRelPath: audiobook.coverRelPath
        )
        item.audiobookID = audiobook.id
        return item
    }
}
