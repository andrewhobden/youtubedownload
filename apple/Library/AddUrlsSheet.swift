import SwiftUI
import SwiftData

/// Paste-box + per-URL job queue. Accepts one URL per line.
struct AddUrlsSheet: View {

    let destination: LibraryDestination

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject var mediaRoot: MediaRoot

    @State private var pasted: String = ""
    @State private var jobs: [DownloadCoordinator] = []
    @State private var ambiguousJob: DownloadCoordinator?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if jobs.isEmpty {
                    pasteBox
                } else {
                    queueView
                }
            }
            .navigationTitle(destination == .videos ? "Add Videos" : "Add Music")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if jobs.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Start") { startJobs() }
                            .disabled(parsedURLs.isEmpty)
                    }
                }
            }
            .sheet(item: $ambiguousJob) { coord in
                AmbiguityPicker(coord: coord) { choice in
                    resolveAmbiguous(coord, choice: choice)
                }
            }
        }
    }

    private var pasteBox: some View {
        VStack(alignment: .leading) {
            Text("Paste one or more YouTube URLs (one per line).")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal)
            TextEditor(text: $pasted)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                .padding()
        }
    }

    private var queueView: some View {
        List(jobs) { job in JobRow(job: job) }
    }

    // MARK: – Parsing + dispatch

    private var parsedURLs: [URL] {
        pasted.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && Sanitize.isValidYouTubeURL($0) }
            .compactMap { URL(string: $0) }
    }

    private func startJobs() {
        let coords = parsedURLs.map {
            DownloadCoordinator(
                url: $0, destination: destination,
                context: context, mediaRoot: mediaRoot
            )
        }
        jobs = coords
        Task {
            for coord in coords {
                await coord.start()
                if case .failed(let m) = coord.state, m == "AMBIGUOUS" {
                    ambiguousJob = coord
                    // Wait for the user to resolve before moving on.
                    while ambiguousJob != nil { try? await Task.sleep(for: .milliseconds(200)) }
                }
            }
        }
    }

    // MARK: – Ambiguous URL handling

    fileprivate enum AmbiguityChoice { case justThisSong, wholePlaylist }

    private func resolveAmbiguous(
        _ coord: DownloadCoordinator,
        choice: AmbiguityChoice?
    ) {
        ambiguousJob = nil
        guard let choice else { return }

        let rewritten: URL
        switch choice {
        case .justThisSong:
            // Strip the &list=… parameter so the classifier sees a pure
            // /watch?v=… URL.
            rewritten = stripListParameter(from: coord.url)
        case .wholePlaylist:
            // Convert /watch?v=…&list=ID into /playlist?list=ID so the
            // classifier picks playlist mode.
            if let id = Sanitize.playlistID(in: coord.url.absoluteString),
               let url = URL(string: "https://www.youtube.com/playlist?list=\(id)") {
                rewritten = url
            } else {
                rewritten = coord.url
            }
        }

        let replacement = DownloadCoordinator(
            url: rewritten, destination: .music,
            context: context, mediaRoot: mediaRoot
        )
        if let idx = jobs.firstIndex(where: { $0.id == coord.id }) {
            jobs[idx] = replacement
        }
        Task { await replacement.start() }
    }

    private func stripListParameter(from url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        comps.queryItems = comps.queryItems?.filter { $0.name != "list" && $0.name != "index" }
        return comps.url ?? url
    }
}

private struct JobRow: View {
    @ObservedObject var job: DownloadCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title.isEmpty ? job.url.absoluteString : job.title)
                .lineLimit(1)
            HStack(spacing: 8) {
                if showsSpinner {
                    // Indeterminate spinner — yt-dlp's progress callback
                    // isn't wired through to Swift yet, so a real percentage
                    // would be misleading.
                    ProgressView().controlSize(.small)
                }
                Text(stateText)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var showsSpinner: Bool {
        switch job.state {
        case .probing, .downloading, .postProcessing: return true
        default: return false
        }
    }

    private var stateText: String {
        switch job.state {
        case .queued: return "Queued"
        case .probing: return "Probing…"
        case .downloading: return "Downloading…"
        case .postProcessing(let s): return s.capitalized + "…"
        case .finished: return "Finished"
        case .failed(let m): return "Failed: \(m)"
        }
    }
}

/// Sheet shown when a `/watch?v=…&list=…` URL is ambiguous (does the user
/// want just the song or the whole playlist?).
private struct AmbiguityPicker: View {
    let coord: DownloadCoordinator
    let resolve: (AddUrlsSheet.AmbiguityChoice?) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("This URL contains a playlist. Which did you mean?")
                .font(.headline).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Just this song") { resolve(.justThisSong) }
                    .buttonStyle(.bordered)
                Button("Whole playlist") { resolve(.wholePlaylist) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Cancel", role: .cancel) { resolve(nil) }
        }
        .padding(30)
    }
}
