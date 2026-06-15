import Foundation
import AVFoundation
import SwiftUI

/// Video player controller with custom controls and subtitle support.
@MainActor
class VideoPlayerController: BaseAVPlayerController {
    @Published var showControls: Bool = true
    @Published var hasSubtitles: Bool = false
    @Published var subtitlesEnabled: Bool = false
    
    weak var videoItem: VideoItem?
    private var controlsHideTimer: Timer?
    
    init(videoItem: VideoItem, url: URL) {
        self.videoItem = videoItem
        super.init(url: url)
        checkForSubtitles()
    }
    
    deinit {
        controlsHideTimer?.invalidate()
    }
    
    /// Check if subtitle file exists for this video
    private func checkForSubtitles() {
        hasSubtitles = videoItem?.subtitleRelPath != nil
    }
    
    /// Load subtitle track if available
    func loadSubtitles(from url: URL) {
        // AVPlayer subtitle loading would be implemented here
        // This is a placeholder for the actual AVMediaSelectionGroup logic
        subtitlesEnabled = true
    }
    
    /// Toggle subtitle display
    func toggleSubtitles() {
        subtitlesEnabled.toggle()
        // Would enable/disable subtitle track here
    }
    
    /// Show controls and start auto-hide timer
    func showControlsWithAutoHide(duration: TimeInterval = 5.0) {
        showControls = true
        controlsHideTimer?.invalidate()
        
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            if self?.isPlaying == true {
                self?.showControls = false
            }
        }
    }
    
    /// User interaction detected - show controls
    func handleUserInteraction() {
        showControlsWithAutoHide()
    }
    
    override func play() {
        super.play()
        showControlsWithAutoHide()
        videoItem?.lastPlayedAt = .now
    }
    
    override func pause() {
        super.pause()
        showControls = true
        controlsHideTimer?.invalidate()
        savePosition()
    }
    
    override func stop() {
        super.stop()
        savePosition()
    }
    
    /// Save current playback position for resume
    func savePosition() {
        guard let videoItem = videoItem else { return }
        videoItem.lastPosition = currentTime
    }
    
    /// Resume from last saved position
    func resumeFromLastPosition() {
        guard let lastPos = videoItem?.lastPosition, lastPos > 0 else { return }
        seek(to: lastPos)
    }
    
    /// Mark video as played and increment counter
    func markAsPlayed() {
        videoItem?.recordPlay()
    }
    
    /// Enable picture-in-picture if supported
    func enablePictureInPicture() {
        // PiP setup would happen here using AVPictureInPictureController
        // This is a placeholder
    }
}
