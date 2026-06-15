import SwiftUI

/// Compact "now playing" bar shown above the tab bar whenever there's an
/// active track. Tap the title area to open the expanded full-screen
/// player; tap the buttons to control playback inline.
struct NowPlayingBar: View {
    @EnvironmentObject var nowPlaying: NowPlaying
    @State private var showingFull = false

    var body: some View {
        if let track = nowPlaying.currentTrack {
            VStack(spacing: 0) {
                // Thin progress line at the top of the mini-bar so the user
                // can see playback advance without opening the full player.
                MiniProgressBar(
                    elapsed: nowPlaying.currentTime,
                    duration: nowPlaying.duration
                )
                HStack(spacing: 12) {
                    Button { showingFull = true } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if let art = nowPlaying.artworkImage {
                                        #if canImport(UIKit)
                                        Image(uiImage: art).resizable().scaledToFill()
                                        #else
                                        Image(nsImage: art).resizable().scaledToFill()
                                        #endif
                                    } else {
                                        Image(systemName: "music.note").font(.title3)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
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

                    Button { nowPlaying.previous() } label: {
                        Image(systemName: "backward.fill").font(.title3)
                    }
                    .disabled(!nowPlaying.hasPrevious)
                    .buttonStyle(.borderless)

                    Button { nowPlaying.togglePlayPause() } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)

                    Button { nowPlaying.next() } label: {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .disabled(!nowPlaying.hasNext)
                    .buttonStyle(.borderless)

                    Button { nowPlaying.stop() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Stop and close player")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
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

    /// Non-nil while the user is dragging the scrubber — overrides the
    /// timer-driven currentTime so the slider tracks the finger smoothly.
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Spacer()

            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
                .frame(width: 180, height: 180)
                .overlay {
                    if let art = nowPlaying.artworkImage {
                        #if canImport(UIKit)
                        Image(uiImage: art).resizable().scaledToFill()
                        #else
                        Image(nsImage: art).resizable().scaledToFill()
                        #endif
                    } else {
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.tertiary)
                            .padding(40)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 6) {
                Text(nowPlaying.currentTrack?.title ?? "")
                    .font(.title2).bold().lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(nowPlaying.currentAlbum)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal)

            scrubber
                .padding(.horizontal, 8)

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

            volumeControl
                .padding(.horizontal)

            Button(role: .destructive) {
                nowPlaying.stop()
                dismiss()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .padding(.horizontal)
        .presentationDragIndicator(.hidden)
    }

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $nowPlaying.volume, in: 0...1)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var scrubber: some View {
        let duration = max(nowPlaying.duration, 0.001)
        let live = scrubValue ?? nowPlaying.currentTime
        let bindable = Binding<Double>(
            get: { live },
            set: { scrubValue = $0 }
        )
        VStack(spacing: 4) {
            Slider(
                value: bindable,
                in: 0...duration,
                onEditingChanged: { editing in
                    if !editing {
                        if let v = scrubValue { nowPlaying.seek(to: v) }
                        scrubValue = nil
                    }
                }
            )
            HStack {
                Text(formatTime(live))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-" + formatTime(max(duration - live, 0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

/// Thin progress line at the top of the mini-bar. Non-interactive — the
/// scrubbing slider lives in the expanded player.
private struct MiniProgressBar: View {
    let elapsed: TimeInterval
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let frac = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary)
                Rectangle()
                    .fill(.tint)
                    .frame(width: geo.size.width * CGFloat(frac))
            }
        }
        .frame(height: 2)
    }
}
