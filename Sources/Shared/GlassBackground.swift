import SwiftUI
import UIKit

/// A blur view whose intensity can be smoothly varied at runtime (SwiftUI's
/// `.ultraThinMaterial` etc. only ship a handful of fixed styles). Built on the
/// standard "paused UIViewPropertyAnimator" technique: an animator that would
/// transition from no-effect to a full blur is created and immediately parked
/// at `fractionComplete`, which UIKit renders as a partial blur.
struct VariableBlurView: UIViewRepresentable {
    /// 0 = no blur at all, 1 = full system material blur.
    var intensity: Double

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: nil)
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        // Tearing down any previous animator before making a new one avoids
        // leaving a stale animation running when the slider moves quickly.
        Self.retireAnimator(context.coordinator.animator)
        context.coordinator.animator = nil
        uiView.effect = nil

        let clamped = max(0.0, min(intensity, 1.0))
        guard clamped > 0.001 else { return }

        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            uiView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        }
        animator.fractionComplete = CGFloat(clamped)
        context.coordinator.animator = animator
    }

    static func dismantleUIView(_ uiView: UIVisualEffectView, coordinator: Coordinator) {
        // Called when the view is removed from the hierarchy — e.g. when the
        // sidebar is torn down entering immersive fullscreen. Without this,
        // an animator left in .stopped-but-not-.inactive state (see below)
        // gets deallocated while still "active", which is an EXC_BAD_ACCESS.
        retireAnimator(coordinator.animator)
        coordinator.animator = nil
    }

    /// `stopAnimation(true)` alone leaves the animator in `.stopped` state,
    /// which UIKit still considers "active" (not `.inactive`) until
    /// `finishAnimation(at:)` is called. An animator deallocated while active
    /// is a well-known UIKit crash, so every retirement path must finish it.
    private static func retireAnimator(_ animator: UIViewPropertyAnimator?) {
        guard let animator, animator.state != .inactive else { return }
        animator.stopAnimation(true)
        if animator.state != .inactive {
            animator.finishAnimation(at: .current)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var animator: UIViewPropertyAnimator?
    }
}

/// A button style that gives immediate, tactile feedback on press — a quick
/// scale-and-fade — so icon-only controls (back/forward/reload, sidebar nav)
/// don't feel inert. Without this, tapping a flat SF Symbol button gives no
/// visual confirmation the tap registered until whatever it triggers finishes.
struct PressFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Reusable "Liquid Glass" style surface: blur + translucent material + soft border + shadow.
/// Supports either a uniform `cornerRadius` on all four corners, or (via
/// `cornerRadii`) different radii per corner — used by the sidebar/content
/// split so the edge touching the physical screen border can stay square
/// while the edge facing the other panel rounds off, and the two panels'
/// facing corners can be driven by the same value so they visually match.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var cornerRadii: RectangleCornerRadii? = nil
    var tintOpacity: Double = 0.55
    /// When provided (0...40, matching `AppSettings.sidebarBlur`'s slider range),
    /// drives a `VariableBlurView` instead of the fixed `.ultraThinMaterial`, so
    /// the "Blur Amount" setting actually changes what's on screen.
    var blurAmount: Double? = nil
    @EnvironmentObject private var settings: AppSettings
    @ViewBuilder var content: () -> Content

    private var shape: UnevenRoundedRectangle {
        if let cornerRadii {
            return UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
        }
        return UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
            topLeading: cornerRadius, bottomLeading: cornerRadius,
            bottomTrailing: cornerRadius, topTrailing: cornerRadius
        ), style: .continuous)
    }

    var body: some View {
        content()
            .background(
                ZStack {
                    if let blurAmount {
                        shape
                            .fill(Color.black.opacity(0.001)) // keeps hit-testing/clip stable while empty
                        VariableBlurView(intensity: blurAmount / 40.0)
                            .clipShape(shape)
                            .opacity(tintOpacity + 0.3)
                    } else {
                        shape
                            .fill(.ultraThinMaterial)
                            .opacity(tintOpacity)
                    }
                    shape
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                shape
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 10)
    }
}

/// In-memory cache for the decoded custom background image. Without this,
/// every SwiftUI re-render of `AppBackgroundView` (which can happen dozens of
/// times a minute as unrelated settings change) re-decodes the full image
/// from disk, which is what made removing/replacing a large photo crash under
/// memory pressure. `BackgroundImageStore.load` is the only place that should
/// touch the file on disk.
enum BackgroundImageStore {
    private static let cache = NSCache<NSString, UIImage>()

    static func load(path: String) -> UIImage? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Call whenever the on-disk file changes or is removed so stale pixels
    /// never linger in memory (and so a freshly-picked replacement is re-read).
    static func invalidate(path: String) {
        cache.removeObject(forKey: path as NSString)
    }

    static func invalidateAll() {
        cache.removeAllObjects()
    }
}

/// The app-wide background: solid / gradient / image / default, driven by AppSettings.
struct AppBackgroundView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            switch settings.backgroundStyle {
            case .defaultStyle:
                defaultBackground
            case .solid:
                Color(hex: settings.backgroundSolidHex).ignoresSafeArea()
            case .gradient:
                gradientBackground
            case .image:
                if let path = settings.customBackgroundImagePath,
                   let uiImage = BackgroundImageStore.load(path: path) {
                    GeometryReader { geo in
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: settings.backgroundImageFillMode.contentMode)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: settings.backgroundImageBlur)
                            .opacity(settings.backgroundImageOpacity)
                    }
                    .ignoresSafeArea()
                    .background(Color(hex: "#08080D").ignoresSafeArea())
                } else {
                    defaultBackground
                }
            }
        }
    }

    private var defaultBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: "#0B0B14"),
                settings.accentColor.opacity(0.28),
                Color(hex: "#050509")
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var gradientBackground: some View {
        let angle = Angle(degrees: settings.gradientAngleDegrees)
        let start = UnitPoint(x: 0.5 - CGFloat(cos(angle.radians)) * 0.6, y: 0.5 - CGFloat(sin(angle.radians)) * 0.6)
        let end = UnitPoint(x: 0.5 + CGFloat(cos(angle.radians)) * 0.6, y: 0.5 + CGFloat(sin(angle.radians)) * 0.6)
        return LinearGradient(
            colors: [
                Color(hex: settings.gradientStartHex).opacity(settings.gradientIntensity),
                Color(hex: settings.gradientEndHex).opacity(settings.gradientIntensity)
            ],
            startPoint: start, endPoint: end
        )
        .background(Color(hex: "#08080D"))
        .ignoresSafeArea()
    }
}
