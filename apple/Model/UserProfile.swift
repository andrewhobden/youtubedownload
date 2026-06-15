import Foundation
import SwiftData

/// User profile and preferences for the application.
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    
    // Playback Preferences
    var defaultPlaybackSpeed: Double = 1.0          // Default for audiobooks/videos
    var defaultAudioQuality: String = "high"        // low, medium, high
    var defaultVideoQuality: String = "1080p"       // 720p, 1080p, 4k
    var autoPlayNext: Bool = true
    var crossfadeDuration: TimeInterval = 0         // Seconds of crossfade between tracks
    var skipForwardSeconds: Int = 15                // Jump forward duration
    var skipBackwardSeconds: Int = 15               // Jump backward duration
    
    // Theme Preferences
    var accentColorHex: String? = nil               // Custom accent color, nil = system
    var useSystemTheme: Bool = true                  // Follow system dark/light mode
    var forceDarkMode: Bool = false
    var useOLEDBlack: Bool = false                  // Pure black for OLED displays
    
    // Library Organization
    var defaultSortOrder: String = "dateAddedDesc"  // See MediaSort enum
    var defaultViewStyle: String = "grid"           // list, grid, compact
    var showEmptyCollections: Bool = false
    var groupByGenre: Bool = false
    var groupByArtist: Bool = false
    
    // Download & Storage
    var downloadOnlyOnWiFi: Bool = true
    var autoDownloadQuality: String = "medium"
    var maxStorageGB: Int = 0                       // 0 = unlimited
    var deleteWatchedVideos: Bool = false
    var deleteAfterDays: Int = 0                    // 0 = never
    
    // Privacy & Social
    var shareListeningActivity: Bool = false
    var allowFriendRequests: Bool = false
    var showOnlineStatus: Bool = false
    var dataCollectionOptIn: Bool = false
    
    // Notifications
    var notifyDownloadComplete: Bool = true
    var notifyFriendActivity: Bool = false
    var notifyPlaylistUpdates: Bool = true
    
    init(
        id: UUID = UUID(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
    
    /// Update the updatedAt timestamp.
    func touch() {
        updatedAt = .now
    }
}

// MARK: - Media Sort Options

enum MediaSort: String, Codable, CaseIterable {
    case titleAsc = "titleAsc"
    case titleDesc = "titleDesc"
    case dateAddedAsc = "dateAddedAsc"
    case dateAddedDesc = "dateAddedDesc"
    case durationAsc = "durationAsc"
    case durationDesc = "durationDesc"
    case artistAsc = "artistAsc"
    case playCountDesc = "playCountDesc"
    case ratingDesc = "ratingDesc"
    
    var displayName: String {
        switch self {
        case .titleAsc: return "Title (A-Z)"
        case .titleDesc: return "Title (Z-A)"
        case .dateAddedAsc: return "Oldest First"
        case .dateAddedDesc: return "Recently Added"
        case .durationAsc: return "Shortest First"
        case .durationDesc: return "Longest First"
        case .artistAsc: return "Artist (A-Z)"
        case .playCountDesc: return "Most Played"
        case .ratingDesc: return "Highest Rated"
        }
    }
}

// MARK: - View Style

enum ViewStyle: String, Codable, CaseIterable {
    case list
    case grid
    case compact
    
    var displayName: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        case .compact: return "Compact"
        }
    }
    
    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        case .compact: return "list.dash"
        }
    }
}

// MARK: - Quality Settings

enum AudioQuality: String, Codable, CaseIterable {
    case low = "128kbps"
    case medium = "256kbps"
    case high = "320kbps"
    
    var displayName: String { rawValue }
}

enum VideoQuality: String, Codable, CaseIterable {
    case q720p = "720p"
    case q1080p = "1080p"
    case q4k = "4K"
    
    var displayName: String { rawValue }
}
