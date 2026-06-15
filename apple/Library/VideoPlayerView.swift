import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    let fileURL: URL
    let title: String
    var onDismiss: (() -> Void)?

    @StateObject private var controller: EnhancedVideoPlayerController
    @State private var showControls = false
    @State private var controlsTimer: Timer?
    @State private var showSubtitlePicker = false
    @State private var showPlaybackSpeedPicker = false
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @Environment(\.dismiss) private var dismiss
    
    init(fileURL: URL, title: String, onDismiss: (() -> Void)? = nil) {
        dlog("[VideoDebug] VideoPlayerView.init fileURL=\(fileURL.absoluteString) " +
              "scheme=\(fileURL.scheme ?? "nil") title=\(title)")
        self.fileURL = fileURL
        self.title = title
        self.onDismiss = onDismiss
        self._controller = StateObject(wrappedValue: EnhancedVideoPlayerController(url: fileURL))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Video layer
            VideoPlayerLayer(player: controller.player, controller: controller)
                .ignoresSafeArea()
                .onTapGesture {
                    toggleControls()
                }
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            handleSwipeGesture(value)
                        }
                )
            
            // Custom controls overlay
            if showControls {
                VStack {
                    // Top bar
                    topBar
                    
                    Spacer()
                    
                    // Center play/pause
                    centerControls
                    
                    Spacer()
                    
                    // Bottom controls
                    bottomControls
                }
                .transition(.opacity)
            }
            
            // Loading indicator
            if controller.isBuffering {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
        .statusBar(hidden: !showControls)
        .onAppear {
            dlog("[VideoDebug] VideoPlayerView.body.onAppear -> play(); item=\(controller.player.currentItem != nil), status=\(controller.player.currentItem?.status.rawValue ?? -99)")
            controller.play()
            startControlsTimer()
        }
        .onDisappear {
            controller.pause()
            controlsTimer?.invalidate()
        }
        .sheet(isPresented: $showSubtitlePicker) {
            SubtitlePickerSheet(controller: controller)
        }
        .sheet(isPresented: $showPlaybackSpeedPicker) {
            PlaybackSpeedSheet(controller: controller)
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if controller.duration > 0 {
                    Text(formatDuration(controller.duration))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            Button {
                showSubtitlePicker = true
            } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            if controller.isPiPSupported {
                Button {
                    controller.togglePictureInPicture()
                } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            .allowsHitTesting(false)
        )
    }
    
    // MARK: - Center Controls
    
    private var centerControls: some View {
        HStack(spacing: 60) {
            // Rewind 15s
            Button {
                controller.skip(by: -15)
                HapticFeedback.trigger(.medium)
                resetControlsTimer()
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            // Play/Pause
            Button {
                if controller.isPlaying {
                    controller.pause()
                } else {
                    controller.play()
                    startControlsTimer()
                }
                HapticFeedback.trigger(.medium)
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                    )
            }
            
            // Forward 15s
            Button {
                controller.skip(by: 15)
                HapticFeedback.trigger(.medium)
                resetControlsTimer()
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Progress bar
            VStack(spacing: 8) {
                // Timeline (draggable scrubber)
                GeometryReader { geometry in
                    let displayProgress = isScrubbing ? scrubProgress : controller.progress
                    ZStack(alignment: .leading) {
                        // Larger transparent hit area
                        Color.white.opacity(0.001)
                            .frame(height: 44)
                        
                        // Background track
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 4)
                        
                        // Played portion
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(0, geometry.size.width * displayProgress), height: 4)
                        
                        // Scrubber handle
                        Circle()
                            .fill(Color.white)
                            .frame(width: isScrubbing ? 18 : 12, height: isScrubbing ? 18 : 12)
                            .offset(x: max(0, min(geometry.size.width - (isScrubbing ? 18 : 12),
                                                  geometry.size.width * displayProgress - (isScrubbing ? 9 : 6))))
                            .animation(.easeOut(duration: 0.1), value: isScrubbing)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isScrubbing = true
                                scrubProgress = max(0, min(1, value.location.x / geometry.size.width))
                                controlsTimer?.invalidate()
                            }
                            .onEnded { value in
                                let p = max(0, min(1, value.location.x / geometry.size.width))
                                if controller.duration > 0 {
                                    controller.seek(to: p * controller.duration)
                                }
                                isScrubbing = false
                                startControlsTimer()
                            }
                    )
                }
                .frame(height: 44)
                
                // Time labels
                HStack {
                    Text(formatDuration(isScrubbing ? scrubProgress * controller.duration : controller.currentTime))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text(formatDuration(controller.duration))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Control buttons
            HStack(spacing: 16) {
                Button {
                    showPlaybackSpeedPicker = true
                } label: {
                    Text("\(String(format: "%.1fx", controller.playbackRate))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 32)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }

                // Volume
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                    Slider(value: $controller.volume, in: 0...1)
                        .tint(.white)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .allowsHitTesting(false)
        )
    }
    
    // MARK: - Helpers
    
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            startControlsTimer()
        }
    }
    
    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            if controller.isPlaying {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls = false
                }
            }
        }
    }
    
    private func resetControlsTimer() {
        if showControls {
            startControlsTimer()
        }
    }
    
    private func handleSwipeGesture(_ value: DragGesture.Value) {
        let horizontalAmount = value.translation.width
        let verticalAmount = value.translation.height
        
        if abs(horizontalAmount) > abs(verticalAmount) {
            // Horizontal swipe - seek
            let seekAmount = horizontalAmount / 10.0
            controller.skip(by: seekAmount)
        } else {
            // Vertical swipe - volume/brightness (left/right side)
            let midX = UIScreen.main.bounds.width / 2
            if value.startLocation.x < midX {
                // Left side - brightness
                adjustBrightness(by: -verticalAmount / 500)
            } else {
                // Right side - volume
                adjustVolume(by: -verticalAmount / 500)
            }
        }
    }
    
    private func adjustBrightness(by amount: CGFloat) {
        let current = UIScreen.main.brightness
        UIScreen.main.brightness = max(0, min(1, current + amount))
    }
    
    private func adjustVolume(by amount: CGFloat) {
        let current = Double(controller.volume)
        controller.volume = Float(max(0, min(1, current + Double(amount))))
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Video Player Layer

private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    let controller: EnhancedVideoPlayerController
    
    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        controller.configurePiP(with: view.playerLayer)
        return view
    }
    
    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        uiView.playerLayer.player = player
    }
    
    static func dismantleUIView(_ uiView: PlayerHostView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

/// A UIView whose backing layer is an AVPlayerLayer, so the video surface
/// always tracks the view's bounds automatically (no manual frame management).
private final class PlayerHostView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

// MARK: - Subtitle Picker

private struct SubtitlePickerSheet: View {
    @ObservedObject var controller: EnhancedVideoPlayerController
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue, .purple, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Subtitles")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
                .padding()
                
                ScrollView {
                    VStack(spacing: 0) {
                        pickerRow(label: "Off", selected: controller.currentSubtitleTrack == nil) {
                            controller.selectSubtitle(nil)
                            dismiss()
                        }
                        
                        ForEach(controller.availableSubtitles) { track in
                            Divider().background(Color.white.opacity(0.2))
                            pickerRow(
                                label: track.displayName,
                                selected: controller.currentSubtitleTrack?.id == track.id
                            ) {
                                controller.selectSubtitle(track)
                                dismiss()
                            }
                        }
                        
                        if controller.availableSubtitles.isEmpty {
                            Text("No subtitles available for this video.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.top, 24)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private func pickerRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundColor(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Playback Speed Sheet

private struct PlaybackSpeedSheet: View {
    @ObservedObject var controller: EnhancedVideoPlayerController
    @Environment(\.dismiss) private var dismiss
    
    let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue, .purple, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Playback Speed")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
                .padding()
                
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(speeds.enumerated()), id: \.element) { index, speed in
                            if index > 0 {
                                Divider().background(Color.white.opacity(0.2))
                            }
                            Button {
                                controller.setPlaybackRate(speed)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Text(speed == 1.0 ? "Normal" : String(format: "%.2fx", speed))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if abs(controller.playbackRate - speed) < 0.01 {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                            .fontWeight(.bold)
                                    }
                                }
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
    }
}
