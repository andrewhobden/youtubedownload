import SwiftUI

/// On iPhone we get a TabView; on iPad and Catalyst we expand to a sidebar
/// `NavigationSplitView`. Both back the same two libraries.
struct RootTabsView: View {

    enum LibraryTab: String, Hashable, CaseIterable, Identifiable {
        case videos
        case music
        var id: String { rawValue }

        var label: String {
            switch self {
            case .videos: return "Videos"
            case .music:  return "Music Albums"
            }
        }

        var systemImage: String {
            switch self {
            case .videos: return "play.rectangle"
            case .music:  return "music.note.list"
            }
        }
    }

    @State private var selection: LibraryTab? = .videos

    var body: some View {
        content
            // The mini-player sits in the safe-area inset so every screen
            // shows it whenever audio is active; tabs/sidebar still own
            // the bottom edge.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingBar()
            }
    }

    @ViewBuilder private var content: some View {
        #if targetEnvironment(macCatalyst)
        NavigationSplitView {
            List(LibraryTab.allCases, selection: $selection) { tab in
                NavigationLink(value: tab) {
                    Label(tab.label, systemImage: tab.systemImage)
                }
            }
            .navigationTitle("Library")
        } detail: {
            switch selection ?? .videos {
            case .videos: VideosListView()
            case .music:  AlbumsGridView()
            }
        }
        #else
        TabView {
            VideosListView()
                .tabItem { Label(LibraryTab.videos.label,
                                 systemImage: LibraryTab.videos.systemImage) }
            AlbumsGridView()
                .tabItem { Label(LibraryTab.music.label,
                                 systemImage: LibraryTab.music.systemImage) }
        }
        #endif
    }
}
