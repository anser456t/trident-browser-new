import SwiftUI

/// Settings for how the Start page looks: search field placement and the
/// styling of its Quick Access / widget cards.
struct HomeScreenSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsGroup("Layout") {
                Picker("Start Page Style", selection: $settings.startPageStyle) {
                    ForEach(StartPageStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Toggle("Search Bar at Top", isOn: $settings.searchBarAtTop)
            }

            settingsGroup("Card Appearance") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Corner Radius").foregroundStyle(.secondary)
                    Slider(value: $settings.homeCardCornerRadius, in: 0...28, step: 1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transparency").foregroundStyle(.secondary)
                    Slider(value: $settings.homeCardTransparency, in: 0...1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Blur").foregroundStyle(.secondary)
                    Slider(value: $settings.homeCardBlur, in: 0...40)
                }
            }
        }
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
        }
    }
}
