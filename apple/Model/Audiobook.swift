import Foundation
import SwiftData

/// Chapter information for audiobooks, typically extracted from video chapters
/// or generated via silence splitting.
struct AudiobookChapter: Codable, Identifiable {
    var id: UUID = UUID()
    var number: Int                    // 1-based
    var title: String
    var startTime: TimeInterval
    var duration: TimeInterval
    
    var endTime: TimeInterval {
        startTime + duration
    }
}

@Model
final class Audiobook {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String?
    var narrator: String?
    var sourceURL: URL
    var sourceKindRaw: String          // AlbumSourceKind.rawValue for compatibility
    var coverRelPath: String?
    var addedAt: Date
    
    /// Chapters encoded as JSON for SwiftData storage.
    /// Use `chapters` computed property to access as typed array.
    var chaptersJSON: Data?
    
    /// Current playback position in seconds. Updated automatically during playback.
    var currentPosition: TimeInterval = 0
    
    /// Playback speed multiplier (0.5x to 2.5x typical range).
    var playbackSpeed: Double = 1.0
    
    /// Completion percentage (0.0 to 1.0). Calculated from currentPosition/totalDuration.
    var completionPercentage: Double = 0.0
    
    /// Play count for tracking listening history.
    var playCount: Int = 0
    
    /// Whether this audiobook has been marked as finished.
    var isFinished: Bool = false
    
    /// Total duration in seconds. Sum of all track durations.
    var totalDuration: TimeInterval = 0
    
    /// Date when the user last listened to this audiobook.
    var lastPlayedAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \Track.audiobook)
    var tracks: [Track] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Bookmark.audiobook)
    var bookmarks: [Bookmark] = []
    
    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        narrator: String? = nil,
        sourceURL: URL,
        sourceKind: AlbumSourceKind,
        coverRelPath: String? = nil,
        totalDuration: TimeInterval = 0,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.narrator = narrator
        self.sourceURL = sourceURL
        self.sourceKindRaw = sourceKind.rawValue
        self.coverRelPath = coverRelPath
        self.totalDuration = totalDuration
        self.addedAt = addedAt
    }
    
    var sourceKind: AlbumSourceKind {
        AlbumSourceKind(rawValue: sourceKindRaw) ?? .single
    }
    
    /// Tracks in playback order.
    var orderedTracks: [Track] {
        tracks.sorted { $0.trackNumber < $1.trackNumber }
    }
    
    /// Bookmarks sorted by timestamp for chronological navigation.
    var orderedBookmarks: [Bookmark] {
        bookmarks.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Decoded chapters from JSON storage.
    var chapters: [AudiobookChapter] {
        get {
            guard let data = chaptersJSON else { return [] }
            return (try? JSONDecoder().decode([AudiobookChapter].self, from: data)) ?? []
        }
        set {
            chaptersJSON = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Find which chapter contains the given timestamp.
    func chapter(at timestamp: TimeInterval) -> AudiobookChapter? {
        chapters.first { chapter in
            timestamp >= chapter.startTime && timestamp < chapter.endTime
        }
    }
    
    /// Update completion percentage based on current position.
    func updateCompletion() {
        guard totalDuration > 0 else {
            completionPercentage = 0
            return
        }
        completionPercentage = min(max(currentPosition / totalDuration, 0), 1)
        
        // Auto-mark as finished if user has listened to 95% or more
        if completionPercentage >= 0.95 {
            isFinished = true
        }
    }
    
    @MainActor func coverURL(in root: MediaRoot) -> URL? {
        guard let rel = coverRelPath else { return nil }
        return root.resolve(rel)
    }
}
