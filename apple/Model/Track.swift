import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var album: Album?
    var audiobook: Audiobook?
    var trackNumber: Int               // 1-based
    var title: String
    var fileRelPath: String
    var durationSec: Double
    
    // Metadata enrichment fields
    var artist: String?
    var genre: String?
    var year: Int?
    var rating: Int?                   // 0-5 stars
    var tagsRaw: String?               // Comma-separated tags
    var lyricsRelPath: String?         // Path to lyrics/subtitle file
    var playCount: Int = 0
    var lastPlayedAt: Date?

    init(
        id: UUID = UUID(),
        album: Album? = nil,
        audiobook: Audiobook? = nil,
        trackNumber: Int,
        title: String,
        fileRelPath: String,
        durationSec: Double,
        artist: String? = nil,
        genre: String? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.album = album
        self.audiobook = audiobook
        self.trackNumber = trackNumber
        self.title = title
        self.fileRelPath = fileRelPath
        self.durationSec = durationSec
        self.artist = artist
        self.genre = genre
        self.year = year
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

    @MainActor func fileURL(in root: MediaRoot) -> URL? {
        root.resolve(fileRelPath)
    }
    
    @MainActor func lyricsURL(in root: MediaRoot) -> URL? {
        guard let rel = lyricsRelPath else { return nil }
        return root.resolve(rel)
    }
    
    /// Increment play count and update last played timestamp.
    func recordPlay() {
        playCount += 1
        lastPlayedAt = .now
    }
}
