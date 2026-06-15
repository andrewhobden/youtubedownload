import SwiftUI

/// Standalone job-queue view used to surface in-flight downloads outside
/// the AddUrlsSheet (e.g. a future "Downloads" tab). The AddUrlsSheet
/// embeds its own job list inline for v1; this view exists so that the
/// queue can be reopened later without losing state.
struct JobQueueView: View {
    @ObservedObject var queue: JobQueueStore

    var body: some View {
        List(queue.jobs) { job in
            HStack {
                VStack(alignment: .leading) {
                    Text(job.title.isEmpty ? job.url.absoluteString : job.title)
                        .lineLimit(1)
                    Text(stateText(job.state))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if case .downloading(let p) = job.state {
                    ProgressView(value: p).frame(width: 80)
                }
            }
        }
        .navigationTitle("Downloads")
    }

    private func stateText(_ s: DownloadJobState) -> String {
        switch s {
        case .queued: return "Queued"
        case .probing: return "Probing"
        case .downloading(let p): return String(format: "%.0f%%", p * 100)
        case .paused(let p):
            return p > 0 ? String(format: "Paused %.0f%%", p * 100) : "Paused"
        case .postProcessing(let stage): return stage
        case .finished: return "Done"
        case .failed(let m): return m
        }
    }
}

/// Shared store for the global job list. Add jobs via `enqueue`; observe
/// `jobs` in any view.
@MainActor
final class JobQueueStore: ObservableObject {
    @Published private(set) var jobs: [DownloadCoordinator] = []

    func enqueue(_ coord: DownloadCoordinator) { jobs.append(coord) }
    func clearFinished() {
        jobs.removeAll {
            if case .finished = $0.state { return true } else { return false }
        }
    }
}
