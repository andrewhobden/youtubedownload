import SwiftUI

/// Full-featured audiobook player view with chapters, bookmarks, and sleep timer.
struct AudiobookPlayerView: View {
    @StateObject var player: AudiobookPlayer
    @State private var showingBookmarks = false
    @State private var showingChapters = false
    @State private var showingSleepTimer = false
    @State private var showingSpeedPicker = false
    @State private var scrubValue: Double?
    
    let audiobook: Audiobook
    let mediaRoot: MediaRoot
    
    var body: some View {
        VStack(spacing: 0) {
            // Album art and info
            artworkSection
            
            Spacer()
            
            // Chapter info
            if let chapter = player.currentChapter {
                chapterInfo(chapter)
            }
            
            // Progress and scrubber
            progressSection
            
            // Playback controls
            controlsSection
            
            // Additional features
            featuresSection
        }
        .padding()
        .sheet(isPresented: $showingBookmarks) {
            BookmarksSheet(player: player, audiobook: audiobook)
        }
        .sheet(isPresented: $showingChapters) {
            ChaptersSheet(player: player, chapters: player.chapters)
        }
        .sheet(isPresented: $showingSleepTimer) {
            SleepTimerSheet(player: player)
        }
        .sheet(isPresented: $showingSpeedPicker) {
            PlaybackSpeedPicker(player: player)
        }
    }
    
    private var artworkSection: some View {
        VStack(spacing: 16) {
            LocalImage(url: audiobook.coverURL(in: mediaRoot), contentMode: .fit) {
                placeholderArtwork
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            
            VStack(spacing: 6) {
                Text(audiobook.title)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                
                if let author = audiobook.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let narrator = audiobook.narrator {
                    Text("Narrated by \(narrator)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 40)
    }
    
    private var placeholderArtwork: some View {
        Image(systemName: "book.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
            .foregroundStyle(.tertiary)
            .frame(width: 280, height: 280)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func chapterInfo(_ chapter: AudiobookChapter) -> some View {
        VStack(spacing: 4) {
            Text("Chapter \(chapter.number)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(chapter.title)
                .font(.subheadline)
                .bold()
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { scrubValue ?? player.currentTime },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 0.001),
                onEditingChanged: { editing in
                    if !editing, let value = scrubValue {
                        player.seek(to: value)
                        scrubValue = nil
                    }
                }
            )
            .tint(.primary)
            
            HStack {
                Text(formatTime(scrubValue ?? player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("-\(formatTime(max(player.duration - (scrubValue ?? player.currentTime), 0)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            // Progress bar with completion percentage
            ProgressView(value: audiobook.completionPercentage)
                .tint(.green)

            // Volume
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }
    
    private var controlsSection: some View {
        HStack(spacing: 40) {
            // Previous chapter
            Button {
                player.previousChapter()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title)
            }
            .disabled(player.currentChapter == nil || player.chapters.first?.id == player.currentChapter?.id)
            
            // Skip backward 15 seconds
            Button {
                player.skipBackward(15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
            }
            
            // Play/Pause
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
            }
            
            // Skip forward 15 seconds
            Button {
                player.skipForward(15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title2)
            }
            
            // Next chapter
            Button {
                player.nextChapter()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title)
            }
            .disabled(player.currentChapter == nil || player.chapters.last?.id == player.currentChapter?.id)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 24)
    }
    
    private var featuresSection: some View {
        HStack(spacing: 32) {
            // Chapters button
            Button {
                showingChapters = true
            } label: {
                Label("Chapters", systemImage: "list.bullet")
                    .font(.subheadline)
            }
            .disabled(player.chapters.isEmpty)
            
            // Playback speed
            Button {
                showingSpeedPicker = true
            } label: {
                Label("\(String(format: "%.1fx", player.rate))", systemImage: "gauge")
                    .font(.subheadline)
            }
            
            // Bookmarks
            Button {
                showingBookmarks = true
            } label: {
                Label("Bookmarks", systemImage: "bookmark")
                    .font(.subheadline)
            }
            
            // Sleep timer
            Button {
                showingSleepTimer = true
            } label: {
                Label("Sleep", systemImage: "moon.fill")
                    .font(.subheadline)
            }
        }
        .buttonStyle(.borderless)
        .padding(.bottom, 20)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
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

// MARK: - Supporting Sheets

struct ChaptersSheet: View {
    let player: AudiobookPlayer
    let chapters: [AudiobookChapter]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(chapters) { chapter in
                Button {
                    player.jumpToChapter(chapter)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chapter \(chapter.number)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(chapter.title)
                                .font(.body)
                        }
                        
                        Spacer()
                        
                        Text(formatDuration(chapter.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if player.currentChapter?.id == chapter.id {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct BookmarksSheet: View {
    let player: AudiobookPlayer
    let audiobook: Audiobook
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddBookmark = false
    @State private var newBookmarkTitle = ""
    @State private var newBookmarkNote = ""
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(player.bookmarks) { bookmark in
                    Button {
                        player.jumpToBookmark(bookmark)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.title)
                                .font(.body)
                            HStack {
                                Text(bookmark.formattedTimestamp)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let note = bookmark.note {
                                    Text("·")
                                        .foregroundStyle(.tertiary)
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            player.deleteBookmark(bookmark)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddBookmark = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBookmark) {
                AddBookmarkSheet(
                    player: player,
                    currentTime: player.currentTime,
                    onSave: { title, note in
                        _ = player.createBookmark(title: title, note: note)
                        showingAddBookmark = false
                    }
                )
            }
        }
    }
}

struct AddBookmarkSheet: View {
    let player: AudiobookPlayer
    let currentTime: TimeInterval
    let onSave: (String, String?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bookmark Title", text: $title)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...5)
                }
                
                Section {
                    HStack {
                        Text("Position")
                        Spacer()
                        Text(formatTime(currentTime))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onSave(title.isEmpty ? "Bookmark at \(formatTime(currentTime))" : title,
                               note.isEmpty ? nil : note)
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
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

struct PlaybackSpeedPicker: View {
    let player: AudiobookPlayer
    @Environment(\.dismiss) private var dismiss
    
    let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5]
    
    var body: some View {
        NavigationStack {
            List(speeds, id: \.self) { speed in
                Button {
                    player.setPlaybackSpeed(speed)
                    dismiss()
                } label: {
                    HStack {
                        Text("\(String(format: "%.2gx", speed))")
                        if speed == 1.0 {
                            Text("Normal")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if abs(player.rate - speed) < 0.01 {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SleepTimerSheet: View {
    let player: AudiobookPlayer
    @Environment(\.dismiss) private var dismiss
    
    let durations: [(String, TimeInterval)] = [
        ("5 minutes", 5 * 60),
        ("10 minutes", 10 * 60),
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("45 minutes", 45 * 60),
        ("1 hour", 60 * 60)
    ]
    
    var body: some View {
        NavigationStack {
            List(durations, id: \.0) { label, duration in
                Button {
                    player.startSleepTimer(duration: duration, fadeOutDuration: 10)
                    dismiss()
                } label: {
                    Text(label)
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
