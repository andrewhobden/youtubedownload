import SwiftUI
import SwiftData

/// Lightweight diagnostic logging to the unified log (Xcode / Console.app).
/// Compiled out of release builds, so it has zero cost in shipping binaries
/// while remaining handy when diagnosing playback on a real device.
func dlog(_ message: String) {
    #if DEBUG
    NSLog("%@", message)
    #endif
}

@main
struct YouTubeLibraryApp: App {

    @StateObject private var mediaRoot = MediaRoot()
    @StateObject private var nowPlaying = NowPlaying()
    @StateObject private var downloads = DownloadManager()
    @StateObject private var youtubeAuth = YouTubeAuth.shared

    init() { SmokeTest.runIfRequested() }

    var body: some Scene {
        #if targetEnvironment(macCatalyst)
        WindowGroup {
            RootTabsView()
                .environmentObject(mediaRoot)
                .environmentObject(nowPlaying)
                .environmentObject(downloads)
                .environmentObject(youtubeAuth)
                .task { try? PythonBridge.shared.bootstrap() }
        }
        .modelContainer(for: [VideoItem.self, Album.self, Track.self, Audiobook.self, Bookmark.self, Playlist.self, PlaylistItem.self, SmartPlaylist.self, UserProfile.self])
        .commands { AppCommands() }
        #else
        WindowGroup {
            RootTabsView()
                .environmentObject(mediaRoot)
                .environmentObject(nowPlaying)
                .environmentObject(downloads)
                .environmentObject(youtubeAuth)
                .task { try? PythonBridge.shared.bootstrap() }
        }
        .modelContainer(for: [VideoItem.self, Album.self, Track.self, Audiobook.self, Bookmark.self, Playlist.self, PlaylistItem.self, SmartPlaylist.self, UserProfile.self])
        #endif
    }
}

/// Catalyst settings live in the main window for v1 — Settings scene
/// isn't available under Mac Catalyst's iOS-emulating compile target on
/// this Xcode. Surface it as a toolbar button instead (TBD).
struct SettingsView: View {
    @EnvironmentObject var mediaRoot: MediaRoot
    @State private var showingPicker = false

    var body: some View {
        Form {
            Section("Download folder") {
                HStack {
                    Text(mediaRoot.rootURL?.path ?? "(none chosen)")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { showingPicker = true }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 160)
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                mediaRoot.setBookmarkedFolder(url)
            }
        }
    }
}
