import SwiftUI
import WebKit

struct PrivacySettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingClearConfirm = false
    @State private var clearedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("Tracking") {
                Toggle("Tracking Protection", isOn: $settings.trackingProtectionEnabled)
                Text("Blocks common third-party trackers where WebKit's content-blocking APIs allow it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsGroup("Browsing Data") {
                Button("Clear Cookies & Website Data", role: .destructive) {
                    showingClearConfirm = true
                }
                if let clearedMessage {
                    Text(clearedMessage).font(.caption).foregroundStyle(.green)
                }
            }

            settingsGroup("Private Browsing") {
                Text("Private tabs use a separate, non-persistent data store and are never added to History.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Clear all cookies and website data?", isPresented: $showingClearConfirm, titleVisibility: .visible) {
            Button("Clear Data", role: .destructive) { clearAllData() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func clearAllData() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                clearedMessage = "Cleared \(records.count) site data records."
            }
        }
    }
}
