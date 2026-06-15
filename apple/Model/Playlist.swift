import Foundation
import SwiftData

/// A user-created collection of media items (videos, tracks, audiobooks) that can be played sequentially.
@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var descriptionText: String?
    var coverRelPath: String?          // Custom cover art or auto-generated
    var createdAt: Date
    var updatedAt: Date
    
    /// Total duration in seconds. Computed from all items.
    var totalDuration: TimeInterval = 0
    
    /// Play count for the entire playlist.
    var playCount: Int = 0
    var lastPlayedAt: Date?
    
    /// Whether this is a system-generated playlist (Recently Added, Favorites, etc.)
    var isSystemPlaylist: Bool = false
    
    /// Whether this playlist is shared with others.
    var isShared: Bool = false
    
    /// Share link identifier if this playlist is shared.
    var shareCode: String?
    
    /// Collaborative settings - encoded as JSON for flexibility.
    var collaborativeSettingsJSON: Data?
    
    /// Whether this is a smart playlist (has associated SmartPlaylist)
    var isSmartPlaylist: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \PlaylistItem.playlist)
    var items: [PlaylistItem] = []
    
    @Relationship(deleteRule: .cascade)
    var smartConfig: SmartPlaylist?
    
    init(
        id: UUID = UUID(),
        name: String,
        descriptionText: String? = nil,
        coverRelPath: String? = nil,
        createdAt: Date = .now,
        isSystemPlaylist: Bool = false
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.coverRelPath = coverRelPath
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isSystemPlaylist = isSystemPlaylist
    }
    
    /// Playlist items in user-defined order.
    var orderedItems: [PlaylistItem] {
        items.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    /// Count of items in the playlist.
    var itemCount: Int {
        items.count
    }
    
    /// Add a media item to the playlist.
    func addItem(_ item: PlaylistItem) {
        item.sortOrder = items.map(\.sortOrder).max().map { $0 + 1 } ?? 0
        items.append(item)
        updatedAt = .now
        recalculateDuration()
    }
    
    /// Remove an item from the playlist and reorder remaining items.
    func removeItem(_ item: PlaylistItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        
        // Reorder items after removal
        for (newIndex, item) in items.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            item.sortOrder = newIndex
        }
        
        updatedAt = .now
        recalculateDuration()
    }
    
    /// Recalculate total duration from all items.
    func recalculateDuration() {
        totalDuration = items.reduce(0) { $0 + $1.duration }
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

/// Collaborative playlist settings.
struct CollaborativeSettings: Codable {
    enum Permission: String, Codable {
        case viewOnly
        case canAdd
        case canEdit
        case canRemove
        case fullControl
    }
    
    var ownerID: String                    // User identifier
    var isPublic: Bool = false
    var allowComments: Bool = true
    var defaultPermission: Permission = .viewOnly
    var invitedUsers: [String: Permission] = [:] // User ID: Permission
    var activityFeed: [ActivityEntry] = []
    
    struct ActivityEntry: Codable, Identifiable {
        var id: UUID = UUID()
        var userID: String
        var action: String                  // "added track", "removed track", etc.
        var timestamp: Date
        var details: String?
    }
}
