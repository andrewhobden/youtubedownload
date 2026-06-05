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

    @Relationship(deleteRule: .cascade, inverse: \Track.album)
    var tracks: [Track] = []

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL,
        sourceKind: AlbumSourceKind,
        coverRelPath: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourceKindRaw = sourceKind.rawValue
        self.coverRelPath = coverRelPath
        self.addedAt = addedAt
    }

    var sourceKind: AlbumSourceKind {
        AlbumSourceKind(rawValue: sourceKindRaw) ?? .single
    }

    /// Tracks in playback order.
    var orderedTracks: [Track] {
        tracks.sorted { $0.trackNumber < $1.trackNumber }
    }

    @MainActor func coverURL(in root: MediaRoot) -> URL? {
        guard let rel = coverRelPath else { return nil }
        return root.resolve(rel)
    }
}
