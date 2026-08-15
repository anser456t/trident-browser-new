import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("Search") {
                Picker("Default Search Engine", selection: $settings.defaultSearchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                if settings.defaultSearchEngine == .custom {
                    TextField("https://example.com/search?q=%s", text: $settings.customSearchEngineTemplate)
                        .textFieldStyle(.roundedBorder)
                }
            }

            settingsGroup("Website Mode") {
                Picker("Default Website Mode", selection: $settings.defaultWebsiteMode) {
                    ForEach(WebsiteMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("New tabs load sites in this mode. You can override per-tab from the address bar menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsGroup("New Tab") {
                Toggle("Open new tabs next to current tab", isOn: $settings.openNewTabsAdjacent)
                Picker("Start Page Layout", selection: $settings.startPageStyle) {
                    ForEach(StartPageStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }
        }
    }
}

@ViewBuilder
func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.08)))
    }
}
