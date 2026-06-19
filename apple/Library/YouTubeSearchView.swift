import SwiftUI
import UIKit

/// A category the user is searching within (e.g. "Music Videos"). The `term`
/// is appended to the user's typed query so results stay within the category.
struct SearchScope: Equatable, Identifiable {
    let title: String
    let term: String
    /// Download types offered for this category (empty offers all options).
    /// e.g. Music Videos offers both video and audio.
    let downloads: [LibraryDestination]
    var id: String { title }
}

/// One selectable secondary filter (e.g. a genre or a length band). `queryTerm`
/// is appended to the YouTube query; duration bounds (seconds), when set,
/// additionally narrow the displayed results client-side.
struct SearchFilterOption: Identifiable, Equatable {
    let id: String
    let label: String
    var queryTerm: String? = nil
    var minDuration: Double? = nil
    var maxDuration: Double? = nil
}

/// A group of mutually-exclusive secondary filters (e.g. "Genre", "Length").
struct SearchFilterGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let options: [SearchFilterOption]
}

/// Secondary filters offered within a given category. Empty for categories
/// where they don't apply (e.g. Creators).
func secondaryFilterGroups(for scope: SearchScope) -> [SearchFilterGroup] {
    func genres(_ names: [String]) -> [SearchFilterOption] {
        names.map { SearchFilterOption(id: $0.lowercased(), label: $0, queryTerm: $0.lowercased()) }
    }
    switch scope.title {
    case "Music", "Music Videos":
        return [
            SearchFilterGroup(id: "genre", title: "Genre", systemImage: "guitars",
                options: genres(["Pop", "Rock", "Hip-Hop", "R&B", "Electronic",
                                 "Jazz", "Classical", "Country", "Metal", "Indie"])),
            SearchFilterGroup(id: "length", title: "Length", systemImage: "clock",
                options: [
                    SearchFilterOption(id: "short", label: "Short (< 3 min)", maxDuration: 180),
                    SearchFilterOption(id: "medium", label: "Medium (3–6 min)", minDuration: 180, maxDuration: 360),
                    SearchFilterOption(id: "long", label: "Long (> 6 min)", minDuration: 360),
                ])
        ]
    case "Movies & Shows":
        return [
            SearchFilterGroup(id: "genre", title: "Genre", systemImage: "theatermasks",
                options: genres(["Comedy", "Thriller", "Drama", "Action", "Horror",
                                 "Sci-Fi", "Romance", "Mystery", "Documentary", "Animation"])),
            SearchFilterGroup(id: "length", title: "Length", systemImage: "clock",
                options: [
                    SearchFilterOption(id: "short", label: "Short (< 40 min)", maxDuration: 2400),
                    SearchFilterOption(id: "feature", label: "Full Movie (> 40 min)",
                                       queryTerm: "full movie", minDuration: 2400),
                ])
        ]
    case "Audiobooks":
        return [
            SearchFilterGroup(id: "genre", title: "Genre", systemImage: "books.vertical",
                options: genres(["Fiction", "Non-Fiction", "Mystery", "Sci-Fi", "Fantasy",
                                 "Romance", "Biography", "Self-Help", "History"])),
            SearchFilterGroup(id: "length", title: "Length", systemImage: "clock",
                options: [
                    SearchFilterOption(id: "short", label: "Under 1 hr", maxDuration: 3600),
                    SearchFilterOption(id: "medium", label: "Over 1 hr", minDuration: 3600),
                    SearchFilterOption(id: "long", label: "Over 3 hrs", minDuration: 10800),
                ])
        ]
    default:
        return []
    }
}

struct YouTubeSearchView: View {
    /// Bumped by the parent whenever the Search tab is tapped; clears the
    /// current query and returns to the landing page.
    var resetToken: Int = 0

    @StateObject private var searchService = YouTubeSearchService()
    @State private var searchText = ""
    @State private var searchFilter: SearchFilter = .all
    @State private var sortOrder: SearchSortOrder = .relevance
    @State private var showFilters = false
    @State private var selectedResult: YouTubeSearchResult?
    @State private var scope: SearchScope?
    /// Selected secondary filter per group id (e.g. "genre", "length").
    @State private var selectedFilters: [String: SearchFilterOption] = [:]
    @State private var showingDownloads = false
    @State private var showingLogin = false
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var auth: YouTubeAuth
    
