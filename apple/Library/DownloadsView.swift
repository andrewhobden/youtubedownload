import SwiftUI

/// Lists every queued / in-progress / finished download and its live status.
struct DownloadsView: View {
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject private var auth: YouTubeAuth
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogin = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()

                if downloads.jobs.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if auth.isSignedIn {
                            Label("Signed in to YouTube", systemImage: "checkmark.seal.fill")
                            Button("Re-sign in") { showingLogin = true }
                            Button("Sign out", role: .destructive) { auth.signOut() }
                        } else {
                            Button {
                                showingLogin = true
                            } label: {
                                Label("Sign in to YouTube", systemImage: "person.crop.circle")
                            }
                        }
                    } label: {
                        Image(systemName: auth.isSignedIn
                              ? "person.crop.circle.badge.checkmark"
                              : "person.crop.circle")
                            .foregroundStyle(auth.isSignedIn ? .green : .white)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear Finished") { downloads.clearFinished() }
                        .disabled(!downloads.hasFinishedJobs)
                }
            }
            .sheet(isPresented: $showingLogin) {
                YouTubeLoginView()
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(downloads.jobs) { job in
                    DownloadJobRow(job: job, onRemove: { downloads.remove(job) }, onRestart: { downloads.restart(job) })
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.6))
            Text("No Downloads")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Downloads you start from search will appear here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

private struct DownloadJobRow: View {
    @ObservedObject var job: DownloadCoordinator
    let onRemove: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: destinationIcon)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(job.title.isEmpty ? job.url.absoluteString : job.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if showsSpinner {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else if isPaused {
                        Image(systemName: "pause.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(stateText)
                        .font(.caption)
                        .foregroundStyle(stateColor)
                }

                if let fraction = progressFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(isPaused ? .orange : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if isRestartable {
                Button(action: onRestart) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restart download")
            }

            if isRemovable {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .mediaCardStyle(cornerRadius: 14)
    }

    private var destinationIcon: String {
        switch job.destination {
        case .videos: return "video.fill"
        case .music: return "music.note"
        case .audiobook: return "book.fill"
        }
    }

    private var showsSpinner: Bool {
        switch job.state {
        case .probing, .postProcessing: return true
        default: return false
        }
    }

    /// Fraction (0…1) to drive the row's progress bar, or nil when there's no
    /// meaningful determinate progress (queued / probing / post-processing /
    /// finished / failed).
    private var progressFraction: Double? {
        switch job.state {
        case .downloading(let p), .paused(let p): return p
        default: return nil
        }
    }

    private var isPaused: Bool {
        if case .paused = job.state { return true }
        return false
    }

    private var isRemovable: Bool {
        switch job.state {
        case .finished, .failed: return true
        default: return false
        }
    }

    private var isRestartable: Bool {
        switch job.state {
        case .paused, .failed: return true
        default: return false
        }
    }

    private var stateText: String {
        switch job.state {
        case .queued: return "Queued"
        case .probing: return "Probing…"
        case .downloading(let p):
            return p > 0 ? "Downloading \(Int(p * 100))%" : "Downloading…"
        case .paused(let p):
            return p > 0 ? "Paused for search · \(Int(p * 100))%" : "Paused for search"
        case .postProcessing(let stage): return stage.capitalized + "…"
        case .finished: return "Finished"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private var stateColor: Color {
        switch job.state {
        case .finished: return .green
        case .failed: return .red
        case .paused: return .orange
        default: return .white.opacity(0.7)
        }
    }
}

// MARK: - Toast

/// A small auto-dismissing pill, used to confirm transient actions.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

extension View {
    /// Overlay a transient toast driven by `DownloadManager.toast`. Apply this
    /// in a view that observes the manager so the toast appears/disappears.
    func downloadToast(_ downloads: DownloadManager) -> some View {
        overlay(alignment: .bottom) {
            if let message = downloads.toast {
                ToastView(message: message)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: downloads.toast)
    }
}
