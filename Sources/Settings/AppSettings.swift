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
    @Published var searchBarAtTop: Bool { didSet { save(searchBarAtTop, "searchBarAtTop") } }
    /// Corner radius applied to Quick Access / widget cards on the Start page.
    @Published var homeCardCornerRadius: Double { didSet { save(homeCardCornerRadius, "homeCardCornerRadius") } }
    /// Opacity of the frosted-glass fill behind Start page cards (0 = fully
    /// see-through, 1 = fully opaque).
    @Published var homeCardTransparency: Double { didSet { save(homeCardTransparency, "homeCardTransparency") } }
    /// Background blur radius (points) behind Start page cards.
    @Published var homeCardBlur: Double { didSet { save(homeCardBlur, "homeCardBlur") } }

    // Appearance
    @Published var colorSchemePreference: ColorSchemePreference { didSet { save(colorSchemePreference.rawValue, "colorSchemePreference") } }
    @Published var accentColorHex: String { didSet { save(accentColorHex, "accentColorHex") } }
    @Published var backgroundStyle: BackgroundStyle { didSet { save(backgroundStyle.rawValue, "backgroundStyle") } }
    @Published var backgroundSolidHex: String { didSet { save(backgroundSolidHex, "backgroundSolidHex") } }
    @Published var gradientStartHex: String { didSet { save(gradientStartHex, "gradientStartHex") } }
    @Published var gradientEndHex: String { didSet { save(gradientEndHex, "gradientEndHex") } }
    @Published var gradientAngleDegrees: Double { didSet { save(gradientAngleDegrees, "gradientAngleDegrees") } }
    @Published var gradientIntensity: Double { didSet { save(gradientIntensity, "gradientIntensity") } }
    @Published var customBackgroundImagePath: String? { didSet { save(customBackgroundImagePath, "customBackgroundImagePath") } }
    @Published var backgroundImageBlur: Double { didSet { save(backgroundImageBlur, "backgroundImageBlur") } }
    @Published var backgroundImageOpacity: Double { didSet { save(backgroundImageOpacity, "backgroundImageOpacity") } }
    @Published var backgroundImageFillMode: BackgroundFillMode { didSet { save(backgroundImageFillMode.rawValue, "backgroundImageFillMode") } }

    // Sidebar customization
    @Published var sidebarWidth: Double { didSet { save(sidebarWidth, "sidebarWidth") } }
    @Published var sidebarTransparency: Double { didSet { save(sidebarTransparency, "sidebarTransparency") } }
    @Published var sidebarBlur: Double { didSet { save(sidebarBlur, "sidebarBlur") } }
    @Published var sidebarCornerRadius: Double { didSet { save(sidebarCornerRadius, "sidebarCornerRadius") } }
    @Published var sidebarCompactMode: Bool { didSet { save(sidebarCompactMode, "sidebarCompactMode") } }
    @Published var sidebarShowFavicons: Bool { didSet { save(sidebarShowFavicons, "sidebarShowFavicons") } }
    @Published var sidebarShowSpaceNames: Bool { didSet { save(sidebarShowSpaceNames, "sidebarShowSpaceNames") } }
    @Published var sidebarAlwaysShow: Bool { didSet { save(sidebarAlwaysShow, "sidebarAlwaysShow") } }
    @Published var sidebarAutoHide: Bool { didSet { save(sidebarAutoHide, "sidebarAutoHide") } }
    /// Vertical margin between the sidebar panel and the top/bottom of the window.
    /// Smaller values make the sidebar taller; larger values shrink it. This is how
    /// users adjust sidebar "height" without breaking the full-bleed layout.
    @Published var sidebarVerticalInset: Double { didSet { save(sidebarVerticalInset, "sidebarVerticalInset") } }

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
        searchBarAtTop = d.object(forKey: "searchBarAtTop") as? Bool ?? false
        homeCardCornerRadius = d.object(forKey: "homeCardCornerRadius") as? Double ?? 14
        homeCardTransparency = d.object(forKey: "homeCardTransparency") as? Double ?? 0.06
        homeCardBlur = d.object(forKey: "homeCardBlur") as? Double ?? 20

        colorSchemePreference = ColorSchemePreference(rawValue: d.string(forKey: "colorSchemePreference") ?? "") ?? .dark
        accentColorHex = d.string(forKey: "accentColorHex") ?? AccentPreset.lavender.hex
        backgroundStyle = BackgroundStyle(rawValue: d.string(forKey: "backgroundStyle") ?? "") ?? .defaultStyle
        backgroundSolidHex = d.string(forKey: "backgroundSolidHex") ?? "#0B0B12"
        gradientStartHex = d.string(forKey: "gradientStartHex") ?? "#7C3AED"
        gradientEndHex = d.string(forKey: "gradientEndHex") ?? "#EC4899"
        gradientAngleDegrees = d.object(forKey: "gradientAngleDegrees") as? Double ?? 45
        gradientIntensity = d.object(forKey: "gradientIntensity") as? Double ?? 0.6
        customBackgroundImagePath = d.string(forKey: "customBackgroundImagePath")
        backgroundImageBlur = d.object(forKey: "backgroundImageBlur") as? Double ?? 0
        backgroundImageOpacity = d.object(forKey: "backgroundImageOpacity") as? Double ?? 1.0
        backgroundImageFillMode = BackgroundFillMode(rawValue: d.string(forKey: "backgroundImageFillMode") ?? "") ?? .fill

        sidebarWidth = d.object(forKey: "sidebarWidth") as? Double ?? 310
        sidebarTransparency = d.object(forKey: "sidebarTransparency") as? Double ?? 0.6
        sidebarBlur = d.object(forKey: "sidebarBlur") as? Double ?? 20
        sidebarCornerRadius = d.object(forKey: "sidebarCornerRadius") as? Double ?? 16
        sidebarCompactMode = d.object(forKey: "sidebarCompactMode") as? Bool ?? false
        sidebarShowFavicons = d.object(forKey: "sidebarShowFavicons") as? Bool ?? true
        sidebarShowSpaceNames = d.object(forKey: "sidebarShowSpaceNames") as? Bool ?? true
        sidebarAlwaysShow = d.object(forKey: "sidebarAlwaysShow") as? Bool ?? true
        sidebarAutoHide = d.object(forKey: "sidebarAutoHide") as? Bool ?? false
        sidebarVerticalInset = d.object(forKey: "sidebarVerticalInset") as? Double ?? 0

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
