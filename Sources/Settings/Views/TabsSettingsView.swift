import SwiftUI

struct TabsSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var browser: BrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("Automatic Archiving") {
                Picker("Archive Inactive Tabs", selection: $settings.archiveInterval) {
                    ForEach(ArchiveInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                Text("Archived tabs are removed from the main list but never deleted — their browsing data is kept until you close them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsGroup("New Tab Behavior") {
                Toggle("Open new tabs next to current tab", isOn: $settings.openNewTabsAdjacent)
            }

            settingsGroup("Restore") {
                Button("Restore Last Closed Tab") { browser.restoreLastClosedTab() }
            }
        }
    }
}
