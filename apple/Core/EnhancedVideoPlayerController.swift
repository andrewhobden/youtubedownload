import Foundation
import AVFoundation
import AVKit
import SwiftUI

struct SubtitleTrack: Identifiable, Equatable {
    let id = UUID()
    let displayName: String
    let languageCode: String?
    let mediaSelectionOption: AVMediaSelectionOption?
}

/// Enhanced video player controller with all modern features
@MainActor
final class EnhancedVideoPlayerController: BaseAVPlayerController {
    
    // MARK: - Published Properties
    
    @Published var isBuffering = false
    @Published var availableSubtitles: [SubtitleTrack] = []
    @Published var currentSubtitleTrack: SubtitleTrack?
    @Published var playbackRate: Float = 1.0
    @Published var isPipActive = false
    
    // MARK: - Computed Properties
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    // MARK: - Private Properties
    
    private var pipController: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    
    // MARK: - Initialization
    
    override init(url: URL) {
        dlog("[VideoDebug] EnhancedVideoPlayerController.init url=\(url.absoluteString)")
        super.init(url: url)
        setupBufferMonitoring()
        if let item = player.currentItem {
            Task { await extractSubtitleTracks(from: item) }
        }
    }
    
    deinit {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()
        pipController?.delegate = nil
    }
    
    // MARK: - Video Loading
    
    func loadVideo(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        
        // Extract subtitle tracks
        Task {
            await extractSubtitleTracks(from: playerItem)
        }
    }
    
    // MARK: - Subtitle Support
    
    private func extractSubtitleTracks(from playerItem: AVPlayerItem) async {
        guard let asset = playerItem.asset as? AVURLAsset else { return }
        
        var tracks: [SubtitleTrack] = []
        
        // Check for embedded subtitle tracks
        do {
            if let legibleGroup = try await asset.loadMediaSelectionGroup(for: .legible) {
                for option in legibleGroup.options {
                    let displayName = option.displayName
                    let languageCode = option.extendedLanguageTag
                    tracks.append(SubtitleTrack(
                        displayName: displayName,
                        languageCode: languageCode,
                        mediaSelectionOption: option
                    ))
                }
            }
        } catch {
            print("Failed to load subtitle tracks: \(error)")
        }
        
        await MainActor.run {
            self.availableSubtitles = tracks
        }
    }
    
    func selectSubtitle(_ track: SubtitleTrack?) {
        guard let playerItem = player.currentItem else { return }
        
        if let track = track,
           let group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
           let option = track.mediaSelectionOption {
            playerItem.select(option, in: group)
            currentSubtitleTrack = track
        } else {
            // Disable subtitles
            if let group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                playerItem.select(nil, in: group)
            }
            currentSubtitleTrack = nil
        }
    }
    
    // MARK: - Playback Speed
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player.rate = rate
    }
    
    override func play() {
        #if os(iOS)
        // Use the playback category so video is audible even with the ring/mute
        // switch on, and so playback is reliable on a real device.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        dlog("[VideoDebug] EnhancedVideoPlayerController.play() status=\(player.currentItem?.status.rawValue ?? -99) error=\(String(describing: player.currentItem?.error))")
        super.play()
        player.rate = playbackRate
    }
    
    // MARK: - Skip Controls
    
    func skip(by seconds: Double) {
        let newTime = currentTime + seconds
        let clampedTime = max(0, min(duration, newTime))
        seek(to: clampedTime)
    }
    
    // MARK: - Picture in Picture
    
    /// Wire PiP to the actual on-screen AVPlayerLayer. Must be called by the
    /// view once its player layer exists — PiP only works with the layer that
    /// is really being displayed (a detached layer never activates).
    func configurePiP(with layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        playerLayer = layer
        guard pipController == nil,
              let pip = AVPictureInPictureController(playerLayer: layer) else { return }
        pip.delegate = self
        pipController = pip
    }
    
    var isPiPSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }
    
    func togglePictureInPicture() {
        guard let pipController = pipController else { return }
        
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }
    
    // MARK: - Buffer Monitoring
    
    private func setupBufferMonitoring() {
        statusObserver = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.updateBufferingState(for: item)
            }
        }
        
        bufferObserver = player.currentItem?.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.updateBufferingState(for: item)
            }
        }
    }
    
    private func updateBufferingState(for item: AVPlayerItem) {
        if item.status == .readyToPlay {
            isBuffering = item.isPlaybackBufferEmpty && player.rate == 0
        } else {
            isBuffering = item.status == .unknown
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension EnhancedVideoPlayerController: AVPictureInPictureControllerDelegate {
    
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPipActive = true
        }
    }
    
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPipActive = false
        }
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            isPipActive = false
            print("PiP failed to start: \(error.localizedDescription)")
        }
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // Restore the player UI when coming back from PiP
        Task { @MainActor in
            completionHandler(true)
        }
    }
}
