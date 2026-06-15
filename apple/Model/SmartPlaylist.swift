import Foundation
import SwiftData

/// Rule condition for smart playlists that auto-populate based on criteria.
struct PlaylistRule: Codable, Identifiable {
    var id: UUID = UUID()
    var field: RuleField
    var operatorType: RuleOperator
    var value: String                      // Generic string value, parsed based on field type
    
    enum RuleField: String, Codable, CaseIterable {
        case mediaType
        case genre
        case artist
        case creator
        case title
        case duration
        case playCount
        case rating
        case dateAdded
        case lastPlayed
        case year
        case tags
        case isFinished                    // For audiobooks
        
        var displayName: String {
            switch self {
            case .mediaType: return "Media Type"
            case .genre: return "Genre"
            case .artist: return "Artist"
            case .creator: return "Creator"
            case .title: return "Title"
            case .duration: return "Duration"
            case .playCount: return "Play Count"
            case .rating: return "Rating"
            case .dateAdded: return "Date Added"
            case .lastPlayed: return "Last Played"
            case .year: return "Year"
            case .tags: return "Tags"
            case .isFinished: return "Is Finished"
            }
        }
    }
    
    enum RuleOperator: String, Codable, CaseIterable {
        case equals = "is"
        case notEquals = "is not"
        case contains = "contains"
        case notContains = "does not contain"
        case greaterThan = "greater than"
        case lessThan = "less than"
        case greaterOrEqual = "greater or equal"
        case lessOrEqual = "less or equal"
        case startsWith = "starts with"
        case endsWith = "ends with"
        case inLast = "in the last"         // For date fields
        case notInLast = "not in the last"
        
        var displayName: String {
            rawValue
        }
    }
    
    /// Get applicable operators for a given field type.
    static func operators(for field: RuleField) -> [RuleOperator] {
        switch field {
        case .mediaType, .genre, .artist, .creator, .title, .tags:
            return [.equals, .notEquals, .contains, .notContains, .startsWith, .endsWith]
        case .duration, .playCount, .rating, .year:
            return [.equals, .notEquals, .greaterThan, .lessThan, .greaterOrEqual, .lessOrEqual]
        case .dateAdded, .lastPlayed:
            return [.inLast, .notInLast, .greaterThan, .lessThan]
        case .isFinished:
            return [.equals]
        }
    }
}

/// Group of rules with AND/OR logic.
struct RuleGroup: Codable, Identifiable {
    var id: UUID = UUID()
    var rules: [PlaylistRule] = []
    var matchAll: Bool = true              // true = AND, false = OR
    
    var logicDescription: String {
        matchAll ? "Match ALL of the following" : "Match ANY of the following"
    }
}

/// Smart playlist that automatically populates based on rules.
@Model
final class SmartPlaylist {
    @Attribute(.unique) var id: UUID
    var playlist: Playlist?
    
    /// Rule groups encoded as JSON. Multiple groups are combined with OR logic.
    var ruleGroupsJSON: Data?
    
    /// Whether this smart playlist auto-updates when media library changes.
    var autoUpdate: Bool = true
    
    /// Last time the playlist was evaluated and updated.
    var lastEvaluatedAt: Date?
    
    /// Limit maximum number of items (0 = unlimited).
    var itemLimit: Int = 0
    
    /// Sort order for auto-populated items.
    var sortByRaw: String = SmartPlaylistSort.dateAddedDesc.rawValue
    
    enum SmartPlaylistSort: String, Codable, CaseIterable {
        case dateAddedDesc = "date_added_desc"
        case dateAddedAsc = "date_added_asc"
        case titleAsc = "title_asc"
        case titleDesc = "title_desc"
        case durationDesc = "duration_desc"
        case durationAsc = "duration_asc"
        case playCountDesc = "play_count_desc"
        case playCountAsc = "play_count_asc"
        case ratingDesc = "rating_desc"
        case random = "random"
        
        var displayName: String {
            switch self {
            case .dateAddedDesc: return "Recently Added"
            case .dateAddedAsc: return "Oldest First"
            case .titleAsc: return "Title (A-Z)"
            case .titleDesc: return "Title (Z-A)"
            case .durationDesc: return "Longest First"
            case .durationAsc: return "Shortest First"
            case .playCountDesc: return "Most Played"
            case .playCountAsc: return "Least Played"
            case .ratingDesc: return "Highest Rated"
            case .random: return "Random"
            }
        }
    }
    
    var sortBy: SmartPlaylistSort {
        get { SmartPlaylistSort(rawValue: sortByRaw) ?? .dateAddedDesc }
        set { sortByRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        playlist: Playlist? = nil,
        ruleGroups: [RuleGroup] = [],
        autoUpdate: Bool = true,
        sortBy: SmartPlaylistSort = .dateAddedDesc,
        itemLimit: Int = 0
    ) {
        self.id = id
        self.playlist = playlist
        self.autoUpdate = autoUpdate
        self.sortBy = sortBy
        self.itemLimit = itemLimit
        self.ruleGroups = ruleGroups
    }
    
    /// Decoded rule groups from JSON storage.
    var ruleGroups: [RuleGroup] {
        get {
            guard let data = ruleGroupsJSON else { return [] }
            return (try? JSONDecoder().decode([RuleGroup].self, from: data)) ?? []
        }
        set {
            ruleGroupsJSON = try? JSONEncoder().encode(newValue)
        }
    }
}
