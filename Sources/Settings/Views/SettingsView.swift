import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general, appearance, homeScreen, sidebar, tabs, privacy, downloads, extensions, advanced, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .homeScreen: return "Home Screen"
            case .sidebar: return "Sidebar"
            case .tabs: return "Tabs"
            case .privacy: return "Privacy"
            case .downloads: return "Downloads"
            case .extensions: return "Extensions"
            case .advanced: return "Advanced"
            case .about: return "About Trident"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            case .homeScreen: return "square.grid.2x2"
            case .sidebar: return "sidebar.left"
            case .tabs: return "square.on.square"
            case .privacy: return "hand.raised"
            case .downloads: return "arrow.down.circle"
            case .extensions: return "puzzlepiece.extension"
            case .advanced: return "wrench.and.screwdriver"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.icon).tag(section)
                }
            }
            .navigationTitle("Settings")
        } detail: {
            ScrollView {
                Group {
                    switch selection ?? .general {
                    case .general: GeneralSettingsView()
                    case .appearance: AppearanceSettingsView()
                    case .homeScreen: HomeScreenSettingsView()
                    case .sidebar: SidebarSettingsView()
                    case .tabs: TabsSettingsView()
                    case .privacy: PrivacySettingsView()
                    case .downloads: DownloadsSettingsView()
                    case .extensions: ExtensionsSettingsView()
                    case .advanced: AdvancedSettingsView()
                    case .about: AboutTridentView()
                    }
                }
                .padding(24)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle((selection ?? .general).title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AboutTridentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#A78BFA"), Color(hex: "#7C3AED")], startPoint: .top, endPoint: .bottom))
                    .frame(width: 56, height: 56)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("Trident").font(.title.bold())
            Text("An original, Arc-inspired browser built for iPad with a Liquid Glass interface. Version 1.0.")
                .foregroundStyle(.secondary)
        }
    }
}
