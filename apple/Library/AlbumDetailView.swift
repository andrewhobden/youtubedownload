import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var mediaRoot: MediaRoot
    @EnvironmentObject var nowPlaying: NowPlaying

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        cover
                            .frame(width: 120, height: 120)
                            .cornerRadius(10)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(album.title)
                                .font(.title3).bold()
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(album.tracks.count) tracks · \(album.sourceKind.rawValue.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 12) {
                        Button {
                            playFromIndex(0)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            playShuffled()
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Tracks") {
                ForEach(Array(album.orderedTracks.enumerated()), id: \.element.id) { idx, track in
                    Button {
                        playFromIndex(idx)
                    } label: {
                        HStack {
                            Text("\(track.trackNumber)")
                                .frame(width: 28, alignment: .trailing)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(track.title).lineLimit(1)
                            Spacer()
                            Text(formatDuration(track.durationSec))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(album.title)
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
                Image(systemName: "music.note").font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func playFromIndex(_ start: Int) {
        let playables = buildQueue(from: album.orderedTracks)
        guard playables.indices.contains(start) else { return }
        nowPlaying.play(
            queue: playables,
            startingAt: start,
            album: album.title,
            artwork: loadCover()
        )
    }

    private func playShuffled() {
        // Shuffle the orderedTracks first, then build playables from the
        // shuffled order so trackNumber stays in sync with the queue.
        let shuffled = album.orderedTracks.shuffled()
        let playables = buildQueue(from: shuffled)
        nowPlaying.play(
            queue: playables,
            startingAt: 0,
            album: album.title,
            artwork: loadCover()
        )
    }

    private func buildQueue(from tracks: [Track]) -> [PlayableTrack] {
        tracks.compactMap { track in
            guard let url = track.fileURL(in: mediaRoot) else { return nil }
            return PlayableTrack(id: track.id, title: track.title, fileURL: url)
        }
    }

    private func loadCover() -> PlatformImage? {
        guard let url = album.coverURL(in: mediaRoot) else { return nil }
        return PlatformImage(contentsOfFile: url.path)
    }
}
