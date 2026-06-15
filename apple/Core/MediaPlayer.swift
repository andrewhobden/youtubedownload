import Foundation
import AVFoundation

/// Protocol defining common playback controls for all media types.
protocol MediaPlayer: AnyObject {
    /// Current playback state
    var isPlaying: Bool { get }
    
    /// Current playback time in seconds
    var currentTime: TimeInterval { get }
    
    /// Total duration in seconds
    var duration: TimeInterval { get }
    
    /// Playback rate (speed multiplier: 0.5x to 2.5x)
    var rate: Double { get set }
    
    /// Volume (0.0 to 1.0)
    var volume: Float { get set }
    
    /// Start or resume playback
    func play()
    
    /// Pause playback
    func pause()
    
    /// Stop playback completely and reset
    func stop()
    
    /// Seek to a specific time
    func seek(to time: TimeInterval)
    
    /// Skip forward by seconds
    func skipForward(_ seconds: TimeInterval)
    
    /// Skip backward by seconds
    func skipBackward(_ seconds: TimeInterval)
    
    /// Toggle between play and pause
    func togglePlayPause()
}

/// Default implementations for common operations
extension MediaPlayer {
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func skipForward(_ seconds: TimeInterval) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    func skipBackward(_ seconds: TimeInterval) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }
}

/// Playback session tracking current media and context
@MainActor
class PlaybackSession: ObservableObject {
    @Published var currentMediaType: MediaType?
    @Published var currentMediaID: UUID?
    @Published var currentTitle: String = ""
    @Published var currentArtist: String?
    @Published var currentArtworkPath: String?
    
    /// Context for queue management (playlist ID, album ID, etc.)
    @Published var contextID: UUID?
    @Published var contextType: PlaybackContextType?
    
    /// Current position in playback context (for queue navigation)
    @Published var contextPosition: Int = 0
    
    /// Playback start time for analytics
    var sessionStartTime: Date?
    
    /// Total time played in this session
    var totalPlayTime: TimeInterval = 0
    
    enum PlaybackContextType {
        case playlist
        case album
        case audiobook
        case videoLibrary
        case singleItem
    }
    
    func startSession(
        mediaType: MediaType,
        mediaID: UUID,
        title: String,
        artist: String? = nil,
        artworkPath: String? = nil,
        context: PlaybackContextType = .singleItem,
        contextID: UUID? = nil
    ) {
        self.currentMediaType = mediaType
        self.currentMediaID = mediaID
        self.currentTitle = title
        self.currentArtist = artist
        self.currentArtworkPath = artworkPath
        self.contextType = context
        self.contextID = contextID
        self.sessionStartTime = .now
        self.totalPlayTime = 0
    }
    
    func endSession() {
        sessionStartTime = nil
        currentMediaType = nil
        currentMediaID = nil
        currentTitle = ""
        currentArtist = nil
        currentArtworkPath = nil
        contextType = nil
        contextID = nil
    }
    
    func recordPlayTime(_ duration: TimeInterval) {
        totalPlayTime += duration
    }
}

/// Base AVPlayer wrapper providing common functionality
@MainActor
class BaseAVPlayerController: NSObject, MediaPlayer, ObservableObject {
    let player: AVPlayer
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    
    var rate: Double {
        get { Double(player.rate) }
        set { player.rate = Float(newValue) }
    }
    
    @Published var volume: Float = 1.0 {
        didSet { player.volume = volume }
    }
    
    init(url: URL) {
        self.player = AVPlayer(url: url)
        super.init()
        setupObservers()
        PlaybackCoordinator.shared.register(self)
    }
    
    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    @MainActor
    private func setupObservers() {
        // Periodic time observer for progress updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                // Keep duration current regardless of item replacement — the
                // status KVO can be attached to a stale item, leaving duration
                // at 0 (which would clamp skip/seek to the start).
                if let item = self.player.currentItem {
                    let d = item.duration.seconds
                    if d.isFinite, d > 0, self.duration != d {
                        self.duration = d
                    }
                }
            }
        }
        
        // Observe playback rate changes
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.rate > 0
            }
        }
        
        // Status + end-of-item observers are specific to the current item;
        // (re)bind them here and again whenever the item is replaced.
        observeCurrentItem()
    }
    
    /// (Re)bind observers tied to `player.currentItem`. Safe to call repeatedly;
    /// it tears down the previous bindings first. Call after replacing the item.
    @MainActor
    func observeCurrentItem() {
        statusObserver?.invalidate()
        NotificationCenter.default.removeObserver(
            self, name: .AVPlayerItemDidPlayToEndTime, object: nil
        )
        
        statusObserver = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                Task { @MainActor in
                    self.duration = item.duration.seconds
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }
    
    /// Replace the current item with a new URL and rebind item observers.
    @MainActor
    func loadItem(_ url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        currentTime = 0
        observeCurrentItem()
    }
    
    @MainActor
    @objc func playerDidFinishPlaying() {
        // Override in subclasses to handle completion
    }
    
    func play() {
        PlaybackCoordinator.shared.stopOthers(except: self)
        player.play()
    }
    
    func pause() {
        player.pause()
    }
    
    func stop() {
        player.pause()
        seek(to: 0)
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

extension BaseAVPlayerController: ExclusivePlayer {
    /// Pause when another player takes over — keeps position (audiobooks resume,
    /// videos stay put) rather than tearing the item down.
    func stopForExclusivity() {
        pause()
    }
}
