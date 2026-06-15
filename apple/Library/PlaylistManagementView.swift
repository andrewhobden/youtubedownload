import SwiftUI
import SwiftData

struct PlaylistManagementView: View {
    @Environment(\.modelContext) private var context
    @Query private var playlists: [Playlist]
    
    @State private var showCreateSheet = false
    @State private var selectedPlaylist: Playlist?
    
    var body: some View {
        ZStack {
            AnimatedGradientBackground()
                .ignoresSafeArea()
            
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Create new button
                    Button {
                        showCreateSheet = true
                        HapticFeedback.trigger(.light)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Create New Playlist")
                                    .font(.system(size: 17, weight: .semibold))
                                
                                Text("Organize your media collection")
                                    .font(.system(size: 14))
                                    .opacity(0.7)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .opacity(0.5)
                        }
                        .foregroundColor(.white)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .pressAnimation()
                    
                    // User playlists
                    ForEach(playlists) { playlist in
                        PlaylistCard(playlist: playlist) {
                            selectedPlaylist = playlist
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Playlists")
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistSheet()
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
        }
    }
}

// MARK: - Playlist Card

private struct PlaylistCard: View {
    let playlist: Playlist
    let onTap: () -> Void
    
    @State private var showDeleteConfirm = false
    
    var body: some View {
        Button(action: {
            HapticFeedback.trigger(.medium)
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Icon or artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: playlistIcon)
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(playlist.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let desc = playlist.descriptionText, !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(2)
                        } else {
                            Text("\(playlist.items.count) items")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
            )
        }
        .pressAnimation()
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Open", systemImage: "play.rectangle")
            }
            
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Playlist", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete Playlist", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                deletePlaylist()
            }
        } message: {
            Text("Are you sure you want to delete \"\(playlist.name)\"? This cannot be undone.")
        }
    }
    
    private var playlistIcon: String {
        if playlist.isShared {
            return "music.note.list"
            return "person.2.fill"
        } else {
            return "music.note"
        }
    }
    
    private var gradientColors: [Color] {
        let hash = playlist.name.hashValue
        let colorPairs: [[Color]] = [
            [.blue, .purple],
            [.pink, .orange],
            [.green, .teal],
            [.red, .pink],
            [.purple, .blue],
            [.orange, .red]
        ]
        return colorPairs[abs(hash) % colorPairs.count]
    }
    
    private func deletePlaylist() {
        // Delete playlist (context.delete would be called from parent)
    }
}

// MARK: - Create Playlist Sheet

private struct CreatePlaylistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var isShared = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                Form {
                    Section {
                        TextField("Playlist Name", text: $name)
                            .font(.system(size: 17))
                        
                        TextField("Description (optional)", text: $description, axis: .vertical)
                            .font(.system(size: 15))
                            .lineLimit(3...6)
                    } header: {
                        Text("Details")
                    }
                    
                    Section {
                        Toggle("Shared Playlist", isOn: $isShared)
                    } header: {
                        Text("Options")
                    } footer: {
                        Text("Shared playlists can be shared with others.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createPlaylist()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func createPlaylist() {
        let playlist = Playlist(
            name: name,
            descriptionText: description.isEmpty ? nil : description
        )
        playlist.isShared = isShared
        
        context.insert(playlist)
        
        HapticFeedback.trigger(.success)
        dismiss()
    }
}

// MARK: - Playlist Detail View

struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var showEditSheet = false
    @State private var showAddItemsSheet = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 16) {
                            // Artwork
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 200, height: 200)
                                
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 80))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            // Title & Description
                            VStack(spacing: 8) {
                                Text(playlist.name)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                
                                if let desc = playlist.descriptionText, !desc.isEmpty {
                                    Text(desc)
                                        .font(.system(size: 15))
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                                
                                Text("\(playlist.items.count) items")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            // Actions
                            HStack(spacing: 12) {
                                GlassButton("Play All", systemImage: "play.fill") {
                                    playAllItems()
                                }
                                
                                GlassButton("Shuffle", systemImage: "shuffle", style: .secondary) {
                                    shufflePlay()
                                }
                                
                                GlassButton("Add Items", systemImage: "plus", style: .secondary) {
                                    showAddItemsSheet = true
                                }
                            }
                        }
                        .padding(.top, 20)
                        
                        // Items list
                        LazyVStack(spacing: 12) {
                            ForEach(Array(playlist.items.enumerated()), id: \.element.id) { index, item in
                                PlaylistItemRow(item: item, index: index + 1) {
                                    removeItem(item)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Text("Edit")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditPlaylistSheet(playlist: playlist)
        }
        .sheet(isPresented: $showAddItemsSheet) {
            AddItemsToPlaylistSheet(playlist: playlist)
        }
    }
    
    private func playAllItems() {
        // Play all items in order
        HapticFeedback.trigger(.success)
    }
    
    private func shufflePlay() {
        // Shuffle and play
        HapticFeedback.trigger(.success)
    }
    
    private func removeItem(_ item: PlaylistItem) {
        if let index = playlist.items.firstIndex(of: item) {
            playlist.items.remove(at: index)
        }
    }
}

// MARK: - Playlist Item Row

private struct PlaylistItemRow: View {
    let item: PlaylistItem
    let index: Int
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Index
            Text("\(index)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 30, alignment: .trailing)
            
            // Placeholder artwork
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                )
            
            // Title & artist
            VStack(alignment: .leading, spacing: 4) {
                Text("Media Item \(index)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                
                Text("Artist • Album")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Duration
            Text("3:45")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove from Playlist", systemImage: "trash")
            }
        }
    }
}

// MARK: - Edit Playlist Sheet

private struct EditPlaylistSheet: View {
    @Bindable var playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                Form {
                    Section {
                        TextField("Playlist Name", text: $playlist.name)
                        TextField("Description (optional)", text: Binding(
                            get: { playlist.descriptionText ?? "" },
                            set: { playlist.descriptionText = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                            .lineLimit(3...6)
                    } header: {
                        Text("Details")
                    }
                    
                    Section {
                        Toggle("Public Playlist", isOn: $playlist.isShared)
                    } header: {
                        Text("Options")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        playlist.updatedAt = .now
                        HapticFeedback.trigger(.success)
                        dismiss()
                    }
                    .disabled(playlist.name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Items Sheet

private struct AddItemsToPlaylistSheet: View {
    @Bindable var playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                VStack {
                    Text("Add items to \(playlist.name)")
                        .foregroundColor(.white)
                        .padding()
                    
                    Text("Item selection UI would go here")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .navigationTitle("Add Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}
