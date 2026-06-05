import SwiftUI
import SwiftData

struct VideosListView: View {
    @Query(sort: \VideoItem.addedAt, order: .reverse) private var items: [VideoItem]
    @EnvironmentObject var mediaRoot: MediaRoot
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No videos yet",
                        systemImage: "play.rectangle",
                        description: Text("Tap + to add a YouTube URL.")
                    )
                } else {
                    List(items) { item in
                        NavigationLink {
                            if let url = item.fileURL(in: mediaRoot) {
                                VideoPlayerView(fileURL: url, title: item.title)
                            }
                        } label: {
                            VideoRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("Videos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddUrlsSheet(destination: .videos)
            }
        }
    }
}

private struct VideoRow: View {
    let item: VideoItem
    var body: some View {
        HStack {
            Image(systemName: "play.rectangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text(item.title).lineLimit(1)
                Text(formatDuration(item.durationSec))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    let m = s / 60
    let r = s % 60
    if m >= 60 {
        return String(format: "%d:%02d:%02d", m / 60, m % 60, r)
    }
    return String(format: "%d:%02d", m, r)
}
