import SwiftUI

struct SidebarSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("Layout") {
                sliderRow("Sidebar Width", value: $settings.sidebarWidth, range: 260...400, unit: "pt")
                sliderRow("Sidebar Height Margin", value: $settings.sidebarVerticalInset, range: 4...48, unit: "pt")
                sliderRow("Transparency", value: $settings.sidebarTransparency, range: 0.2...0.9, unit: "%", isPercent: true)
                sliderRow("Blur Amount", value: $settings.sidebarBlur, range: 0...40, unit: "pt")
                sliderRow("Corner Radius", value: $settings.sidebarCornerRadius, range: 0...28, unit: "pt")
            }

            settingsGroup("Display") {
                Toggle("Show Favicons", isOn: $settings.sidebarShowFavicons)
                Toggle("Show Space Names", isOn: $settings.sidebarShowSpaceNames)
                Toggle("Compact Mode", isOn: $settings.sidebarCompactMode)
            }

            settingsGroup("Behavior") {
                Toggle("Always Show Sidebar", isOn: $settings.sidebarAlwaysShow)
                Toggle("Auto-Hide in Portrait", isOn: $settings.sidebarAutoHide)
            }
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, isPercent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(isPercent ? "\(Int(value.wrappedValue * 100))\(unit)" : "\(Int(value.wrappedValue))\(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
