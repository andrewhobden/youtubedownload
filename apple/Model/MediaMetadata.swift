import Foundation

/// Protocol for media items that support common metadata operations.
protocol MediaMetadata {
    var title: String { get set }
    var genre: String? { get set }
    var rating: Int? { get set }
    var tagsRaw: String? { get set }
    var playCount: Int { get set }
    var lastPlayedAt: Date? { get set }
    var addedAt: Date { get }
    var durationSec: TimeInterval { get }
    
    var tags: [String] { get set }
    func recordPlay()
}

/// Shared metadata operations extension
extension MediaMetadata {
    /// Check if this item has a specific tag.
    func hasTag(_ tag: String) -> Bool {
        tags.contains { $0.lowercased() == tag.lowercased() }
    }
    
    /// Add a tag if it doesn't already exist.
    mutating func addTag(_ tag: String) {
        let normalized = tag.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, !hasTag(normalized) else { return }
        var currentTags = tags
        currentTags.append(normalized)
        tags = currentTags
    }
    
    /// Remove a tag if it exists.
    mutating func removeTag(_ tag: String) {
        tags = tags.filter { $0.lowercased() != tag.lowercased() }
    }
    
    /// Format duration as human-readable string.
    var formattedDuration: String {
        let hours = Int(durationSec) / 3600
        let minutes = (Int(durationSec) % 3600) / 60
        let seconds = Int(durationSec) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Check if this item was recently added (within last 7 days).
    var isRecentlyAdded: Bool {
        guard let daysAgo = Calendar.current.dateComponents([.day], from: addedAt, to: .now).day else {
            return false
        }
        return daysAgo <= 7
    }
    
    /// Check if this item was recently played (within last 24 hours).
    var isRecentlyPlayed: Bool {
        guard let lastPlayed = lastPlayedAt,
              let hoursAgo = Calendar.current.dateComponents([.hour], from: lastPlayed, to: .now).hour else {
            return false
        }
        return hoursAgo <= 24
    }
}

/// Protocol for media items with album art/thumbnails.
protocol MediaArtwork {
    var coverRelPath: String? { get set }
    var thumbnailRelPath: String? { get set }
    
    @MainActor func coverURL(in root: MediaRoot) -> URL?
    @MainActor func thumbnailURL(in root: MediaRoot) -> URL?
}

/// Protocol for media items with artist/creator information.
protocol MediaCreator {
    var artist: String? { get set }
    var creator: String? { get set }
    
    var displayCreator: String? { get }
}

extension MediaCreator {
    var displayCreator: String? {
        if let artist = self as? any MediaArtist {
            return artist.artist
        }
        if let creator = self as? any MediaVideoCreator {
            return creator.creator
        }
        return nil
    }
}

// Type-specific protocols to avoid ambiguity
protocol MediaArtist {
    var artist: String? { get set }
}

protocol MediaVideoCreator {
    var creator: String? { get set }
}
