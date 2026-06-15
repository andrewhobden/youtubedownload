import Foundation
import PythonKit

/// Search result from YouTube
struct YouTubeSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let creator: String
    let duration: TimeInterval
    let viewCount: Int
    let uploadDate: String
    let thumbnailURL: URL?
    let videoURL: URL
    let description: String
    let isLive: Bool
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedViewCount: String {
        if viewCount >= 1_000_000 {
            return String(format: "%.1fM views", Double(viewCount) / 1_000_000)
        } else if viewCount >= 1_000 {
            return String(format: "%.1fK views", Double(viewCount) / 1_000)
        } else {
            return "\(viewCount) views"
        }
    }
}

enum SearchFilter {
    case all
    case video
    case playlist
    case channel
    
    var ytdlpFilter: String {
        switch self {
        case .all: return "all"
        case .video: return "video"
        case .playlist: return "playlist"
        case .channel: return "channel"
        }
    }
}

enum SearchSortOrder {
    case relevance
    case uploadDate
    case viewCount
    case rating
    
    var ytdlpSort: String {
        switch self {
        case .relevance: return "relevance"
        case .uploadDate: return "upload_date"
        case .viewCount: return "view_count"
        case .rating: return "rating"
        }
    }
}

/// YouTube search service using yt-dlp
@MainActor
final class YouTubeSearchService: ObservableObject {
    
    @Published var results: [YouTubeSearchResult] = []
    @Published var isSearching = false
    @Published var isLoadingMore = false
    @Published var canLoadMore = false
    @Published var error: String?
    
    private var currentQuery = ""
    private var currentFilter: SearchFilter = .all
    private var currentSortOrder: SearchSortOrder = .relevance
    private var pageSize = 25
    
    func search(
        query: String,
        filter: SearchFilter = .all,
        sortOrder: SearchSortOrder = .relevance,
        maxResults: Int = 25
    ) async {
        guard !query.isEmpty else {
            results = []
            canLoadMore = false
            return
        }
        
        currentQuery = query
        currentFilter = filter
        currentSortOrder = sortOrder
        pageSize = max(1, maxResults)
        isSearching = true
        error = nil
        canLoadMore = false

        // Raise the pause flag so any in-flight download yields the shared
        // Python thread to this search, then resumes once it completes.
        PythonWorkArbiter.shared.beginForeground()
        defer { PythonWorkArbiter.shared.endForeground() }

        do {
            let searchResults = try await performSearch(
                query: query,
                filter: filter,
                sortOrder: sortOrder,
                start: 1,
                count: pageSize
            )
            
            // Only update if this is still the current query
            if currentQuery == query {
                results = searchResults
                // A full page back implies more results may be available.
                canLoadMore = searchResults.count >= pageSize
            }
        } catch {
            self.error = error.localizedDescription
            results = []
            canLoadMore = false
        }
        
        isSearching = false
    }
    
    /// Fetch the next page of results for the current query and append them.
    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isSearching, !currentQuery.isEmpty else {
            return
        }
        
        let query = currentQuery
        isLoadingMore = true
        error = nil
        
        let start = results.count + 1

        PythonWorkArbiter.shared.beginForeground()
        defer { PythonWorkArbiter.shared.endForeground() }

        do {
            let moreResults = try await performSearch(
                query: query,
                filter: currentFilter,
                sortOrder: currentSortOrder,
                start: start,
                count: pageSize
            )
            
            // Ignore if the query changed while we were loading.
            if currentQuery == query {
                // De-duplicate against what we already show — YouTube's
                // ranking can drift slightly between paged requests.
                let existingIDs = Set(results.map(\.id))
                let newResults = moreResults.filter { !existingIDs.contains($0.id) }
                results.append(contentsOf: newResults)
                canLoadMore = moreResults.count >= pageSize
            }
        } catch {
            self.error = error.localizedDescription
            canLoadMore = false
        }
        
        isLoadingMore = false
    }
    
    private func performSearch(
        query: String,
        filter: SearchFilter,
        sortOrder: SearchSortOrder,
        start: Int,
        count: Int
    ) async throws -> [YouTubeSearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let results: [YouTubeSearchResult] = try PythonBridge.shared.run { mod in
                        // Search far enough to cover the requested window, then
                        // restrict extraction to just that slice so paging only
                        // pulls the new page (items `start`...`end`). The Python
                        // `search` wraps everything in try/except and returns an
                        // envelope, so a network error can never crash the app.
                        let res = mod.search(query, start, count)
                        if Bool(res["ok"]) != true {
                            throw YouTubeError(message: String(res["error"]) ?? "Search failed")
                        }

                        var out: [YouTubeSearchResult] = []
                        for item in res["results"] {
                            guard let videoId = String(item["id"]),
                                  let title = String(item["title"]) else { continue }

                            let creator = String(item["creator"]) ?? "Unknown"
                            let duration = Double(item["duration"]) ?? 0
                            let viewCount = Int(item["view_count"]) ?? 0
                            let uploadDate = String(item["upload_date"]) ?? ""
                            let description = String(item["description"]) ?? ""
                            let isLive = Bool(item["is_live"]) ?? false

                            let thumbStr = String(item["thumbnail"]) ?? ""
                            let thumbnailURL = thumbStr.isEmpty
                                ? URL(string: "https://i.ytimg.com/vi/\(videoId)/hq720.jpg")
                                : URL(string: thumbStr)

                            let videoURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!

                            out.append(YouTubeSearchResult(
                                id: videoId,
                                title: title,
                                creator: creator,
                                duration: duration,
                                viewCount: viewCount,
                                uploadDate: uploadDate,
                                thumbnailURL: thumbnailURL,
                                videoURL: videoURL,
                                description: description,
                                isLive: isLive
                            ))
                        }
                        return out
                    }
                    
                    await MainActor.run {
                        continuation.resume(returning: results)
                    }
                } catch {
                    await MainActor.run {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    func clearResults() {
        results = []
        error = nil
        currentQuery = ""
        canLoadMore = false
        isLoadingMore = false
    }
}
