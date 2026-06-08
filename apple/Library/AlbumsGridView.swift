import SwiftUI
import SwiftData

/// Library list of albums. Uses `List` (not `LazyVGrid`) so it gets native
/// swipe-to-delete; the row layout is thumbnail + title + track count,
/// matching Apple Music's "Library > Albums" list view.
struct AlbumsGridView: View {
    @Query(sort: \Album.addedAt, order: .reverse) private var albums: [Album]
    @EnvironmentObject var mediaRoot: MediaRoot
    @Environment(\.modelContext) private var context
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if albums.isEmpty {
                    ContentUnavailableView(
                        "No albums yet",
                        systemImage: "music.note.list",
                        description: Text("Tap + to add a YouTube URL.")
                    )
                } else {
                    List {
                        ForEach(albums) { album in
                            NavigationLink {
                                AlbumDetailView(album: album)
                            } label: {
                                AlbumRow(album: album)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(album)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Music Albums")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddUrlsSheet(destination: .music)
            }
        }
    }

    private func delete(_ album: Album) {
        // Tracks live in a per-album folder under MediaRoot. Delete the
        // folder (the cover image + all track mp3s) then drop the catalog
        // entries. Track rows are cascade-deleted via the @Relationship.
        if let track = album.orderedTracks.first,
           let trackURL = track.fileURL(in: mediaRoot) {
            let folder = trackURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: folder)
        } else if let cover = album.coverURL(in: mediaRoot) {
            // Fallback: single-track album with no tracks fetched.
            try? FileManager.default.removeItem(at: cover.deletingLastPathComponent())
        }
        context.delete(album)
        try? context.save()
    }
}

private struct AlbumRow: View {
    let album: Album
    @EnvironmentObject var mediaRoot: MediaRoot

    var body: some View {
        HStack(spacing: 12) {
            cover
                .frame(width: 56, height: 56)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .lineLimit(2)
                Text("\(album.tracks.count) tracks · \(album.sourceKind.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var cover: some View {
        if let url = album.coverURL(in: mediaRoot),
           let img = PlatformImage(contentsOfFile: url.path) {
            #if canImport(UIKit)
            Image(uiImage: img).resizable().scaledToFill()
            #else
            Image(nsImage: img).resizable().scaledToFill()
            #endif
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
