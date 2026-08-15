import SwiftUI

/// Shown in place of two separate `TabRowView`s (sidebar list) or chips
/// (compact strip) whenever Split View is active — a single pill holding
/// both tabs' favicon + title side by side, split by a thin divider, so it's
/// visually obvious the two are paired rather than just two ordinary open
/// tabs. Long-press/right-click offers "Unsplit".
struct SplitMergedTabRow: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    let primary: BrowserTab
    let split: BrowserTab

    var body: some View {
        HStack(spacing: 0) {
            half(for: primary)
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: 18)
            half(for: split)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(settings.accentColor.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contextMenu {
            Button("Unsplit", systemImage: "rectangle.split.2x1.slash") {
                browser.closeSplit()
            }
        }
    }

    private func half(for tab: BrowserTab) -> some View {
        HStack(spacing: 5) {
            FaviconView(host: tab.host, size: 14)
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            if let controller = browser.webControllers[tab.id] {
                AudioIndicatorBadge(controller: controller, diameter: 14)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