    var body: some View {
        ZStack {
            // Animated gradient background
            AnimatedGradientBackground()
                .ignoresSafeArea()
            
            // Main content - scrolls behind header
            VStack(spacing: 0) {
                // Results
                if searchService.isSearching {
                    loadingView
                } else if let error = searchService.error {
                    errorView(error)
                } else if searchService.results.isEmpty && (!searchText.isEmpty || scope != nil) {
                    emptyStateView
                } else if !searchService.results.isEmpty {
                    resultsScrollView
                } else {
                    landingView
                }
            }
            
            // Floating search header - stays on top
            VStack(spacing: 0) {
                searchHeader
                
                // Filter chips
                if showFilters {
                    filterChips
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
            }
        }
        .sheet(item: $selectedResult) { result in
            ResultDetailSheet(
                result: result,
                downloadFilter: scope?.downloads ?? []
            )
        }
        .sheet(isPresented: $showingDownloads) {
            DownloadsView()
        }
        .sheet(isPresented: $showingLogin) {
            YouTubeLoginView()
        }
        .onChange(of: resetToken) { resetSearch() }
    }
    
    /// Clear the query, filters and results so the Search tab always opens on
    /// its initial landing page.
    private func resetSearch() {
        searchText = ""
        searchFilter = .all
        sortOrder = .relevance
        showFilters = false
        selectedResult = nil
        scope = nil
        selectedFilters = [:]
        searchService.clearResults()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
    
    // MARK: - Search Header
    
    private var searchHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Search field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 18, weight: .medium))
                    
