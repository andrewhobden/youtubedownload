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

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL,
        fileRelPath: String,
        thumbnailRelPath: String? = nil,
        durationSec: Double,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.fileRelPath = fileRelPath
        self.thumbnailRelPath = thumbnailRelPath
        self.durationSec = durationSec
        self.addedAt = addedAt
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
}
