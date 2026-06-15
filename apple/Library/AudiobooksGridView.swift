import SwiftUI
import SwiftData

/// Dedicated view for browsing and managing audiobooks with progress indicators
struct AudiobooksGridView: View {
    @Query(sort: \Audiobook.addedAt, order: .reverse) private var audiobooks: [Audiobook]
    @EnvironmentObject var mediaRoot: MediaRoot
    @EnvironmentObject var nowPlaying: NowPlaying
    @Environment(\.modelContext) private var context
    @State private var showingAddSheet = false
    @State private var selectedAudiobook: Audiobook?
    @State private var searchText = ""
    
    var filteredAudiobooks: [Audiobook] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return audiobooks }
        return audiobooks.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            ($0.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if audiobooks.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(filteredAudiobooks) { audiobook in
                                AudiobookCard(audiobook: audiobook, mediaRoot: mediaRoot)
                                    .onTapGesture {
                                        selectedAudiobook = audiobook
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            delete(audiobook)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Audiobooks")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter audiobooks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddUrlsSheet(destination: .audiobook)
            }
            .sheet(item: $selectedAudiobook) { audiobook in
                playerSheet(for: audiobook)
            }
        }
    }
    
    /// Build the player for the tapped audiobook, resolving all of its track
    /// files so multi-file books play through and expose chapters.
    private func playerSheet(for audiobook: Audiobook) -> some View {
        let tracks: [AudiobookTrack] = audiobook.orderedTracks.compactMap { track in
            guard let url = track.fileURL(in: mediaRoot) else { return nil }
            return AudiobookTrack(url: url, duration: track.durationSec, title: track.title)
        }
        return Group {
            if !tracks.isEmpty {
                AudiobookPlayerView(
                    player: AudiobookPlayer(audiobook: audiobook, tracks: tracks),
                    audiobook: audiobook,
                    mediaRoot: mediaRoot
                )
            } else {
                ContentUnavailableView(
                    "Can't Play Audiobook",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The audio files for this audiobook are missing.")
                )
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tertiary)
            
            Text("No Audiobooks Yet")
                .font(.title2.bold())
            
            Text("Add audiobooks from YouTube or import your own")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            GlassButton("Add Audiobook", systemImage: "plus") {
                showingAddSheet = true
            }
            .padding(.top)
        }
    }
    
    private func delete(_ audiobook: Audiobook) {
        HapticFeedback.trigger(.warning)
        
        if let track = audiobook.orderedTracks.first,
           let trackURL = track.fileURL(in: mediaRoot) {
            let folder = trackURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: folder)
        } else if let cover = audiobook.coverURL(in: mediaRoot) {
            try? FileManager.default.removeItem(at: cover.deletingLastPathComponent())
        }
        
        withAnimation(.smooth) {
            context.delete(audiobook)
            try? context.save()
        }
    }
}

/// Landscape card for an audiobook: 16:9 cover on the left, details on the right.
struct AudiobookCard: View {
    let audiobook: Audiobook
    let mediaRoot: MediaRoot
    
    private let coverWidth: CGFloat = 160
    private let coverHeight: CGFloat = 90   // 16:9, matches YouTube source art
    
    var body: some View {
        HStack(spacing: 14) {
            // 16:9 landscape cover
            ZStack(alignment: .bottomTrailing) {
                LocalImage(url: audiobook.coverURL(in: mediaRoot)) {
                    placeholderCover
                }
                .frame(width: coverWidth, height: coverHeight)
                .clipped()
                
                if audiobook.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white, .green)
                        .padding(6)
                }
            }
            .frame(width: coverWidth, height: coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            // Details
            VStack(alignment: .leading, spacing: 5) {
                Text(audiobook.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let author = audiobook.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(formatDuration(audiobook.totalDuration))
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
                
                if audiobook.completionPercentage > 0 && !audiobook.isFinished {
                    HStack(spacing: 6) {
                        ProgressView(value: audiobook.completionPercentage)
                            .tint(.accentColor)
                        Text("\(Int(audiobook.completionPercentage * 100))%")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
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
            Image(systemName: "book.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Preview

#Preview {
    AudiobooksGridView()
        .environmentObject(MediaRoot())
        .environmentObject(NowPlaying())
}
