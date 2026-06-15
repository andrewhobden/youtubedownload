import SwiftUI
import SwiftData

/// Smart collections view showing auto-generated playlists and recommendations
struct SmartCollectionsView: View {
    @Query private var videos: [VideoItem]
    @Query private var albums: [Album]
    @Query private var audiobooks: [Audiobook]
    @Query private var tracks: [Track]
    
    @EnvironmentObject var mediaRoot: MediaRoot
    @State private var selectedCollection: SmartCollection?
    
    enum SmartCollection: String, CaseIterable, Identifiable {
        case recentlyAdded = "Recently Added"
        case recentlyPlayed = "Recently Played"
        case mostPlayed = "Most Played"
        case favorites = "Favorites"
        case longVideos = "Long Videos"
        case quickListens = "Quick Listens"
        case unfinished = "Unfinished"
        case thisWeek = "This Week"
        
        var id: String { rawValue }
        
        var systemImage: String {
            switch self {
            case .recentlyAdded: return "plus.circle.fill"
            case .recentlyPlayed: return "clock.fill"
            case .mostPlayed: return "play.circle.fill"
            case .favorites: return "heart.fill"
            case .longVideos: return "film.fill"
            case .quickListens: return "bolt.fill"
            case .unfinished: return "arrow.clockwise.circle.fill"
            case .thisWeek: return "calendar.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .recentlyAdded: return .green
            case .recentlyPlayed: return .orange
            case .mostPlayed: return .red
            case .favorites: return .pink
            case .longVideos: return .blue
            case .quickListens: return .yellow
            case .unfinished: return .purple
            case .thisWeek: return .teal
            }
        }
        
        var description: String {
            switch self {
            case .recentlyAdded: return "Your newest additions"
            case .recentlyPlayed: return "What you've been watching and listening to"
            case .mostPlayed: return "Your all-time favorites"
            case .favorites: return "Highly rated content"
            case .longVideos: return "Videos over 20 minutes"
            case .quickListens: return "Tracks under 3 minutes"
            case .unfinished: return "Resume where you left off"
            case .thisWeek: return "Added in the last 7 days"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For You")
                            .font(.largeTitle.bold())
                        Text("Personalized collections based on your library")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Smart collections grid
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160), spacing: 16)
                    ], spacing: 16) {
                        ForEach(SmartCollection.allCases) { collection in
                            CollectionCard(
                                collection: collection,
                                count: getCount(for: collection)
                            )
                            .onTapGesture {
                                selectedCollection = collection
                                HapticFeedback.trigger(.selection)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(AnimatedGradientBackground(colors: [.blue.opacity(0.1), .purple.opacity(0.1), .pink.opacity(0.1)]))
            .navigationTitle("Collections")
            .sheet(item: $selectedCollection) { collection in
                CollectionDetailView(
                    collection: collection,
                    items: getItems(for: collection),
                    mediaRoot: mediaRoot
                )
            }
        }
    }
    
    private func getCount(for collection: SmartCollection) -> Int {
        return getItems(for: collection).count
    }
    
    private func getItems(for collection: SmartCollection) -> [AnyMediaItem] {
        let now = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        
        switch collection {
        case .recentlyAdded:
            var allItems: [AnyMediaItem] = []
            allItems.append(contentsOf: videos.map { .video($0) })
            allItems.append(contentsOf: albums.map { .album($0) })
            allItems.append(contentsOf: audiobooks.map { .audiobook($0) })
            return allItems.sorted { $0.addedAt > $1.addedAt }.prefix(20).map { $0 }
            
        case .recentlyPlayed:
            var allItems: [AnyMediaItem] = []
            allItems.append(contentsOf: videos.filter { $0.lastPlayedAt != nil }.map { .video($0) })
            allItems.append(contentsOf: albums.filter { $0.lastPlayedAt != nil }.map { .album($0) })
            allItems.append(contentsOf: audiobooks.filter { $0.lastPlayedAt != nil }.map { .audiobook($0) })
            return allItems.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }.prefix(20).map { $0 }
            
        case .mostPlayed:
            var allItems: [AnyMediaItem] = []
            allItems.append(contentsOf: videos.filter { $0.playCount > 0 }.map { .video($0) })
            allItems.append(contentsOf: albums.filter { $0.playCount > 0 }.map { .album($0) })
            allItems.append(contentsOf: audiobooks.filter { $0.playCount > 0 }.map { .audiobook($0) })
            return allItems.sorted { $0.playCount > $1.playCount }.prefix(20).map { $0 }
            
        case .favorites:
            var allItems: [AnyMediaItem] = []
            allItems.append(contentsOf: videos.filter { ($0.rating ?? 0) >= 4 }.map { .video($0) })
            allItems.append(contentsOf: albums.filter { ($0.rating ?? 0) >= 4 }.map { .album($0) })
            return allItems.prefix(20).map { $0 }
            
        case .longVideos:
            return videos.filter { $0.durationSec >= 1200 } // 20+ minutes
                .sorted { $0.durationSec > $1.durationSec }
                .prefix(20)
                .map { .video($0) }
            
        case .quickListens:
            return tracks.filter { $0.durationSec <= 180 } // Under 3 minutes
                .sorted { $0.durationSec < $1.durationSec }
                .prefix(20)
                .map { .track($0) }
            
        case .unfinished:
            let unfinishedVideos = videos.filter { $0.lastPosition > 0 && $0.lastPosition < $0.durationSec * 0.95 }
                .map { AnyMediaItem.video($0) }
            let unfinishedAudiobooks = audiobooks.filter { !$0.isFinished && $0.completionPercentage > 0 }
                .map { AnyMediaItem.audiobook($0) }
            return (unfinishedVideos + unfinishedAudiobooks).sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            
        case .thisWeek:
            let allItems: [AnyMediaItem] = videos.filter { $0.addedAt >= weekAgo }.map { .video($0) } +
                                            albums.filter { $0.addedAt >= weekAgo }.map { .album($0) } +
                                            audiobooks.filter { $0.addedAt >= weekAgo }.map { .audiobook($0) }
            return allItems.sorted { $0.addedAt > $1.addedAt }
        }
    }
}

