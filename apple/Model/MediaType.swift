import Foundation

/// Classifies media content into distinct types for specialized handling.
enum MediaType: String, Codable, CaseIterable, Identifiable {
    case video
    case music
    case audiobook
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .video: return "Video"
        case .music: return "Music"
        case .audiobook: return "Audiobook"
        }
    }
    
    var systemImage: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .music: return "music.note"
        case .audiobook: return "book.fill"
        }
    }
}
