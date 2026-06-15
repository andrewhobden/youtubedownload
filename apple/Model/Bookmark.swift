import Foundation
import SwiftData

/// Represents a user-created bookmark within an audiobook for quick navigation
/// to important moments or to remember where they left off.
@Model
final class Bookmark {
    @Attribute(.unique) var id: UUID
    var audiobook: Audiobook?
    var timestamp: TimeInterval
    var title: String
    var note: String?
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        audiobook: Audiobook? = nil,
        timestamp: TimeInterval,
        title: String,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.audiobook = audiobook
        self.timestamp = timestamp
        self.title = title
        self.note = note
        self.createdAt = createdAt
    }
    
    /// Formatted timestamp for display (e.g., "1:23:45")
    var formattedTimestamp: String {
        let hours = Int(timestamp) / 3600
        let minutes = (Int(timestamp) % 3600) / 60
        let seconds = Int(timestamp) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
