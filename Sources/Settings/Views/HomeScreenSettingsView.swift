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
                sliderRow("Webpage Height", value: $settings.homeWebpageHeight, range: 0.65...1.0, unit: "%", isPercent: true)
            }

            settingsGroup("Widget Position") {
                Text("Adjust the Start page widget row inside the webpage surface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                sliderRow("Left", value: $settings.homeWidgetsLeading, range: 0...80, unit: "pt")
                sliderRow("Right", value: $settings.homeWidgetsTrailing, range: 0...80, unit: "pt")
                sliderRow("Top", value: $settings.homeWidgetsTop, range: 0...80, unit: "pt")
                sliderRow("Bottom", value: $settings.homeWidgetsBottom, range: 0...80, unit: "pt")
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

            settingsGroup("Background") {
                Text("A tint layer just for the Start page's own background — separate from the app-wide wallpaper in Appearance settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                    ForEach(AccentPreset.allCases) { preset in
                        Circle()
                            .fill(preset.color)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(Color.primary, lineWidth: settings.homeBackgroundColorHex == preset.hex ? 2 : 0)
                            )
                            .onTapGesture { settings.homeBackgroundColorHex = preset.hex }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tint Opacity").foregroundStyle(.secondary)
                    Slider(value: $settings.homeBackgroundOpacity, in: 0...0.6)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Blur").foregroundStyle(.secondary)
                    Slider(value: $settings.homeBackgroundBlur, in: 0...40)
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

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, isPercent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(isPercent ? "\(Int(value.wrappedValue * 100))\(unit)" : "\(Int(value.wrappedValue))\(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
