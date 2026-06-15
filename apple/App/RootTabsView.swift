import SwiftUI
import SwiftData
import UIKit

/// On iPhone we get a TabView; on iPad and Catalyst we expand to a sidebar
/// `NavigationSplitView`. Both back the same two libraries.
struct RootTabsView: View {

    enum LibraryTab: String, Hashable, CaseIterable, Identifiable {
        case search
        case videos
        case music
        case audiobooks
        case playlists
        var id: String { rawValue }

        var label: String {
            switch self {
            case .search: return "Home"
            case .videos: return "Videos"
            case .music:  return "Music Albums"
            case .audiobooks: return "Audiobooks"
            case .playlists: return "Playlists"
            }
        }

        var systemImage: String {
            switch self {
            case .search: return "house.fill"
            case .videos: return "play.rectangle"
            case .music:  return "music.note.list"
            case .audiobooks: return "book.fill"
            case .playlists: return "music.note.list"
            }
        }
    }

    @EnvironmentObject private var mediaRoot: MediaRoot
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.modelContext) private var modelContext

    @State private var selection: LibraryTab? = .videos

    // iPhone TabView state. Tapping the Search tab bumps `searchResetToken`,
    // which YouTubeSearchView observes to clear its query and return to the
    // landing page.
    @State private var tabSelection: LibraryTab = .search
    @State private var searchResetToken = 0

    /// Selection binding whose setter fires on every tap of a tab (including a
    /// re-tap of the already-active tab on iOS 16+). Whenever Search is tapped
    /// we increment the reset token so the search view starts fresh.
    private var tabSelectionBinding: Binding<LibraryTab> {
        Binding(
            get: { tabSelection },
            set: { newValue in
                if newValue == .search { searchResetToken &+= 1 }
                tabSelection = newValue
            }
        )
    }

    init() {
        #if !targetEnvironment(macCatalyst)
        Self.configureTabBarAppearance()
        #endif
    }

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
            case .search: YouTubeSearchView().withNowPlayingBar()
            case .videos: VideosListView().withNowPlayingBar()
            case .music:  AlbumsGridView().withNowPlayingBar()
            case .audiobooks: AudiobooksGridView().withNowPlayingBar()
            case .playlists: PlaylistManagementView().withNowPlayingBar()
            }
        }
        #else
        TabView(selection: tabSelectionBinding) {
            YouTubeSearchView(resetToken: searchResetToken)
                .withNowPlayingBar()
                .tabItem { Label(LibraryTab.search.label,
                                 systemImage: LibraryTab.search.systemImage) }
                .tag(LibraryTab.search)
            VideosListView()
                .withNowPlayingBar()
                .tabItem { Label(LibraryTab.videos.label,
                                 systemImage: LibraryTab.videos.systemImage) }
                .tag(LibraryTab.videos)
            AlbumsGridView()
                .withNowPlayingBar()
                .tabItem { Label(LibraryTab.music.label,
                                 systemImage: LibraryTab.music.systemImage) }
                .tag(LibraryTab.music)
            AudiobooksGridView()
                .withNowPlayingBar()
                .tabItem { Label(LibraryTab.audiobooks.label,
                                 systemImage: LibraryTab.audiobooks.systemImage) }
                .tag(LibraryTab.audiobooks)
            PlaylistManagementView()
                .withNowPlayingBar()
                .tabItem { Label(LibraryTab.playlists.label,
                                 systemImage: LibraryTab.playlists.systemImage) }
                .tag(LibraryTab.playlists)
        }
        .tint(.white)
        .downloadToast(downloads)
        .onAppear {
            downloads.configure(context: modelContext, mediaRoot: mediaRoot)
        }
        #endif
    }

    #if !targetEnvironment(macCatalyst)
    /// Give the tab bar a distinct frosted-glass panel so it reads as its own
    /// surface instead of dissolving into the app's vibrant gradient
    /// background. Selected items are bright white; unselected are dimmed —
    /// a high-contrast, Spotify-style treatment that stays legible over any
    /// gradient colour.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        // A dark frosted material keeps the bar reading as a separate panel
        // regardless of the gradient hue behind it.
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterialDark)
        appearance.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        // Hairline separator along the top edge to define the panel.
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.18)

        let selected = UIColor.white
        let normal = UIColor.white.withAlphaComponent(0.55)

        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [
                .foregroundColor: selected,
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [
                .foregroundColor: normal,
                .font: UIFont.systemFont(ofSize: 10, weight: .medium)
            ]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    #endif
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
