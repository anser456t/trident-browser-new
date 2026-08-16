import Foundation
import SwiftUI
import Combine

enum ColorSchemePreference: String, CaseIterable, Codable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Codable, Identifiable {
    case defaultStyle, solid, gradient, image
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .defaultStyle: return "Default"
        case .solid: return "Solid Color"
        case .gradient: return "Gradient"
        case .image: return "Custom Image"
        }
    }
}

enum StartPageStyle: String, CaseIterable, Codable, Identifiable {
    case minimal, favorites, dashboard
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum ArchiveInterval: String, CaseIterable, Codable, Identifiable {
    case never, oneDay, sevenDays, thirtyDays
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: return "Never"
        case .oneDay: return "After 1 Day"
        case .sevenDays: return "After 7 Days"
        case .thirtyDays: return "After 30 Days"
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .never: return nil
        case .oneDay: return 60 * 60 * 24
        case .sevenDays: return 60 * 60 * 24 * 7
        case .thirtyDays: return 60 * 60 * 24 * 30
        }
    }
}

enum WebsiteMode: String, CaseIterable, Codable, Identifiable {
    case desktop, mobile
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BackgroundFillMode: String, CaseIterable, Codable, Identifiable {
    case fill, fit
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        }
    }
    var contentMode: ContentMode {
        switch self {
        case .fill: return .fill
        case .fit: return .fit
        }
    }
}

