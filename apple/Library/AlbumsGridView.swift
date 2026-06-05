import SwiftUI
import SwiftData

struct AlbumsGridView: View {
    @Query(sort: \Album.addedAt, order: .reverse) private var albums: [Album]
    @EnvironmentObject var mediaRoot: MediaRoot
    @State private var showingAdd = false

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

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
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(albums) { album in
                                NavigationLink {
                                    AlbumDetailView(album: album)
                                } label: {
                                    AlbumTile(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
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
}

private struct AlbumTile: View {
    let album: Album
    @EnvironmentObject var mediaRoot: MediaRoot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(8)
                if let coverURL = album.coverURL(in: mediaRoot),
                   let img = PlatformImage(contentsOfFile: coverURL.path) {
                    #if canImport(UIKit)
                    Image(uiImage: img).resizable().scaledToFill().cornerRadius(8)
                    #else
                    Image(nsImage: img).resizable().scaledToFill().cornerRadius(8)
                    #endif
                } else {
                    Image(systemName: "music.note")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
            Text(album.title)
                .font(.headline).lineLimit(1)
            Text("\(album.tracks.count) tracks")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
