import SwiftUI
import SwiftData

/// Enhanced videos library with multiple view modes and glassmorphic design
struct VideosListView: View {
    @Query(sort: \VideoItem.addedAt, order: .reverse) private var videos: [VideoItem]
    @EnvironmentObject var mediaRoot: MediaRoot
    @Environment(\.modelContext) private var context
    
    @State private var showingAdd = false
    @State private var viewMode: ViewMode = .grid
    @State private var sortOrder: SortOrder = .recentlyAdded
    @State private var filterCreator: String? = nil
    @State private var showingFilters = false
    @State private var playingVideo: VideoItem?
    @State private var searchText = ""
    
    enum ViewMode: String, CaseIterable {
        case grid, list, compact
        
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "rectangle.grid.1x2"
            case .compact: return "list.bullet"
            }
        }
    }
    
    enum SortOrder: String, CaseIterable {
        case recentlyAdded = "Recently Added"
        case title = "Title"
        case duration = "Duration"
        case mostPlayed = "Most Played"
        
        var systemImage: String {
            switch self {
            case .recentlyAdded: return "clock"
            case .title: return "textformat"
            case .duration: return "timer"
            case .mostPlayed: return "play.circle"
            }
        }
    }
    
    var sortedAndFilteredVideos: [VideoItem] {
        var filtered = videos
        
        // Apply creator filter
        if let creator = filterCreator, !creator.isEmpty {
            filtered = filtered.filter { $0.creator?.localizedCaseInsensitiveContains(creator) == true }
        }
        
        // Apply text filter (title or creator)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                ($0.creator?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        
        // Apply sort
        switch sortOrder {
        case .recentlyAdded:
            return filtered.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .duration:
            return filtered.sorted { $0.durationSec > $1.durationSec }
        case .mostPlayed:
            return filtered.sorted { $0.playCount > $1.playCount }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if videos.isEmpty {
                    emptyState
                } else {
                    contentView
                }
            }
            .navigationTitle("Videos")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter videos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        if filterCreator != nil {
                            Button {
                                withAnimation(.smooth) {
                                    filterCreator = nil
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        
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
                AddUrlsSheet(destination: .videos)
            }
            .fullScreenCover(item: $playingVideo) { video in
                VideoPlayerView(
                    fileURL: video.fileURL(in: mediaRoot) ?? URL(string: "about:blank")!,
                    title: video.title
                )
                .onAppear { dlog("[VideoDebug] fullScreenCover presented for \(video.title)") }
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
    
    /// Open the player for `video`, logging the resolved path + existence so a
    /// failure to present can be diagnosed from the device console.
    private func selectVideo(_ video: VideoItem) {
        let url = video.fileURL(in: mediaRoot)
        let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        dlog("[VideoDebug] tap: title=\(video.title) relPath=\(video.fileRelPath) " +
              "root=\(mediaRoot.rootURL?.path ?? "nil") url=\(url?.path ?? "nil") exists=\(exists)")
        playingVideo = video
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
            ], spacing: 20) {
                ForEach(sortedAndFilteredVideos) { video in
                    Button {
                        selectVideo(video)
                    } label: {
                        VideoGridCard(video: video, mediaRoot: mediaRoot)
                            .contextMenu {
                                videoContextMenu(video)
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
            LazyVStack(spacing: 12) {
                ForEach(sortedAndFilteredVideos) { video in
                    Button {
                        selectVideo(video)
                    } label: {
                        VideoListCard(video: video, mediaRoot: mediaRoot)
                            .contextMenu {
                                videoContextMenu(video)
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
            ForEach(sortedAndFilteredVideos) { video in
                Button {
                    selectVideo(video)
                } label: {
                    VideoCompactRow(video: video, mediaRoot: mediaRoot)
                }
                .buttonStyle(.pressableCard)
                .listRowBackground(Color.clear)
                .contextMenu {
                    videoContextMenu(video)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(video)
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
    private func videoContextMenu(_ video: VideoItem) -> some View {
        Button {
            selectVideo(video)
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        
        Button {
            // Add to playlist
        } label: {
            Label("Add to Playlist", systemImage: "plus")
        }
        
        if let creator = video.creator {
            Button {
                filterCreator = creator
            } label: {
                Label("More by \(creator)", systemImage: "person")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            delete(video)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 80))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: .repeating)
            
            VStack(spacing: 8) {
                Text("No Videos Yet")
                    .font(.title2.bold())
                
                Text("Add videos from YouTube to start building your library")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            GlassButton("Add Video", systemImage: "plus") {
                showingAdd = true
                HapticFeedback.trigger(.light)
            }
            .padding(.top, 8)
        }
    }
    
    private func delete(_ video: VideoItem) {
        HapticFeedback.trigger(.warning)
        
        if let fileURL = video.fileURL(in: mediaRoot) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if let thumbURL = video.thumbnailURL(in: mediaRoot) {
            try? FileManager.default.removeItem(at: thumbURL)
        }
        
        withAnimation(.smooth) {
            context.delete(video)
            try? context.save()
        }
    }
}

// MARK: - Video Card Components

struct VideoGridCard: View {
    let video: VideoItem
    let mediaRoot: MediaRoot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail with duration badge
            ZStack(alignment: .bottomTrailing) {
                LocalImage(url: video.thumbnailURL(in: mediaRoot)) {
                    placeholderThumb
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                
                // Duration badge
                Text(formatDuration(video.durationSec))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                    .padding(8)
                
                // Resume indicator if partially watched
                if video.lastPosition > 0 && video.lastPosition < video.durationSec {
                    VStack {
                        Spacer()
                        ProgressView(value: video.lastPosition / video.durationSec)
                            .tint(.white)
                            .background(.black.opacity(0.3))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            
            // Video info
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .frame(height: 36, alignment: .top)
                
                HStack {
                    if let creator = video.creator {
                        Text(creator)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if video.playCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.caption2)
                            Text("\(video.playCount)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .mediaCardStyle()
        .pressAnimation()
    }
    
    private var placeholderThumb: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: "play.rectangle")
                .font(.system(size: 50))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 180)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

struct VideoListCard: View {
    let video: VideoItem
    let mediaRoot: MediaRoot
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                LocalImage(url: video.thumbnailURL(in: mediaRoot)) {
                    placeholderThumb
                }
                .frame(width: 120, height: 68)
                .clipped()
                
                Text(formatDuration(video.durationSec))
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Video info
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title)
                    .font(.body.bold())
                    .lineLimit(2)
                
                if let creator = video.creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 12) {
                    if video.playCount > 0 {
                        Label("\(video.playCount) plays", systemImage: "play.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    if video.lastPosition > 0 {
                        Label("Resume", systemImage: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundStyle(.blue)
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
    
    private var placeholderThumb: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: "play.rectangle")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 120, height: 68)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct VideoCompactRow: View {
    let video: VideoItem
    let mediaRoot: MediaRoot
    
    var body: some View {
        HStack(spacing: 12) {
            LocalImage(url: video.thumbnailURL(in: mediaRoot)) {
                placeholderThumb
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let creator = video.creator {
                        Text(creator)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if video.lastPosition > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("Resume")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Spacer()
            
            Text(formatDuration(video.durationSec))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
    
    private var placeholderThumb: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: "play.rectangle")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 64, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Helper Functions

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    let m = s / 60
    let r = s % 60
    if m >= 60 {
        return String(format: "%d:%02d:%02d", m / 60, m % 60, r)
    }
    return String(format: "%d:%02d", m, r)
}
