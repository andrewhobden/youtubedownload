import Foundation

/// Where downloaded files live.
///
/// - iOS: app's `Documents/MediaRoot/` (visible in Files.app thanks to
///   UIFileSharingEnabled).
/// - macOS Catalyst: a user-picked folder; the security-scoped bookmark
///   is stored in UserDefaults so it persists across launches.
@MainActor
final class MediaRoot: ObservableObject {

    @Published private(set) var rootURL: URL?

    private let bookmarkKey = "MediaRoot.bookmark"

    init() {
        #if targetEnvironment(macCatalyst)
        rootURL = resolveBookmarkedFolder()
        #else
        rootURL = defaultIOSRoot()
        try? rootURL.map {
            try FileManager.default.createDirectory(at: $0,
                withIntermediateDirectories: true)
        }
        #endif
    }

    /// Resolve a relative path against the root, returning nil if the root
    /// hasn't been set yet (Catalyst before user picks a folder).
    func resolve(_ relPath: String) -> URL? {
        guard let root = rootURL else { return nil }
        return root.appendingPathComponent(relPath)
    }

    /// Create (if needed) and return a per-album subfolder under root.
    func subfolder(named name: String) throws -> URL {
        guard let root = rootURL else {
            throw NSError(domain: "MediaRoot", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No download root chosen"])
        }
        let sub = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: sub,
            withIntermediateDirectories: true)
        return sub
    }

    /// Catalyst: replace the bookmarked folder. Called from a NSOpenPanel
    /// / .fileImporter binding in the Settings scene.
    func setBookmarkedFolder(_ url: URL) {
        #if targetEnvironment(macCatalyst)
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        rootURL = url
        #else
        rootURL = url
        #endif
    }

    // MARK: – private

    private func defaultIOSRoot() -> URL? {
        let docs = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return docs?.appendingPathComponent("MediaRoot", isDirectory: true)
    }

    #if targetEnvironment(macCatalyst)
    private func resolveBookmarkedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }
    #endif
}
