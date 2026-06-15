import SwiftUI
import SwiftData

/// Enhanced albums library with multiple view modes and glassmorphic design
struct AlbumsGridView: View {
    @Query(sort: \Album.addedAt, order: .reverse) private var albums: [Album]
    @EnvironmentObject var mediaRoot: MediaRoot
    @EnvironmentObject var nowPlaying: NowPlaying
    @Environment(\.modelContext) private var context
    
    @State private var showingAdd = false
    @State private var viewMode: ViewMode = .grid
    @State private var sortOrder: SortOrder = .recentlyAdded
    @State private var showingSortPicker = false
    @State private var searchText = ""
    
    enum ViewMode: String, CaseIterable {
        case grid, list, compact
        
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            case .compact: return "list.dash"
            }
        }
    }
    
    enum SortOrder: String, CaseIterable {
        case recentlyAdded = "Recently Added"
        case title = "Title"
        case artist = "Artist"
        case mostPlayed = "Most Played"
        
        var systemImage: String {
            switch self {
            case .recentlyAdded: return "clock"
            case .title: return "textformat"
            case .artist: return "person"
            case .mostPlayed: return "play.circle"
            }
        }
    }
    
    var sortedAlbums: [Album] {
        var filtered = albums
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                ($0.artist?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        switch sortOrder {
        case .recentlyAdded:
            return filtered.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            return filtered.sorted { ($0.artist ?? "") < ($1.artist ?? "") }
        case .mostPlayed:
            return filtered.sorted { $0.playCount > $1.playCount }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if albums.isEmpty {
                    emptyState
                } else {
                    contentView
                }
            }
            .navigationTitle("Music")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter music")
            .task {
                await CoverArtBackfill.run(context: context, mediaRoot: mediaRoot)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Button {
                                    withAnimation(.smooth) {
                                        viewMode = mode
                                    }
                                } label: {
                                    Label(mode.rawValue.capitalized, systemImage: mode.icon)
                                }
                            }
                        } label: {
                            Image(systemName: viewMode.icon)
                        }
                        
                        Menu {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Button {
                                    withAnimation(.smooth) {
                                        sortOrder = order
                                    }
                                } label: {
                                    Label(order.rawValue, systemImage: order.systemImage)
                                    if sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        
                        Button {
                            showingAdd = true
                            HapticFeedback.trigger(.light)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddUrlsSheet(destination: .music)
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .grid:
            gridView
        case .list:
            listView
        case .compact:
            compactView
        }
    }
    
    private var gridView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(sortedAlbums) { album in
                    NavigationLink(destination: AlbumDetailView(album: album)) {
                        AlbumGridCard(album: album, mediaRoot: mediaRoot)
                            .contextMenu {
                                albumContextMenu(album)
                            }
                    }
                    .buttonStyle(.pressableCard)
                }
            }
            .padding()
        }
    }
    
    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sortedAlbums) { album in
                    NavigationLink(destination: AlbumDetailView(album: album)) {
                        AlbumListCard(album: album, mediaRoot: mediaRoot)
                            .contextMenu {
                                albumContextMenu(album)
                            }
                    }
                    .buttonStyle(.pressableCard)
                }
            }
            .padding()
        }
    }
    
    private var compactView: some View {
        List {
            ForEach(sortedAlbums) { album in
                NavigationLink(destination: AlbumDetailView(album: album)) {
                    AlbumCompactRow(album: album, mediaRoot: mediaRoot)
                }
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(album)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    @ViewBuilder
    private func albumContextMenu(_ album: Album) -> some View {
        Button {
            playAlbum(album)
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        
        Button {
            // Add to playlist
        } label: {
            Label("Add to Playlist", systemImage: "plus")
        }
        
        Divider()
        
        Button(role: .destructive) {
            delete(album)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Start playback of the whole album from the first track. Mirrors
    /// `AlbumDetailView.playFromIndex(0)` so the context-menu Play and the
    /// detail screen behave identically.
    private func playAlbum(_ album: Album) {
        let playables: [PlayableTrack] = album.orderedTracks.compactMap { track in
            guard let url = track.fileURL(in: mediaRoot) else { return nil }
            return PlayableTrack(id: track.id, title: track.title, fileURL: url)
        }
        guard !playables.isEmpty else { return }
        let artwork = album.coverURL(in: mediaRoot)
            .flatMap { PlatformImage(contentsOfFile: $0.path) }
        nowPlaying.play(
            queue: playables,
            startingAt: 0,
            album: album.title,
            artwork: artwork
        )
        HapticFeedback.trigger(.light)
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 80))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: .repeating)
            
            VStack(spacing: 8) {
                Text("No Music Yet")
                    .font(.title2.bold())
                
                Text("Add albums from YouTube or import your own music")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            GlassButton("Add Music", systemImage: "plus") {
                showingAdd = true
                HapticFeedback.trigger(.light)
            }
            .padding(.top, 8)
        }
    }
    
    private func delete(_ album: Album) {
        HapticFeedback.trigger(.warning)
        
        if let track = album.orderedTracks.first,
           let trackURL = track.fileURL(in: mediaRoot) {
            let folder = trackURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: folder)
        } else if let cover = album.coverURL(in: mediaRoot) {
            try? FileManager.default.removeItem(at: cover.deletingLastPathComponent())
        }
        
        withAnimation(.smooth) {
            context.delete(album)
            try? context.save()
        }
    }
}

// MARK: - Album Card Components

/// Landscape card for an album: 16:9 cover on the left, details on the right.
/// Mirrors `AudiobookCard` so the Music and Audiobooks libraries match.
struct AlbumGridCard: View {
    let album: Album
    let mediaRoot: MediaRoot
    
    private let coverWidth: CGFloat = 160
    private let coverHeight: CGFloat = 90   // 16:9, matches YouTube source art
    
    var body: some View {
        HStack(spacing: 14) {
            // 16:9 landscape cover
            ZStack(alignment: .bottomTrailing) {
                LocalImage(url: album.coverURL(in: mediaRoot)) {
                    placeholderCover
                }
                .frame(width: coverWidth, height: coverHeight)
                .clipped()
                
                // Play count badge
                if album.playCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                        Text("\(album.playCount)")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
                }
            }
            .frame(width: coverWidth, height: coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            // Details
            VStack(alignment: .leading, spacing: 5) {
                Text(album.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let artist = album.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                    Text("\(album.tracks.count) tracks")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .mediaCardStyle(cornerRadius: 14)
        .pressAnimation()
    }
    
    private var placeholderCover: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
        }
    }
}

struct AlbumListCard: View {
    let album: Album
    let mediaRoot: MediaRoot
    
    var body: some View {
        HStack(spacing: 12) {
            // Album artwork
            LocalImage(url: album.coverURL(in: mediaRoot)) {
                placeholderCover
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Album info
            VStack(alignment: .leading, spacing: 6) {
                Text(album.title)
                    .font(.body.bold())
                    .lineLimit(2)
                
                if let artist = album.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 12) {
                    Label("\(album.tracks.count)", systemImage: "music.note")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    if album.playCount > 0 {
                        Label("\(album.playCount)", systemImage: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassCard(cornerRadius: 12, shadowRadius: 4)
        .pressAnimation()
    }
    
    private var placeholderCover: some View {
        Image(systemName: "music.note")
            .font(.system(size: 30))
            .foregroundStyle(.tertiary)
            .frame(width: 80, height: 80)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AlbumCompactRow: View {
    let album: Album
    let mediaRoot: MediaRoot
    
    var body: some View {
        HStack(spacing: 12) {
            LocalImage(url: album.coverURL(in: mediaRoot)) {
                placeholderCover
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let artist = album.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("\(album.tracks.count) tracks")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
        }
    }
    
    private var placeholderCover: some View {
        Image(systemName: "music.note")
            .font(.system(size: 20))
            .foregroundStyle(.tertiary)
            .frame(width: 48, height: 48)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
