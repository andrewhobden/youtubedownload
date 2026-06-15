import Foundation
import SwiftData

enum AlbumSourceKind: String, Codable, CaseIterable {
    case single
    case chapters
    case playlist
    case autosplit
}

@Model
final class Album {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceURL: URL
    var sourceKindRaw: String          // AlbumSourceKind.rawValue
    var coverRelPath: String?
    var addedAt: Date
    
    // Metadata enrichment fields
    var artist: String?
    var genre: String?
    var year: Int?
    var rating: Int?                   // 0-5 stars
    var tagsRaw: String?               // Comma-separated tags
    var playCount: Int = 0
    var lastPlayedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Track.album)
    var tracks: [Track] = []

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL,
        sourceKind: AlbumSourceKind,
        coverRelPath: String? = nil,
        addedAt: Date = .now,
        artist: String? = nil,
        genre: String? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourceKindRaw = sourceKind.rawValue
        self.coverRelPath = coverRelPath
        self.addedAt = addedAt
        self.artist = artist
        self.genre = genre
        self.year = year
    }

    var sourceKind: AlbumSourceKind {
        AlbumSourceKind(rawValue: sourceKindRaw) ?? .single
    }

    /// Tracks in playback order.
    var orderedTracks: [Track] {
        tracks.sorted { $0.trackNumber < $1.trackNumber }
    }
    
    var tags: [String] {
        get {
            guard let raw = tagsRaw, !raw.isEmpty else { return [] }
            return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        set {
            tagsRaw = newValue.isEmpty ? nil : newValue.joined(separator: ", ")
        }
    }
    
    /// Increment play count and update last played timestamp.
    func recordPlay() {
        playCount += 1
        lastPlayedAt = .now
    }

    @MainActor func coverURL(in root: MediaRoot) -> URL? {
        guard let rel = coverRelPath else { return nil }
        return root.resolve(rel)
    }
}