                    TextField(searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .font(.system(size: 17))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            if scope != nil {
                                performSearch()
                            } else {
                                searchService.clearResults()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.4))
                                .font(.system(size: 16))
                        }
                        .pressAnimation()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        )
                )
                
                // Account / YouTube sign-in button
                Button {
                    showingLogin = true
                    HapticFeedback.trigger(.light)
                } label: {
                    Image(systemName: auth.isSignedIn
                          ? "person.crop.circle.badge.checkmark"
                          : "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundColor(auth.isSignedIn ? .green : .white)
                        .frame(width: 44, height: 44)
                }
                .pressAnimation()

                // Downloads button
                Button {
                    showingDownloads = true
                    HapticFeedback.trigger(.light)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if downloads.activeCount > 0 {
                                Text("\(downloads.activeCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Circle().fill(.red))
                                    .offset(x: 6, y: -4)
                            }
                        }
                }
                .pressAnimation()
                
                // Filter button
                Button {
                    withAnimation(.smooth) {
                        showFilters.toggle()
                    }
                    HapticFeedback.trigger(.light)
                } label: {
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(showFilters ? Color.blue.opacity(0.3) : Color.clear)
                        )
                }
                .pressAnimation()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            if let scope = scope {
                scopeLabel(scope)
                let groups = secondaryFilterGroups(for: scope)
                if !groups.isEmpty {
                    secondaryFilterBar(groups)
                }
            }
        }
    }

    /// Horizontal row of secondary-filter menus (Genre, Length, …) shown beneath
    /// the category label.
    private func secondaryFilterBar(_ groups: [SearchFilterGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(groups) { group in
                    Menu {
                        Button { toggleFilter(nil, in: group) } label: {
                            if selectedFilters[group.id] == nil {
                                Label("Any \(group.title)", systemImage: "checkmark")
                            } else {
                                Text("Any \(group.title)")
                            }
                        }
                        ForEach(group.options) { option in
                            Button { toggleFilter(option, in: group) } label: {
                                if selectedFilters[group.id]?.id == option.id {
                                    Label(option.label, systemImage: "checkmark")
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        filterChipLabel(group)
                    }
                    .pressAnimation()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private func filterChipLabel(_ group: SearchFilterGroup) -> some View {
        let selected = selectedFilters[group.id]
        return HStack(spacing: 6) {
            Image(systemName: group.systemImage)
                .font(.system(size: 12))
            Text(selected?.label ?? group.title)
                .font(.system(size: 13, weight: selected == nil ? .medium : .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(selected == nil ? .white.opacity(0.85) : .white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            if selected == nil {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            } else {
                Capsule().fill(Color.blue.opacity(0.5))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
        }
    }
    
    /// Pill shown beneath the search box indicating the active category. The
    /// category isn't placed in the text field; instead it scopes the search.
    private func scopeLabel(_ scope: SearchScope) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.85))
            
            (Text("Searching in ")
                .foregroundColor(.white.opacity(0.7))
             + Text("'\(scope.title)'")
                .foregroundColor(.white)
                .fontWeight(.semibold))
                .font(.system(size: 13))
                .lineLimit(1)
            
            Spacer(minLength: 0)
            
            Button {
                clearScope()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(6)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .pressAnimation()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        )
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Filter Chips
    
    private var filterChips: some View {
        VStack(spacing: 12) {
            // Type filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Text("Type:")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 14, weight: .medium))
                    
                    FilterChip(title: "All", isSelected: searchFilter == .all) {
                        searchFilter = .all
                        performSearch()
                    }
                    FilterChip(title: "Videos", isSelected: searchFilter == .video) {
                        searchFilter = .video
                        performSearch()
                    }
                    FilterChip(title: "Playlists", isSelected: searchFilter == .playlist) {
                        searchFilter = .playlist
                        performSearch()
                    }
                    FilterChip(title: "Channels", isSelected: searchFilter == .channel) {
                        searchFilter = .channel
                        performSearch()
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Sort order
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Text("Sort:")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 14, weight: .medium))
                    
                    FilterChip(title: "Relevance", isSelected: sortOrder == .relevance) {
                        sortOrder = .relevance
                        performSearch()
                    }
                    FilterChip(title: "Upload Date", isSelected: sortOrder == .uploadDate) {
                        sortOrder = .uploadDate
                        performSearch()
                    }
                    FilterChip(title: "View Count", isSelected: sortOrder == .viewCount) {
                        sortOrder = .viewCount
                        performSearch()
                    }
                    FilterChip(title: "Rating", isSelected: sortOrder == .rating) {
                        sortOrder = .rating
                        performSearch()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
        )
    }
    
    // MARK: - Results
    
    /// Results after applying any client-side (duration) secondary filters.
    private var visibleResults: [YouTubeSearchResult] {
        var results = searchService.results
        for option in selectedFilters.values {
            if let minD = option.minDuration {
                results = results.filter { $0.duration == 0 || $0.duration >= minD }
            }
            if let maxD = option.maxDuration {
                results = results.filter { $0.duration == 0 || $0.duration <= maxD }
            }
        }
        return results
    }

    /// Extra top padding so the first result clears the secondary filter row.
    private var extraFilterBarPadding: CGFloat {
        guard let scope, !secondaryFilterGroups(for: scope).isEmpty else { return 0 }
        return 48
    }

    private var resultsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(visibleResults) { result in
                    SearchResultCard(result: result) {
                        selectedResult = result
                    }
                }
                
                seeMoreFooter
            }
            .padding(.horizontal, 20)
            .padding(.top, 120 + extraFilterBarPadding) // Padding for search bar and filters
            .padding(.bottom, 20)
        }
    }
    
    @ViewBuilder
    private var seeMoreFooter: some View {
        if searchService.isLoadingMore {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if searchService.canLoadMore {
            Button {
                HapticFeedback.trigger(.light)
                Task { await searchService.loadMore() }
            } label: {
                HStack(spacing: 8) {
                    Text("See More")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            .pressAnimation()
            .padding(.top, 4)
        }
    }
    
    // MARK: - States
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)
            
            Text("Searching YouTube...")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red.opacity(0.8))
            
            Text("Search Error")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                performSearch()
            } label: {
                Text("Try Again")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            }
            .pressAnimation()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.4))
            
            Text("No Results")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text("Try different keywords or filters")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var landingView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.6))
                
                VStack(spacing: 8) {
                    Text("Search YouTube")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Find videos, music, and playlists")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    TrendingChip(icon: "music.quarternote.3", text: "Music") {
                        applyScope(SearchScope(title: "Music", term: "music", downloads: [.music]))
                    }
                    TrendingChip(icon: "music.note", text: "Music Videos") {
                        applyScope(SearchScope(title: "Music Videos", term: "music videos", downloads: [.videos, .music]))
                    }
                    TrendingChip(icon: "film", text: "Movies & Shows") {
                        applyScope(SearchScope(title: "Movies & Shows", term: "movies", downloads: [.videos]))
                    }
                    TrendingChip(icon: "book.fill", text: "Audiobooks") {
                        applyScope(SearchScope(title: "Audiobooks", term: "audiobooks", downloads: [.audiobook]))
                    }
                    TrendingChip(icon: "person.fill", text: "Creators") {
                        applyScope(SearchScope(title: "Creators", term: "creators", downloads: []))
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 180 + extraFilterBarPadding) // Padding for search bar
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Actions
    
    /// Placeholder reflects the active scope so the filter is obvious even
    /// though the category text isn't inside the field.
    private var searchPlaceholder: String {
        if let scope = scope {
            return "Search within \(scope.title)..."
        }
        return "Search YouTube..."
    }
    
    /// Combine the user's typed term with the active scope so YouTube results
    /// stay within the chosen category.
    private func effectiveQuery(_ userTerm: String) -> String {
        let filterTerms = selectedFilters.values.compactMap { $0.queryTerm }
        return ([userTerm, scope?.term ?? ""] + filterTerms)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    private func performSearch() {
        let userTerm = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = effectiveQuery(userTerm)
        guard !query.isEmpty else { return }
        
        HapticFeedback.trigger(.medium)
        
        Task {
            await searchService.search(
                query: query,
                filter: searchFilter,
                sortOrder: sortOrder,
                maxResults: 25
            )
        }
    }
    
    /// Enter a category scope and immediately browse it (with no typed term).
    private func applyScope(_ newScope: SearchScope) {
        withAnimation(.smooth) {
            scope = newScope
            selectedFilters = [:]
        }
        searchText = ""
        performSearch()
    }
    
    /// Remove the category scope, keeping any typed term.
    private func clearScope() {
        HapticFeedback.trigger(.light)
        withAnimation(.smooth) {
            scope = nil
            selectedFilters = [:]
        }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchService.clearResults()
        } else {
            performSearch()
        }
    }

    /// Select (or clear, when `option` is nil) a secondary filter. Re-runs the
    /// search only when the query text changes; length-only filters apply
    /// client-side via `visibleResults`.
    private func toggleFilter(_ option: SearchFilterOption?, in group: SearchFilterGroup) {
        HapticFeedback.trigger(.light)
        let previous = selectedFilters[group.id]
        withAnimation(.smooth) { selectedFilters[group.id] = option }
        if previous?.queryTerm != nil || option?.queryTerm != nil {
            performSearch()
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.trigger(.light)
            action()
        }) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue.opacity(0.4) : Color.white.opacity(0.1))
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1)
                        )
                )
        }
        .pressAnimation()
    }
}