/// Central, persisted app settings store. Backed by `@AppStorage`-style UserDefaults keys
/// so every setting survives relaunch without extra plumbing.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // General
    @Published var defaultSearchEngine: SearchEngine { didSet { save(defaultSearchEngine.rawValue, "defaultSearchEngine") } }
    @Published var customSearchEngineTemplate: String { didSet { save(customSearchEngineTemplate, "customSearchEngineTemplate") } }
    @Published var defaultWebsiteMode: WebsiteMode { didSet { save(defaultWebsiteMode.rawValue, "defaultWebsiteMode") } }
    @Published var startPageStyle: StartPageStyle { didSet { save(startPageStyle.rawValue, "startPageStyle") } }
    @Published var openNewTabsAdjacent: Bool { didSet { save(openNewTabsAdjacent, "openNewTabsAdjacent") } }
    /// Whether the Start page's search field is pinned above the widgets
    /// (top) or sits in its normal position below them.
    /// Corner radius applied to Quick Access / widget cards on the Start page.
    @Published var homeCardCornerRadius: Double { didSet { save(homeCardCornerRadius, "homeCardCornerRadius") } }
    /// Opacity of the frosted-glass fill behind Start page cards (0 = fully
    /// see-through, 1 = fully opaque).
    @Published var homeCardTransparency: Double { didSet { save(homeCardTransparency, "homeCardTransparency") } }
    /// Background blur radius (points) behind Start page cards.
    @Published var homeCardBlur: Double { didSet { save(homeCardBlur, "homeCardBlur") } }
    /// Distinct from the app-wide wallpaper in Appearance settings — this is
    /// a tint layer drawn only behind the Start page's own content, so "Home"
    /// personalization can change something beyond just the widget cards.
    @Published var homeBackgroundColorHex: String { didSet { save(homeBackgroundColorHex, "homeBackgroundColorHex") } }
    @Published var homeBackgroundOpacity: Double { didSet { save(homeBackgroundOpacity, "homeBackgroundOpacity") } }
    @Published var homeBackgroundBlur: Double { didSet { save(homeBackgroundBlur, "homeBackgroundBlur") } }

    // Appearance
    @Published var colorSchemePreference: ColorSchemePreference { didSet { save(colorSchemePreference.rawValue, "colorSchemePreference") } }
    @Published var accentColorHex: String { didSet { save(accentColorHex, "accentColorHex") } }
    /// Tracks which `ThemePreset` (if any) was last tapped, purely so the
    /// Appearance screen can show a selection ring on it. Manually tweaking
    /// any individual slider afterward doesn't clear this — it's a "what did
    /// I start from" marker, not a locked mode.
    @Published var lastAppliedThemePresetID: String? { didSet { save(lastAppliedThemePresetID, "lastAppliedThemePresetID") } }
    @Published var backgroundStyle: BackgroundStyle { didSet { save(backgroundStyle.rawValue, "backgroundStyle") } }
    @Published var backgroundSolidHex: String { didSet { save(backgroundSolidHex, "backgroundSolidHex") } }
    @Published var gradientStartHex: String { didSet { save(gradientStartHex, "gradientStartHex") } }
    @Published var gradientEndHex: String { didSet { save(gradientEndHex, "gradientEndHex") } }
    @Published var gradientAngleDegrees: Double { didSet { save(gradientAngleDegrees, "gradientAngleDegrees") } }
    @Published var gradientIntensity: Double { didSet { save(gradientIntensity, "gradientIntensity") } }
    @Published var customBackgroundImagePath: String? { didSet { save(customBackgroundImagePath, "customBackgroundImagePath") } }
    @Published var backgroundImageBlur: Double { didSet { save(backgroundImageBlur, "backgroundImageBlur") } }
    /// Applies to the background as a whole, regardless of which style above
    /// is active — a single "soften everything behind the window" control,
    /// separate from `backgroundImageBlur` which only affects the Image style
    /// specifically (and is layered with this one, not replaced by it).
    @Published var backgroundBlurAmount: Double { didSet { save(backgroundBlurAmount, "backgroundBlurAmount") } }
    @Published var backgroundImageOpacity: Double { didSet { save(backgroundImageOpacity, "backgroundImageOpacity") } }
    @Published var backgroundImageFillMode: BackgroundFillMode { didSet { save(backgroundImageFillMode.rawValue, "backgroundImageFillMode") } }

    // Sidebar customization
    @Published var sidebarWidth: Double { didSet { save(sidebarWidth, "sidebarWidth") } }
    @Published var sidebarTransparency: Double { didSet { save(sidebarTransparency, "sidebarTransparency") } }
    @Published var sidebarBlur: Double { didSet { save(sidebarBlur, "sidebarBlur") } }
    @Published var sidebarCornerRadius: Double { didSet { save(sidebarCornerRadius, "sidebarCornerRadius") } }
    @Published var sidebarCompactMode: Bool { didSet { save(sidebarCompactMode, "sidebarCompactMode") } }
    @Published var sidebarShowFavicons: Bool { didSet { save(sidebarShowFavicons, "sidebarShowFavicons") } }
    @Published var sidebarAlwaysShow: Bool { didSet { save(sidebarAlwaysShow, "sidebarAlwaysShow") } }
    @Published var sidebarAutoHide: Bool { didSet { save(sidebarAutoHide, "sidebarAutoHide") } }
    /// When entering true full-screen (immersive) mode: if true, the status
    /// bar (clock/battery/wifi) is hidden outright; if false, a solid bar is
    /// drawn behind it so the web page can't show through underneath it.
    @Published var hideStatusBarInFullScreen: Bool { didSet { save(hideStatusBarInFullScreen, "hideStatusBarInFullScreen") } }
    /// Vertical margin between the sidebar panel and the top/bottom of the window.
    /// Smaller values make the sidebar taller; larger values shrink it. This is how
    /// users adjust sidebar "height" without breaking the full-bleed layout.
    /// Margin between the *entire* browser window (sidebar + web content,
    /// merged into a single floating card — see `ContentView.windowContent`)
    /// and the physical screen edges. Replaces the old separate
    /// "sidebar height margin" and "gap between sidebar & page" — now that
    /// sidebar and content share one card there's nothing for a gap between
    /// them to mean, and the margin needs to apply on every side, not just
    /// top/bottom.
    @Published var windowMargin: Double { didSet { save(windowMargin, "windowMargin") } }

    // Tabs
    @Published var archiveInterval: ArchiveInterval { didSet { save(archiveInterval.rawValue, "archiveInterval") } }
    /// The Space and tab the user was last looking at, so launch can restore
    /// exactly where they left off instead of always resetting to the first
    /// default Space (previously nothing persisted this, so any tabs living
    /// in a non-default Space became invisible on relaunch — indistinguishable
    /// from having been closed).
    @Published var lastActiveSpaceIDString: String? { didSet { save(lastActiveSpaceIDString, "lastActiveSpaceID") } }
    @Published var lastActiveTabIDString: String? { didSet { save(lastActiveTabIDString, "lastActiveTabID") } }

    // Privacy
    @Published var trackingProtectionEnabled: Bool { didSet { save(trackingProtectionEnabled, "trackingProtectionEnabled") } }

    // Advanced
    @Published var javaScriptEnabled: Bool { didSet { save(javaScriptEnabled, "javaScriptEnabled") } }

    // Downloads
    @Published var downloadHistoryRetained: Bool { didSet { save(downloadHistoryRetained, "downloadHistoryRetained") } }

    // Home screen personalization
    @Published var userDisplayName: String { didSet { save(userDisplayName, "userDisplayName") } }

    private init() {
        let d = UserDefaults.standard
        defaultSearchEngine = SearchEngine(rawValue: d.string(forKey: "defaultSearchEngine") ?? "") ?? .google
        customSearchEngineTemplate = d.string(forKey: "customSearchEngineTemplate") ?? ""
        defaultWebsiteMode = WebsiteMode(rawValue: d.string(forKey: "defaultWebsiteMode") ?? "") ?? .desktop
        startPageStyle = StartPageStyle(rawValue: d.string(forKey: "startPageStyle") ?? "") ?? .dashboard
        openNewTabsAdjacent = d.object(forKey: "openNewTabsAdjacent") as? Bool ?? true
        homeCardCornerRadius = d.object(forKey: "homeCardCornerRadius") as? Double ?? 14
        homeCardTransparency = d.object(forKey: "homeCardTransparency") as? Double ?? 0.06
        homeCardBlur = d.object(forKey: "homeCardBlur") as? Double ?? 20
        homeBackgroundColorHex = d.string(forKey: "homeBackgroundColorHex") ?? AccentPreset.lavender.hex
        homeBackgroundOpacity = d.object(forKey: "homeBackgroundOpacity") as? Double ?? 0.0
        homeBackgroundBlur = d.object(forKey: "homeBackgroundBlur") as? Double ?? 0

        colorSchemePreference = ColorSchemePreference(rawValue: d.string(forKey: "colorSchemePreference") ?? "") ?? .dark
        accentColorHex = d.string(forKey: "accentColorHex") ?? AccentPreset.lavender.hex
        lastAppliedThemePresetID = d.string(forKey: "lastAppliedThemePresetID")
        backgroundStyle = BackgroundStyle(rawValue: d.string(forKey: "backgroundStyle") ?? "") ?? .defaultStyle
        backgroundSolidHex = d.string(forKey: "backgroundSolidHex") ?? "#0B0B12"
        gradientStartHex = d.string(forKey: "gradientStartHex") ?? "#7C3AED"
        gradientEndHex = d.string(forKey: "gradientEndHex") ?? "#EC4899"
        gradientAngleDegrees = d.object(forKey: "gradientAngleDegrees") as? Double ?? 45
        gradientIntensity = d.object(forKey: "gradientIntensity") as? Double ?? 0.6
        customBackgroundImagePath = d.string(forKey: "customBackgroundImagePath")
        backgroundImageBlur = d.object(forKey: "backgroundImageBlur") as? Double ?? 0
        backgroundBlurAmount = d.object(forKey: "backgroundBlurAmount") as? Double ?? 26
        backgroundImageOpacity = d.object(forKey: "backgroundImageOpacity") as? Double ?? 1.0
        backgroundImageFillMode = BackgroundFillMode(rawValue: d.string(forKey: "backgroundImageFillMode") ?? "") ?? .fill

        sidebarWidth = d.object(forKey: "sidebarWidth") as? Double ?? 310
        sidebarTransparency = d.object(forKey: "sidebarTransparency") as? Double ?? 0.6
        sidebarBlur = d.object(forKey: "sidebarBlur") as? Double ?? 20
        sidebarCornerRadius = d.object(forKey: "sidebarCornerRadius") as? Double ?? 16
        sidebarCompactMode = d.object(forKey: "sidebarCompactMode") as? Bool ?? false
        sidebarShowFavicons = d.object(forKey: "sidebarShowFavicons") as? Bool ?? true
        sidebarAlwaysShow = d.object(forKey: "sidebarAlwaysShow") as? Bool ?? true
        sidebarAutoHide = d.object(forKey: "sidebarAutoHide") as? Bool ?? false
        hideStatusBarInFullScreen = d.object(forKey: "hideStatusBarInFullScreen") as? Bool ?? false
        windowMargin = d.object(forKey: "windowMargin") as? Double ?? 14

        archiveInterval = ArchiveInterval(rawValue: d.string(forKey: "archiveInterval") ?? "") ?? .sevenDays
        lastActiveSpaceIDString = d.string(forKey: "lastActiveSpaceID")
        lastActiveTabIDString = d.string(forKey: "lastActiveTabID")
        trackingProtectionEnabled = d.object(forKey: "trackingProtectionEnabled") as? Bool ?? true
        javaScriptEnabled = d.object(forKey: "javaScriptEnabled") as? Bool ?? true
        downloadHistoryRetained = d.object(forKey: "downloadHistoryRetained") as? Bool ?? true

        userDisplayName = d.string(forKey: "userDisplayName") ?? "there"
    }

    private func save<T>(_ value: T, _ key: String) {
        defaults.set(value, forKey: key)
    }

    var accentColor: Color { Color(hex: accentColorHex) }
}
