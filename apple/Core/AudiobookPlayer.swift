import Foundation
import AVFoundation

/// One playable audio file that makes up part of an audiobook.
struct AudiobookTrack {
    let url: URL
    let duration: TimeInterval
    let title: String
}

/// Specialized audio player with audiobook-specific features like bookmarking and resume.
@MainActor
class AudiobookPlayer: BaseAVPlayerController {
    @Published var currentChapter: AudiobookChapter?
    @Published var chapters: [AudiobookChapter] = []
    @Published var bookmarks: [Bookmark] = []
    
    weak var audiobook: Audiobook?
    private var positionSaveTimer: Timer?
    
    /// Resolved audio files that make up the book, in playback order.
    private let trackURLs: [URL]
    /// Cumulative start time (in whole-book seconds) of each track.
    private let trackStartOffsets: [TimeInterval]
    /// Index of the track currently loaded into the player.
    private(set) var currentTrackIndex: Int = 0
    /// Playback speed to (re)apply on play and across track changes.
    private var desiredRate: Float = 1.0
    
    /// Position within the whole book = start of current track + position in it.
    var globalTime: TimeInterval {
        guard currentTrackIndex < trackStartOffsets.count else { return currentTime }
        return trackStartOffsets[currentTrackIndex] + currentTime
    }
    
    /// Initialize with an audiobook and its ordered tracks. Multi-file books are
    /// played back-to-back, and each file is exposed as a navigable chapter.
    init(audiobook: Audiobook, tracks: [AudiobookTrack]) {
        self.audiobook = audiobook
        self.trackURLs = tracks.map(\.url)
        
        var offsets: [TimeInterval] = []
        var acc: TimeInterval = 0
        for t in tracks {
            offsets.append(acc)
            acc += t.duration
        }
        self.trackStartOffsets = offsets
        
        // Resume on whichever track contains the saved whole-book position.
        let resumeAt = max(audiobook.currentPosition, 0)
        let startIndex = Self.trackIndex(for: resumeAt, offsets: offsets)
        
        super.init(url: tracks[startIndex].url)
        self.currentTrackIndex = startIndex
        
        // Expose each file as a chapter (only meaningful with several files).
        if tracks.count > 1 {
            self.chapters = tracks.enumerated().map { i, t in
                AudiobookChapter(
                    number: i + 1,
                    title: t.title.isEmpty ? "Chapter \(i + 1)" : t.title,
                    startTime: offsets[i],
                    duration: t.duration
                )
            }
        }
        self.bookmarks = audiobook.orderedBookmarks
        self.desiredRate = Float(audiobook.playbackSpeed > 0 ? audiobook.playbackSpeed : 1.0)
        
        // Seek within the resume track.
        let offsetInTrack = resumeAt - offsets[startIndex]
        if offsetInTrack > 0 {
            super.seek(to: offsetInTrack)
        }
        updateCurrentChapterByIndex()
        
        startPositionSaving()
    }
    
    /// First track whose range contains `time` (clamped to the last track).
    private static func trackIndex(for time: TimeInterval, offsets: [TimeInterval]) -> Int {
        guard !offsets.isEmpty else { return 0 }
        var index = 0
        for (i, offset) in offsets.enumerated() where time >= offset {
            index = i
        }
        return index
    }
    
    deinit {
        positionSaveTimer?.invalidate()
    }
    