// MARK: - Collection Card

struct CollectionCard: View {
    let collection: SmartCollectionsView.SmartCollection
    let count: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(collection.color.gradient)
                    .frame(width: 64, height: 64)
                
                Image(systemName: collection.systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.rawValue)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCard(cornerRadius: 16, shadowRadius: 8)
        .pressAnimation()
    }
}

// MARK: - Collection Detail View

struct CollectionDetailView: View {
    let collection: SmartCollectionsView.SmartCollection
    let items: [AnyMediaItem]
    let mediaRoot: MediaRoot
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(collection.color.gradient)
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: collection.systemImage)
                                .font(.system(size: 44))
                                .foregroundStyle(.white)
                        }
                        
                        Text(collection.rawValue)
                            .font(.title.bold())
                        
                        Text(collection.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text("\(items.count) items")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    
                    // Items list
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            MediaItemRow(item: item, mediaRoot: mediaRoot)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Media Item Row

struct MediaItemRow: View {
    let item: AnyMediaItem
    let mediaRoot: MediaRoot
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                switch item {
                case .video(let video):
                    LocalImage(url: video.thumbnailURL(in: mediaRoot)) {
                        placeholder
                    }
                case .album(let album):
                    LocalImage(url: album.coverURL(in: mediaRoot)) {
                        placeholder
                    }
                case .audiobook(let audiobook):
                    LocalImage(url: audiobook.coverURL(in: mediaRoot)) {
                        placeholder
                    }
                case .track:
                    placeholder
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.bold())
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.caption2)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if item.playCount > 0 {
                VStack(spacing: 2) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                    Text("\(item.playCount)")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12, shadowRadius: 4)
        .pressAnimation()
    }
    
    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: item.icon)
                    .foregroundStyle(.tertiary)
            }
    }
}

// MARK: - Any Media Item Wrapper

enum AnyMediaItem: Identifiable {
    case video(VideoItem)
    case album(Album)
    case audiobook(Audiobook)
    case track(Track)
    
    var id: UUID {
        switch self {
        case .video(let v): return v.id
        case .album(let a): return a.id
        case .audiobook(let a): return a.id
        case .track(let t): return t.id
        }
    }
    
    var title: String {
        switch self {
        case .video(let v): return v.title
        case .album(let a): return a.title
        case .audiobook(let a): return a.title
        case .track(let t): return t.title
        }
    }
    
    var subtitle: String {
        switch self {
        case .video(let v): return v.creator ?? "Video"
        case .album(let a): return a.artist ?? "Album"
        case .audiobook(let a): return a.author ?? "Audiobook"
        case .track(let t): return t.artist ?? "Track"
        }
    }
    
    var icon: String {
        switch self {
        case .video: return "play.rectangle"
        case .album: return "music.note"
        case .audiobook: return "book.fill"
        case .track: return "music.note"
        }
    }
    
    var addedAt: Date {
        switch self {
        case .video(let v): return v.addedAt
        case .album(let a): return a.addedAt
        case .audiobook(let a): return a.addedAt
        case .track(let t): return t.album?.addedAt ?? .distantPast
        }
    }
    
    var lastPlayedAt: Date? {
        switch self {
        case .video(let v): return v.lastPlayedAt
        case .album(let a): return a.lastPlayedAt
        case .audiobook(let a): return a.lastPlayedAt
        case .track(let t): return t.lastPlayedAt
        }
    }
    
    var playCount: Int {
        switch self {
        case .video(let v): return v.playCount
        case .album(let a): return a.playCount
        case .audiobook(let a): return a.playCount
        case .track(let t): return t.playCount
        }
    }
}
