import Foundation
import SwiftData

@Model
final class VideoItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceURL: URL
    var fileRelPath: String
    var thumbnailRelPath: String?
    var durationSec: Double
    var addedAt: Date
    
    // Metadata enrichment fields
    var creator: String?               // Channel/creator name
    var genre: String?
    var year: Int?
    var rating: Int?                   // 0-5 stars
    var tagsRaw: String?               // Comma-separated tags
    var subtitleRelPath: String?       // Path to subtitle/caption file
    var playCount: Int = 0
    var lastPlayedAt: Date?
    var lastPosition: TimeInterval = 0 // Resume position for videos

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL,
        fileRelPath: String,
        thumbnailRelPath: String? = nil,
        durationSec: Double,
        addedAt: Date = .now,
        creator: String? = nil,
        genre: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.fileRelPath = fileRelPath
        self.thumbnailRelPath = thumbnailRelPath
        self.durationSec = durationSec
        self.addedAt = addedAt
        self.creator = creator
        self.genre = genre
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

    /// Absolute on-disk URL for the video file, resolved against the current
    /// MediaRoot. Returns nil if MediaRoot is unavailable (e.g. Catalyst with
    /// no folder picked yet).
    @MainActor func fileURL(in root: MediaRoot) -> URL? {
        root.resolve(fileRelPath)
    }

    @MainActor func thumbnailURL(in root: MediaRoot) -> URL? {
        guard let rel = thumbnailRelPath else { return nil }
        return root.resolve(rel)
    }
    
    @MainActor func subtitleURL(in root: MediaRoot) -> URL? {
        guard let rel = subtitleRelPath else { return nil }
        return root.resolve(rel)
    }
}