    @MainActor
    private func startPositionSaving() {
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.saveCurrentPosition()
        }
    }
    
    @MainActor
    private func stopPositionSaving() {
        positionSaveTimer?.invalidate()
        positionSaveTimer = nil
        saveCurrentPosition() // Save one last time
    }
    
    /// Save current playback position to audiobook (whole-book seconds).
    func saveCurrentPosition() {
        guard let audiobook = audiobook else { return }
        audiobook.currentPosition = globalTime
        audiobook.updateCompletion()
        audiobook.lastPlayedAt = .now
    }
    
    override func play() {
        PlaybackCoordinator.shared.stopOthers(except: self)
        // Resume at the user's chosen speed (AVPlayer.play() would force 1x).
        player.rate = desiredRate
        audiobook?.lastPlayedAt = .now
        updateCurrentChapterByIndex()
    }
    
    override func stop() {
        stopPositionSaving()
        super.stop()
    }
    
    override func seek(to time: TimeInterval) {
        super.seek(to: time)
        updateCurrentChapterByIndex()
        saveCurrentPosition()
    }
    
    /// Advance to the next file automatically when one finishes; mark the book
    /// finished once the last file ends.
    override func playerDidFinishPlaying() {
        let next = currentTrackIndex + 1
        if next < trackURLs.count {
            loadTrack(next, autoplay: true)
        } else {
            audiobook?.isFinished = true
            saveCurrentPosition()
        }
    }
    
    /// Load a track by index, rebinding observers and preserving playback speed.
    private func loadTrack(_ index: Int, autoplay: Bool) {
        guard index >= 0, index < trackURLs.count else { return }
        currentTrackIndex = index
        loadItem(trackURLs[index])
        updateCurrentChapterByIndex()
        if autoplay {
            player.rate = desiredRate
        }
    }
    
    /// The current chapter follows the loaded track (each file is a chapter).
    private func updateCurrentChapterByIndex() {
        guard !chapters.isEmpty, currentTrackIndex < chapters.count else {
            currentChapter = nil
            return
        }
        currentChapter = chapters[currentTrackIndex]
    }
    
    /// Jump to a specific chapter (loads that file from the start).
    func jumpToChapter(_ chapter: AudiobookChapter) {
        guard let index = chapters.firstIndex(where: { $0.id == chapter.id }) else { return }
        loadTrack(index, autoplay: isPlaying)
        super.seek(to: 0)
        saveCurrentPosition()
    }
    
    /// Jump to next chapter if available
    func nextChapter() {
        let next = currentTrackIndex + 1
        guard next < trackURLs.count else { return }
        loadTrack(next, autoplay: isPlaying)
        saveCurrentPosition()
    }
    
    /// Jump to previous chapter if available
    func previousChapter() {
        let prev = currentTrackIndex - 1
        guard prev >= 0 else { return }
        loadTrack(prev, autoplay: isPlaying)
        saveCurrentPosition()
    }
    
    /// Create a bookmark at the current position
    func createBookmark(title: String, note: String? = nil) -> Bookmark {
        let bookmark = Bookmark(
            audiobook: audiobook,
            timestamp: currentTime,
            title: title,
            note: note
        )
        bookmarks.append(bookmark)
        bookmarks.sort { $0.timestamp < $1.timestamp }
        return bookmark
    }
    
    /// Jump to a bookmark
    func jumpToBookmark(_ bookmark: Bookmark) {
        seek(to: bookmark.timestamp)
    }
    
    /// Delete a bookmark
    func deleteBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }
    
    /// Set playback speed (0.5x to 2.5x)
    func setPlaybackSpeed(_ speed: Double) {
        let clampedSpeed = min(max(speed, 0.5), 2.5)
        desiredRate = Float(clampedSpeed)
        rate = clampedSpeed
        audiobook?.playbackSpeed = clampedSpeed
    }
    
    /// Start a sleep timer that will fade out and pause after duration
    func startSleepTimer(duration: TimeInterval, fadeOutDuration: TimeInterval = 10.0) {
        // Stop any existing timer
        stopSleepTimer()
        
        // Schedule fade out
        let fadeStartTime = duration - fadeOutDuration
        if fadeStartTime > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeStartTime) { [weak self] in
                self?.fadeOutAndPause(duration: fadeOutDuration)
            }
        } else {
            // If duration is shorter than fade, just pause immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.pause()
            }
        }
    }
    
    func stopSleepTimer() {
        // Timer cancellation would be tracked with a stored DispatchWorkItem
        // For now, this is a placeholder
    }
    
    private func fadeOutAndPause(duration: TimeInterval) {
        let steps = 20
        let stepDuration = duration / Double(steps)
        let volumeStep = volume / Float(steps)
        
        var currentStep = 0
        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            self.volume = max(0, self.volume - volumeStep)
            
            if currentStep >= steps {
                timer.invalidate()
                self.pause()
                self.volume = 1.0 // Reset volume for next playback
            }
        }
    }
}
