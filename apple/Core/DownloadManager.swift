import Foundation
import SwiftData

/// App-wide download queue. Holds every job (queued, in-progress, finished or
/// failed) and runs them one at a time. Injected as an environment object so
/// any view can enqueue a download and the Downloads screen can observe status.
@MainActor
final class DownloadManager: ObservableObject {

    @Published private(set) var jobs: [DownloadCoordinator] = []
    /// Transient message surfaced as a toast (e.g. after enqueueing).
    @Published var toast: String?

    private var context: ModelContext?
    private var mediaRoot: MediaRoot?
    private var isProcessing = false
    private var toastTask: Task<Void, Never>?
    private var watchdog: Timer?

    /// Provide the SwiftData context + media root. Call once from the root view.
    func configure(context: ModelContext, mediaRoot: MediaRoot) {
        self.context = context
        self.mediaRoot = mediaRoot
        startWatchdog()
    }

    /// Periodic safety net: re-kick the queue so it never stalls with runnable
    /// work pending (paused downloads self-resume via their own poll).
    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.processQueue() }
        }
    }

    /// Jobs that are still queued or actively downloading.
    var activeCount: Int {
        jobs.filter { job in
            switch job.state {
            case .finished, .failed: return false
            default: return true
            }
        }.count
    }

    var hasFinishedJobs: Bool {
        jobs.contains { if case .finished = $0.state { return true } else { return false } }
    }

    /// Add a download to the queue, surface a toast, and start processing.
    func enqueue(
        url: URL,
        destination: LibraryDestination,
        toastMessage: String = "Added to Downloads"
    ) {
        guard let context, let mediaRoot else { return }
        let coord = DownloadCoordinator(
            url: url, destination: destination,
            context: context, mediaRoot: mediaRoot
        )
        jobs.insert(coord, at: 0)   // newest on top
        showToast(toastMessage)
        processQueue()
    }

    /// Remove a job from the list. (A network call already in flight is not
    /// force-cancelled, but the job stops being displayed.)
    func remove(_ job: DownloadCoordinator) {
        jobs.removeAll { $0.id == job.id }
    }

    /// Drop all finished jobs from the list.
    func clearFinished() {
        jobs.removeAll { if case .finished = $0.state { return true } else { return false } }
    }

    /// Manually restart a paused or failed job. A paused job is nudged out of
    /// its wait immediately; a failed job re-runs its pipeline. Clears any stale
    /// foreground state so the resumed download isn't paused again straight away.
    func restart(_ job: DownloadCoordinator) {
        PythonWorkArbiter.shared.forceClear()
        switch job.state {
        case .paused:
            job.requestResume()
        case .failed:
            Task { await job.start() }
        default:
            break
        }
        processQueue()
    }

    // MARK: - Queue processing

    private func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true
        Task { [weak self] in
            guard let self else { return }
            // Run oldest-queued first (FIFO) even though newest displays on top.
            while let job = self.jobs.last(where: { if case .queued = $0.state { return true } else { return false } }) {
                await job.start()
            }
            self.isProcessing = false
        }
    }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
