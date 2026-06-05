import Foundation
import PythonKit

/// Owns the embedded Python runtime and the `youtube_core` module handle.
///
/// **Threading.** All Python work must run on the same OS thread.
/// `DispatchQueue.serial` is *not* sufficient — `queue.sync` runs on the
/// caller's thread, so two libdispatch workers calling Python serially
/// still alternate threads, which corrupts Python's GIL state and crashes
/// inside `_PyObject_Malloc`. This class instead pins all Python calls to
/// a single dedicated `Thread` and dispatches work through it via an
/// NSCondition-guarded queue.
final class PythonBridge {

    enum BridgeError: Error {
        case stdlibMissing
        case ytDlpMissing
        case bridgeNotInitialised
    }

    static let shared = PythonBridge()

    private let cond = NSCondition()
    private var pending: (() -> Void)?
    private var initialised = false
    private var youtubeCore: PythonObject?

    private init() {
        let t = Thread { [weak self] in
            self?.workerLoop()
        }
        t.name = "PythonBridge"
        t.qualityOfService = .userInitiated
        t.start()
    }

    /// Initialise the runtime. Idempotent. Throws if the bundled stdlib or
    /// yt_dlp directories cannot be located.
    ///
    /// Expected bundle layout (set up by `project.yml` resources):
    ///   <bundle>/python-stdlib/lib/python3.13/    ← stdlib
    ///   <bundle>/site-packages/yt_dlp/            ← bundled yt-dlp
    ///   <bundle>/youtube_core.py                  ← our helper module
    func bootstrap() throws {
        try perform { [self] in
            guard !initialised else { return }
            try doBootstrap()
        }
    }

    /// Run a closure on the Python thread with the live `youtube_core`
    /// module (or throw if bootstrap was never called).
    func run<T>(_ block: @escaping (PythonObject) throws -> T) throws -> T {
        try perform { [self] in
            guard let mod = youtubeCore else {
                throw BridgeError.bridgeNotInitialised
            }
            return try block(mod)
        }
    }

    // MARK: – Internals

    /// Worker run-loop. Picks up tasks and runs them on this thread only.
    private func workerLoop() {
        while true {
            cond.lock()
            while pending == nil { cond.wait() }
            let work = pending!
            pending = nil
            cond.unlock()

            work()
        }
    }

    /// Synchronously execute `block` on the Python thread.
    private func perform<T>(_ block: @escaping () throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        let slot = ResultSlot<T>()

        cond.lock()
        pending = {
            do {
                slot.value = .success(try block())
            } catch {
                slot.value = .failure(error)
            }
            done.signal()
        }
        cond.signal()
        cond.unlock()

        done.wait()
        return try slot.value!.get()
    }

    /// The actual Python bootstrap. Always called from the Python thread
    /// via `perform`.
    private func doBootstrap() throws {
            let bundle = Bundle.main
            let stdlib = bundle.url(forResource: "python-stdlib", withExtension: nil)
                ?? bundle.bundleURL.appendingPathComponent("Resources/python-stdlib")
            guard FileManager.default.fileExists(atPath: stdlib.path) else {
                throw BridgeError.stdlibMissing
            }

            let sitePackages = bundle.url(forResource: "site-packages", withExtension: nil)
                ?? bundle.bundleURL.appendingPathComponent("Resources/site-packages")
            guard FileManager.default.fileExists(atPath: sitePackages.path) else {
                throw BridgeError.ytDlpMissing
            }

            let scriptsURL = bundle.url(forResource: "youtube_core", withExtension: "py")
                ?? bundle.bundleURL.appendingPathComponent("Resources/youtube_core.py")
            guard FileManager.default.fileExists(atPath: scriptsURL.path) else {
                throw BridgeError.bridgeNotInitialised
            }
            let scripts = scriptsURL.deletingLastPathComponent()

            setenv("PYTHONHOME", stdlib.path, 1)
            setenv("PYTHONPATH",
                   "\(stdlib.path)/lib/python3.13:\(sitePackages.path):\(scripts.path)",
                   1)
            setenv("PYTHON_COLORS", "0", 1)

            let sys = Python.import("sys")
            sys.path.insert(0, scripts.path)
            sys.path.insert(0, sitePackages.path)

            youtubeCore = Python.import("youtube_core")
            initialised = true

            let ytdlp = Python.import("yt_dlp")
            print("[PythonBridge] yt-dlp version: \(String(ytdlp.version.__version__) ?? "unknown") (thread: \(Thread.current.name ?? "?"))")
    }
}

private final class ResultSlot<T> {
    var value: Result<T, Error>?
}