// MARK: - Trending Chip

private struct TrendingChip: View {
    let icon: String
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.trigger(.light)
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 24)
                
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .pressAnimation()
    }
}

// MARK: - Search Result Card

private struct SearchResultCard: View {
    let result: YouTubeSearchResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.trigger(.medium)
            onTap()
        }) {
            HStack(spacing: 16) {
                // Thumbnail
                AsyncImage(url: result.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            ProgressView()
                                .tint(.white)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        ZStack {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red.opacity(0.3), Color.orange.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Image(systemName: "photo.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 140, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    // Duration badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            if result.isLive {
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.red)
                                    )
                            } else if result.duration > 0 {
                                Text(result.formattedDuration)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.75))
                                    )
                            }
                        }
                    }
                    .padding(6)
                )
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(result.creator)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    if result.viewCount > 0 {
                        Text(result.formattedViewCount)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
            )
        }
        .pressAnimation()
    }
}

// MARK: - Result Detail Sheet

private struct ResultDetailSheet: View {
    let result: YouTubeSearchResult
    /// Download buttons to show (the user searched within a category). Empty
    /// shows all download options; otherwise only the listed destinations.
    var downloadFilter: [LibraryDestination] = []
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [.blue, .purple, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Scrollable content
            ScrollView {
                VStack(spacing: 20) {
                    // Thumbnail
                    if let url = result.thumbnailURL {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .overlay(ProgressView().tint(.white))
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Title
                    Text(result.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Creator
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                        Text(result.creator)
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Stats
                    HStack(spacing: 20) {
                        if result.viewCount > 0 {
                            Label(result.formattedViewCount, systemImage: "eye.fill")
                        }
                        if result.duration > 0 {
                            Label(result.formattedDuration, systemImage: "clock.fill")
                        }
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Description
                    if !result.description.isEmpty {
                        Text(result.description)
                            .foregroundColor(.white.opacity(0.9))
                            .font(.body)
                            .lineLimit(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Buttons
                    VStack(spacing: 12) {
                        if shouldShow(.videos) {
                            downloadButton("Download Video", icon: "video.fill", destination: .videos)
                        }
                        if shouldShow(.music) {
                            downloadButton("Download Audio", icon: "music.note", destination: .music)
                        }
                        if shouldShow(.audiobook) {
                            downloadButton("Download Audiobook", icon: "book.fill", destination: .audiobook)
                        }
                        
                        // Copy link button
                        Button {
                            UIPasteboard.general.string = result.videoURL.absoluteString
                        } label: {
                            Label("Copy Link", systemImage: "link")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(20)
                .padding(.top, 20)
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
    
    /// Whether a given download option should be offered given the active
    /// search-category filter.
    private func shouldShow(_ destination: LibraryDestination) -> Bool {
        downloadFilter.isEmpty || downloadFilter.contains(destination)
    }
    
    private func downloadButton(_ title: String, icon: String, destination: LibraryDestination) -> some View {
        Button {
            downloads.enqueue(url: result.videoURL, destination: destination)
            dismiss()
        } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.22))
                .cornerRadius(12)
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        // dateString format: "20240115" (YYYYMMDD)
        guard dateString.count == 8 else { return dateString }
        
        let year = dateString.prefix(4)
        let month = dateString.dropFirst(4).prefix(2)
        let day = dateString.dropFirst(6)
        
        return "\(month)/\(day)/\(year)"
    }
}

private struct StatBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
