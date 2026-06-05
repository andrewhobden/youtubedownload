import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var album: Album?
    var trackNumber: Int               // 1-based
    var title: String
    var fileRelPath: String
    var durationSec: Double

    init(
        id: UUID = UUID(),
        album: Album? = nil,
        trackNumber: Int,
        title: String,
        fileRelPath: String,
        durationSec: Double
    ) {
        self.id = id
        self.album = album
        self.trackNumber = trackNumber
        self.title = title
        self.fileRelPath = fileRelPath
        self.durationSec = durationSec
    }

    @MainActor func fileURL(in root: MediaRoot) -> URL? {
        root.resolve(fileRelPath)
    }
}
