import SwiftUI

// MARK: - Local File Image

/// Loads an image from a local file URL reliably, off the main thread.
///
/// `AsyncImage` is designed for network requests and is unreliable for local
/// `file://` URLs (it frequently never leaves its placeholder state), so all
/// downloaded covers/thumbnails must use this instead. Mirrors the
/// `PlatformImage(contentsOfFile:)` approach already used in `AlbumDetailView`.
struct LocalImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: PlatformImage?

    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                #else
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
                #endif
            } else {
                placeholder()
            }
        }
        .task(id: url?.path) { await load() }
    }

    private func load() async {
        guard let path = url?.path else {
            await MainActor.run { image = nil }
            return
        }
        // Read the file off the main thread (Data is Sendable), then build and
        // assign the image on the main actor so SwiftUI observes the change and
        // re-renders immediately. Assigning @State off-main leaves the view
        // showing the placeholder until some unrelated invalidation occurs.
        let data = await Task.detached(priority: .userInitiated) {
            FileManager.default.contents(atPath: path)
        }.value
        guard !Task.isCancelled, let data else { return }
        await MainActor.run { image = PlatformImage(data: data) }
    }
}

// MARK: - Glassmorphic Card

/// A glassmorphic card with frosted glass effect and depth
struct GlassCard<Content: View>: View {
    let content: Content
    var material: Material = .regularMaterial
    var cornerRadius: CGFloat = 16
    var shadowRadius: CGFloat = 10
    
    init(
        material: Material = .regularMaterial,
        cornerRadius: CGFloat = 16,
        shadowRadius: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.material = material
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
    }
    
    var body: some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: shadowRadius, y: shadowRadius / 2)
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    var style: GlassButtonStyle = .primary
    
    enum GlassButtonStyle {
        case primary
        case secondary
        case destructive
        
        var material: Material {
            switch self {
            case .primary: return .regular
            case .secondary: return .thin
            case .destructive: return .thin
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary: return .primary
            case .secondary: return .secondary
            case .destructive: return .red
            }
        }
    }
    
    init(
        _ title: String,
        systemImage: String? = nil,
        style: GlassButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let image = systemImage {
                    Image(systemName: image)
                }
                Text(title)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(style.foregroundColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(style.material, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Sheet

struct GlassSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let content: Content
    
    init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            isPresented = false
                        }
                    }
                
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        // Drag indicator
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 36, height: 5)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        
                        content
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.3), radius: 30, y: -10)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isPresented)
    }
}

// MARK: - Floating Action Button

struct FloatingActionButton: View {
    let systemImage: String
    let action: () -> Void
    var size: CGFloat = 56
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.blue.gradient)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Navigation Bar

struct GlassNavigationBar<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading
    let trailing: Trailing
    
    init(
        title: String,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }
    
    var body: some View {
        HStack {
            leading
                .frame(width: 60, alignment: .leading)
            
            Spacer()
            
            Text(title)
                .font(.headline)
                .lineLimit(1)
            
            Spacer()
            
            trailing
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Animated Gradient Background

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    let colors: [Color]
    
    init(colors: [Color] = [.blue, .purple, .pink, .orange]) {
        self.colors = colors
    }
    
    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - View Extensions for Glass Effects

extension View {
    /// Apply a glassmorphic card style to any view
    func glassCard(
        material: Material = .regularMaterial,
        cornerRadius: CGFloat = 16,
        shadowRadius: CGFloat = 10
    ) -> some View {
        self
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: shadowRadius, y: shadowRadius / 2)
    }
    
    /// Unified media grid-card style: material background with the whole card
    /// clipped to a continuous rounded rectangle (so artwork at the top shares
    /// the card's corners), plus a subtle border and shadow. Unlike `glassCard`
    /// this clips its content, giving a single cohesive card rather than a
    /// separately-rounded thumbnail sitting on a panel.
    func mediaCardStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
    }
    
    /// Apply a subtle glow effect
    func glowEffect(color: Color = .blue, radius: CGFloat = 10) -> some View {
        self
            .shadow(color: color.opacity(0.5), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
    
    /// Apply press animation.
    ///
    /// NOTE: This is intentionally a no-op passthrough. The press-scale effect
    /// is now provided by `PressableButtonStyle` applied to the enclosing
    /// `Button`/`NavigationLink`. The previous implementation attached a
    /// `DragGesture(minimumDistance: 0)` as a `.simultaneousGesture`, which —
    /// on a button/link label inside a `ScrollView` — stole the tap (and
    /// conflicted with `.contextMenu` long-presses), so cards never opened.
    func pressAnimation() -> some View {
        self
    }
}

// MARK: - Pressable Button Style

/// A plain-looking button style that adds a subtle press-scale without
/// interfering with taps, scrolling, or context-menu long-presses. Works for
/// both `Button` and `NavigationLink` (which honour the environment's button
/// style on iOS). Use in place of `.buttonStyle(.plain)` on tappable cards.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7),
                       value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Convenience: `.buttonStyle(.pressableCard)`.
    static var pressableCard: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Blur Intensity

struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    var intensity: CGFloat
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
        uiView.alpha = intensity
    }
}

// MARK: - Haptic Feedback Helper

struct HapticFeedback {
    enum FeedbackType {
        case light
        case medium
        case heavy
        case success
        case warning
        case error
        case selection
    }
    
    static func trigger(_ type: FeedbackType) {
        switch type {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - Smooth Animations

extension Animation {
    static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.9)
    static let smoothFast = Animation.spring(response: 0.25, dampingFraction: 0.95)
    static let smoothSlow = Animation.spring(response: 0.5, dampingFraction: 0.85)
}
