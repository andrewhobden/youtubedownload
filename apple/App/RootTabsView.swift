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
            case .videos: VideosListView().withNowPlayingBar()
            case .music:  AlbumsGridView().withNowPlayingBar()
            }
        }
        #else
        TabView {
            VideosListView()
                .withNowPlayingBar()
                .tabItem { Label(LibraryTab.videos.label,
                                 systemImage: LibraryTab.videos.systemImage) }
            AlbumsGridView()
                .withNowPlayingBar()
                .tabItem { Label(LibraryTab.music.label,
                                 systemImage: LibraryTab.music.systemImage) }
        }
        #endif
    }
}

private extension View {
    /// Insert the NowPlayingBar above the bottom safe area of the tab's
    /// content (not the TabView itself — attaching .safeAreaInset to the
    /// TabView pushes UIKit's tab bar offscreen on iOS).
    func withNowPlayingBar() -> some View {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            NowPlayingBar()
        }
    }
}
