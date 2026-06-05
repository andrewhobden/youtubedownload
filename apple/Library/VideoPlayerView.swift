import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let fileURL: URL
    let title: String

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea(.container, edges: .horizontal)
            .navigationTitle(title)
            .onAppear {
                let p = AVPlayer(url: fileURL)
                player = p
                p.play()
            }
            .onDisappear { player?.pause() }
    }
}
