import SwiftUI

/// A single row in the sidebar's tab list: favicon, title, loading indicator,
/// and a full context menu of tab actions.
struct TabRowView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    let tab: BrowserTab
    @State private var isRenaming = false
    @State private var renameText = ""

    private var isActive: Bool { browser.currentTabID == tab.id }
    private var isLoading: Bool { browser.webControllers[tab.id]?.isLoading ?? false }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { browser.select(tab: tab) }
        } label: {
            HStack(spacing: 10) {
                if settings.sidebarShowFavicons {
                    ZStack {
                        FaviconView(host: tab.host, size: 18)
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.5)
                        }
                    }
                }
                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.system(size: settings.sidebarCompactMode ? 12 : 13))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                if tab.isPrivate {
                    Image(systemName: "eyeglasses")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
                // Only the tab you're currently on shows an always-visible
                // close button — everything else stays clean and relies on
                // the existing swipe/long-press-to-close, exactly as before.
                if isActive {
                    Button {
                        browser.closeTab(tab)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, settings.sidebarCompactMode ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? settings.accentColor.opacity(0.28) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu { contextMenuContent }
        .alert("Rename Tab", isPresented: $isRenaming) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { browser.rename(tab, to: renameText) }
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", systemImage: tab.isPinned ? "pin.slash" : "pin") {
            browser.togglePin(tab)
        }
        Button("Rename", systemImage: "pencil") {
            renameText = tab.title
            isRenaming = true
        }
        Button("Duplicate Tab", systemImage: "plus.square.on.square") {
            browser.duplicateTab(tab)
        }
        if !isActive {
            Button("Split View", systemImage: "rectangle.split.2x1") {
                browser.openInSplit(tab)
            }
        } else if browser.splitTabID != nil {
            Button("Close Split View", systemImage: "rectangle.split.2x1", role: .destructive) {
                browser.closeSplit()
            }
        }
        Menu("Move to Space", systemImage: "arrow.right.square") {
            ForEach(browser.spaces.filter { $0.id != tab.spaceID }) { space in
                Button(space.name) { browser.move(tab, toSpace: space.id) }
            }
        }
        Button("Archive Tab", systemImage: "archivebox") {
            browser.archive(tab)
        }
        Divider()
        Button("Close Tab", systemImage: "xmark", role: .destructive) {
            browser.closeTab(tab)
        }
    }
}
