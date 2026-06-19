import SwiftUI
import WebKit

/// In-app YouTube sign-in. Presents Google's login in a `WKWebView`; once the
/// user is authenticated the session cookies are exported (via `YouTubeAuth`)
/// to a Netscape cookie file that yt-dlp uses to bypass YouTube's bot check.
struct YouTubeLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: YouTubeAuth

    /// Set true once a YouTube auth cookie (e.g. `LOGIN_INFO`) is detected.
    @State private var detectedSignIn = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    banner
                    LoginWebView(detectedSignIn: $detectedSignIn)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(12)
                }
            }
            .navigationTitle("Sign in to YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isSaving ? "Saving…" : "Done") { saveAndClose() }
                        .disabled(isSaving)
                        .fontWeight(detectedSignIn ? .bold : .regular)
                }
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: detectedSignIn ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                .foregroundStyle(detectedSignIn ? .green : .white.opacity(0.8))
            Text(detectedSignIn
                 ? "Signed in — tap Done to save your session."
                 : "Log in with your Google account, then tap Done.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func saveAndClose() {
        isSaving = true
        LoginCookieExporter.exportCookies { cookies in
            auth.save(cookies: cookies)
            isSaving = false
            dismiss()
        }
    }
}

/// Shared helper that exports the signed-in YouTube cookies from WebKit's
/// default cookie store (the same store the login web view writes to).
enum LoginCookieExporter {
    static func exportCookies(_ completion: @escaping ([HTTPCookie]) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            DispatchQueue.main.async { completion(cookies) }
        }
    }
}

/// `WKWebView` wrapper that loads Google's YouTube sign-in flow and reports
/// when an authenticated session cookie appears.
private struct LoginWebView: UIViewRepresentable {
    @Binding var detectedSignIn: Bool

    private static let loginURL = URL(string:
        "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F"
    )!

    func makeCoordinator() -> Delegate { Delegate(detectedSignIn: $detectedSignIn) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // A desktop-class UA keeps Google from blocking the embedded browser
        // and matches the cookies yt-dlp's `web` client expects.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.load(URLRequest(url: Self.loginURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Delegate: NSObject, WKNavigationDelegate {
        private let detectedSignIn: Binding<Bool>

        init(detectedSignIn: Binding<Bool>) {
            self.detectedSignIn = detectedSignIn
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let signedIn = cookies.contains {
                    let domain = $0.domain.lowercased()
                    return domain.contains("youtube.com")
                        && ($0.name == "LOGIN_INFO" || $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID")
                }
                if signedIn {
                    DispatchQueue.main.async { self.detectedSignIn.wrappedValue = true }
                }
            }
        }
    }
}
