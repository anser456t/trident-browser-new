import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("Web Content") {
                Toggle("JavaScript Enabled", isOn: $settings.javaScriptEnabled)
                Text("Changes apply to newly created tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsGroup("User Agent") {
                Picker("Default Mode", selection: $settings.defaultWebsiteMode) {
                    ForEach(WebsiteMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            settingsGroup("Developer") {
                Text("Web Inspector can be enabled from macOS Safari's Develop menu when the iPad is connected, for debug builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
