import SwiftUI

struct DownloadsSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("Location") {
                Text(DownloadManager.downloadsDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Files downloaded in Trident are saved to the app's Downloads folder and are visible in the Files app under On My iPad ▸ Trident.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsGroup("History") {
                Toggle("Keep Download History", isOn: $settings.downloadHistoryRetained)
            }
        }
    }
}
