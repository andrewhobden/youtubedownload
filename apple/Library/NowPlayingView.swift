import SwiftUI

/// Compact "now playing" bar shown above the tab bar whenever there's an
/// active track. Tap the title area to open the expanded full-screen
/// player; tap the buttons to control playback inline.
struct NowPlayingBar: View {
    @EnvironmentObject var nowPlaying: NowPlaying
    @State private var showingFull = false

    var body: some View {
        if let track = nowPlaying.currentTrack {
            HStack(spacing: 12) {
                Button { showingFull = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline).lineLimit(1)
                            Text(nowPlaying.currentAlbum)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    nowPlaying.previous()
                } label: {
                    Image(systemName: "backward.fill").font(.title3)
                }
                .disabled(!nowPlaying.hasPrevious)
                .buttonStyle(.borderless)

                Button {
                    nowPlaying.togglePlayPause()
                } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)

                Button {
                    nowPlaying.next()
                } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .disabled(!nowPlaying.hasNext)
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .overlay(Divider(), alignment: .top)
            .sheet(isPresented: $showingFull) {
                ExpandedNowPlayingView()
            }
        }
    }
}

/// Full-screen player shown when the user taps the mini-bar.
struct ExpandedNowPlayingView: View {
    @EnvironmentObject var nowPlaying: NowPlaying
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Spacer()

            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .foregroundStyle(.tertiary)
                .padding(40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 6) {
                Text(nowPlaying.currentTrack?.title ?? "")
                    .font(.title2).bold().lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(nowPlaying.currentAlbum)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal)

            Spacer()

            HStack(spacing: 32) {
                Button {
                    nowPlaying.previous()
                } label: {
                    Image(systemName: "backward.fill").font(.largeTitle)
                }
                .disabled(!nowPlaying.hasPrevious)

                Button {
                    nowPlaying.togglePlayPause()
                } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }

                Button {
                    nowPlaying.next()
                } label: {
                    Image(systemName: "forward.fill").font(.largeTitle)
                }
                .disabled(!nowPlaying.hasNext)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
        .padding(.horizontal)
        .presentationDragIndicator(.hidden)
    }
}
