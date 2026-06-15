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
    /// Current playback position in seconds. Updated ~4x/s by a timer
    /// while a track is playing. Read-only from the UI; use `seek` to set.
    @Published private(set) var currentTime: TimeInterval = 0
    /// Active track's total duration in seconds. Zero when no track is loaded.
    @Published private(set) var duration: TimeInterval = 0
    /// Output volume (0…1), applied to the current and future tracks.
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    private var player: AVAudioPlayer?
    private var delegateBox: AVAudioPlayerDelegate?
    /// Cover art for the current album/track; surfaced to the player UI and the
    /// lockscreen Now Playing info.
    @Published private(set) var artworkImage: PlatformImage?
    private var progressTimer: Timer?

    init() {
        configureAudioSession()
        wireRemoteCommands()
        PlaybackCoordinator.shared.register(self)
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
        dlog("[AudioDebug] NowPlaying.play album=\(album) queueCount=\(queue.count) startIndex=\(index)")
        self.queue = queue
        self.currentAlbum = album
        self.artworkImage = artwork
        playTrack(at: index)
    }

    func togglePlayPause() {
        guard let p = player else { return }
        if p.isPlaying { p.pause(); isPlaying = false }
        else           {
            PlaybackCoordinator.shared.stopOthers(except: self)
            p.play();  isPlaying = true
        }
        refreshNowPlayingInfo(elapsed: p.currentTime, duration: p.duration)
    }

    /// Jump to `time` (seconds, clamped to [0, duration]) in the current
    /// track. Used by the progress slider for scrubbing.
    func seek(to time: TimeInterval) {
        guard let p = player else { return }
        let clamped = max(0, min(time, p.duration))
        p.currentTime = clamped
        currentTime = clamped
        refreshNowPlayingInfo(elapsed: clamped, duration: p.duration)
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
        currentTime = 0
        duration = 0
        queue = []
        currentIndex = 0
        currentAlbum = ""
        artworkImage = nil
        stopProgressTimer()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: – Internals

    private func playTrack(at index: Int) {
        guard queue.indices.contains(index) else {
            dlog("[AudioDebug] playTrack: index \(index) out of range (queue=\(queue.count))")
            return
        }
        PlaybackCoordinator.shared.stopOthers(except: self)
        let track = queue[index]
        let exists = FileManager.default.fileExists(atPath: track.fileURL.path)
        dlog("[AudioDebug] playTrack[\(index)] title=\(track.title) url=\(track.fileURL.path) exists=\(exists)")
        do {
            let p = try AVAudioPlayer(contentsOf: track.fileURL)
            p.volume = volume
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
            self.currentTime = 0
            self.duration = p.duration
            dlog("[AudioDebug] playTrack started OK duration=\(p.duration) isPlaying=\(p.isPlaying)")
            startProgressTimer()
            refreshNowPlayingInfo(elapsed: 0, duration: p.duration)
        } catch {
            dlog("[AudioDebug] NowPlaying FAILED to play \(track.fileURL): \(error)")
        }
    }

    private func handleTrackFinished() {
        if hasNext {
            next()
        } else {
            isPlaying = false
            currentTime = 0
            stopProgressTimer()
            refreshNowPlayingInfo(elapsed: 0, duration: 0)
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                if self.duration == 0 { self.duration = p.duration }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
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

extension NowPlaying: ExclusivePlayer {
    /// Fully stop and close the Now Playing bar when a video / audiobook starts.
    func stopForExclusivity() {
        stop()
    }
}
