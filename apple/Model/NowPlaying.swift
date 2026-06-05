import Foundation
import AVFoundation
import MediaPlayer

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// Decoupled snapshot of a track for the player — avoids passing
/// SwiftData @Models around the audio session.
struct PlayableTrack: Identifiable, Equatable {
    let id: UUID
    let title: String
    let fileURL: URL
}

/// Drives Now Playing Info (lockscreen, Control Center, headphone remote)
/// and owns the currently playing audio queue.
@MainActor
final class NowPlaying: ObservableObject {

    @Published private(set) var queue: [PlayableTrack] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentAlbum: String = ""
    @Published private(set) var isPlaying: Bool = false

    private var player: AVAudioPlayer?
    private var delegateBox: AVAudioPlayerDelegate?
    private var artworkImage: PlatformImage?

    init() {
        configureAudioSession()
        wireRemoteCommands()
    }

    var currentTrack: PlayableTrack? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var hasNext: Bool { currentIndex + 1 < queue.count }
    var hasPrevious: Bool { currentIndex > 0 }

    /// Start (or replace) an album / playlist queue and begin playing at
    /// `index`. Subsequent `next`/`previous` walk the same queue.
    func play(
        queue: [PlayableTrack],
        startingAt index: Int = 0,
        album: String,
        artwork: PlatformImage? = nil
    ) {
        self.queue = queue
        self.currentAlbum = album
        self.artworkImage = artwork
        playTrack(at: index)
    }

    func togglePlayPause() {
        guard let p = player else { return }
        if p.isPlaying { p.pause(); isPlaying = false }
        else           { p.play();  isPlaying = true  }
        refreshNowPlayingInfo(elapsed: p.currentTime, duration: p.duration)
    }

    func next() {
        guard hasNext else { return }
        playTrack(at: currentIndex + 1)
    }

    func previous() {
        // Mirror typical music-app behaviour: tap previous within the
        // first ~3s restarts the current track; otherwise jumps back.
        if let p = player, p.currentTime > 3, queue.indices.contains(currentIndex) {
            p.currentTime = 0
            refreshNowPlayingInfo(elapsed: 0, duration: p.duration)
            return
        }
        guard hasPrevious else { return }
        playTrack(at: currentIndex - 1)
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: – Internals

    private func playTrack(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let track = queue[index]
        do {
            let p = try AVAudioPlayer(contentsOf: track.fileURL)
            p.prepareToPlay()
            let bridge = DelegateBridge { [weak self] in
                Task { @MainActor in self?.handleTrackFinished() }
            }
            p.delegate = bridge
            delegateBox = bridge
            p.play()
            self.player = p
            self.currentIndex = index
            self.isPlaying = true
            refreshNowPlayingInfo(elapsed: 0, duration: p.duration)
        } catch {
            print("NowPlaying: failed to play \(track.fileURL): \(error)")
        }
    }

    private func handleTrackFinished() {
        if hasNext {
            next()
        } else {
            isPlaying = false
            refreshNowPlayingInfo(elapsed: 0, duration: 0)
        }
    }

    private func configureAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, options: []
        )
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func wireRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            self?.player?.play(); self?.isPlaying = true; return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause(); self?.isPlaying = false; return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.next(); return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous(); return .success
        }
    }

    private func refreshNowPlayingInfo(elapsed: TimeInterval, duration: TimeInterval) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack?.title ?? "",
            MPMediaItemPropertyAlbumTitle: currentAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let art = artworkImage {
            info[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

private final class DelegateBridge: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(_ onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
        onFinish()
    }
}
