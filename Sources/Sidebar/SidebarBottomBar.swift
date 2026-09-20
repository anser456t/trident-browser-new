import SwiftUI

struct SidebarBottomBar: View {
    @EnvironmentObject var browser: BrowserViewModel
    @Binding var showingSettings: Bool
    @Binding var showingHistory: Bool
    @Binding var showingBookmarks: Bool
    @Binding var showingDownloads: Bool
    @ObservedObject private var extensionManager = ExtensionManager.shared
    @State private var showingExtensionsPanel = false
    @State private var activePopupExtensionID: IdentifiableExtensionID?

    var body: some View {
        HStack(spacing: 14) {
            Button { browser.togglePrivateMode() } label: {
                Image(systemName: browser.isPrivateModeActive ? "eyeglasses" : "eyeglasses")
                    .foregroundStyle(browser.isPrivateModeActive ? .purple : .white.opacity(0.6))
            }
            Button { showingHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.white.opacity(0.6))
            }
            Button { showingBookmarks = true } label: {
                Image(systemName: "book").foregroundStyle(.white.opacity(0.6))
            }
            Button { showingDownloads = true } label: {
                Image(systemName: "arrow.down.circle").foregroundStyle(.white.opacity(0.6))
            }
            if !extensionManager.enabledExtensions.isEmpty && !browser.isPrivateModeActive {
                Button { showingExtensionsPanel = true } label: {
                    Image(systemName: "puzzlepiece.extension").foregroundStyle(.white.opacity(0.6))
                }
                .popover(isPresented: $showingExtensionsPanel) {
                    ExtensionsQuickPanel(activePopupExtensionID: $activePopupExtensionID)
                        .frame(width: 280)
                        .presentationCompactAdaptation(.popover)
                }
            }
            Spacer()
            Button { browser.restoreLastClosedTab() } label: {
                Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.white.opacity(0.6))
            }
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 4)
        .sheet(item: $activePopupExtensionID) { wrapper in
            ExtensionPopupView(extensionID: wrapper.id)
        }
    }
}

/// Local wrapper so `.sheet(item:)` can key off an extension ID without
/// giving `String` itself a module-wide `Identifiable` conformance, which
/// would risk colliding with identical conformances elsewhere.
private struct IdentifiableExtensionID: Identifiable {
    let id: String
}

/// The panel that opens when tapping the toolbar's extension icon: one row
/// per enabled extension. Tapping a row opens its `popup.html` if it
/// declares one; otherwise this is as far as "execute its action" goes for
/// now (see FINAL RESPONSE notes — extensions without a popup have no
/// other defined default behavior in this pass).
private struct ExtensionsQuickPanel: View {
    @ObservedObject private var extensionManager = ExtensionManager.shared
    @Binding var activePopupExtensionID: IdentifiableExtensionID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(extensionManager.enabledExtensions) { ext in
                Button {
                    if ext.manifest?.action?.defaultPopup != nil {
                        activePopupExtensionID = IdentifiableExtensionID(id: ext.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.purple)
                        Text(ext.name)
                        Spacer()
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
    }
}
