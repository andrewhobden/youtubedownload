import Foundation

/// Coordinates foreground YouTube lookups (search / load-more) against
/// background downloads. Both funnel through the single `PythonBridge` worker
/// thread, so a long-running download must yield when a foreground lookup
/// arrives — otherwise the search waits for the whole download to finish.
///
/// The pause flag **cannot** be pushed through `PythonBridge` (it is busy
/// running the download), so it lives here on the Swift side and is read by the
/// download's yt-dlp progress hook, which runs on the Python thread *inside*
/// the active download. When the flag is raised the hook aborts the transfer;
/// the download coordinator then parks until `waitUntilIdle()` returns and
/// resumes from the partial `.part` file.
///
/// Thread-safe: `isForegroundActive` is read from the Python worker thread,
/// while the other methods are driven from the main actor; all state is guarded
/// by an `NSLock`.
final class PythonWorkArbiter: @unchecked Sendable {

    static let shared = PythonWorkArbiter()

    private let lock = NSLock()
    private var foregroundCount = 0
    private var lastActivity: Date?
    /// Longest a foreground lookup is allowed to hold off downloads. Searches
    /// finish in a few seconds; anything longer is treated as a leaked flag so
    /// a paused download can never get stuck forever.
    private let maxForegroundAge: TimeInterval = 20

    private init() {}

    /// True while a foreground lookup is active *and* recent. A stale flag
    /// (older than `maxForegroundAge`) is ignored so downloads self-resume.
    var isForegroundActive: Bool {
        lock.lock(); defer { lock.unlock() }
        guard foregroundCount > 0, let last = lastActivity else { return false }
        return Date().timeIntervalSince(last) < maxForegroundAge
    }

    /// Mark the start of a foreground lookup (raises the pause flag).
    func beginForeground() {
        lock.lock()
        foregroundCount += 1
        lastActivity = Date()
        lock.unlock()
    }

    /// Mark the end of a foreground lookup.
    func endForeground() {
        lock.lock()
        foregroundCount = max(0, foregroundCount - 1)
        if foregroundCount == 0 { lastActivity = nil }
        lock.unlock()
    }

    /// Force the arbiter back to idle — an escape hatch when the user manually
    /// restarts a stuck download.
    func forceClear() {
        lock.lock()
        foregroundCount = 0
        lastActivity = nil
        lock.unlock()
    }
}
