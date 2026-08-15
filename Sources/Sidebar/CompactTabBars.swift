import SwiftUI
import UniformTypeIdentifiers

/// A single horizontal strip shown above the web content when the sidebar is
/// hidden. Pinned tabs (compact, favicon-only) come first, followed by a thin
/// divider and then regular open tabs (favicon + title). Both groups can be
/// reordered independently by dragging chips past one another.
///
/// Rendering always reads live from `BrowserViewModel` (so pin/unpin, new
/// tabs, etc. show up immediately) except for the one group currently being
/// dragged, which briefly renders from a local in-memory copy so the reorder
/// preview can move smoothly; that copy is discarded the moment the drop
/// completes and the real `sortOrder` has been persisted.
struct CompactTabStripView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings

    /// Shows a leading button that opens the sidebar. Only needed when the
    /// sidebar is hidden and there's no other on-screen way to reach it
    /// (i.e. we're not on the Start page, which has its own entry point).
    var showsSidebarToggle: Bool = false

    @State private var pinnedDragOverride: [BrowserTab]?
    @State private var regularDragOverride: [BrowserTab]?
    @State private var draggingPinnedID: UUID?
    @State private var draggingRegularID: UUID?

    private var livePinned: [BrowserTab] {
        guard let spaceID = browser.currentSpaceID else { return [] }
        return browser.pinnedTabs(for: spaceID)
    }

    private var liveRegular: [BrowserTab] {
        guard let spaceID = browser.currentSpaceID else { return [] }
        return browser.regularTabs(for: spaceID)
    }

    private var displayedPinned: [BrowserTab] { pinnedDragOverride ?? livePinned }
    private var displayedRegular: [BrowserTab] { regularDragOverride ?? liveRegular }

    var body: some View {
        Group {
            if !displayedPinned.isEmpty || !displayedRegular.isEmpty || showsSidebarToggle {
                // The sidebar-show toggle used to be the first chip *inside*
                // the horizontally-scrolling tab strip, so it scrolled away
                // with the tabs and was easy to lose. It's now a fixed button
                // docked above/before the strip, so it's always reachable.
                HStack(spacing: 6) {
                    if showsSidebarToggle {
                        sidebarToggleChip
                    }
                    tabStrip
                }
            }
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(displayedPinned.filter { $0.id != browser.splitTabID }) { tab in
                    Group {
                        if let splitID = browser.splitTabID, tab.id == browser.currentTabID, let splitTab = browser.tab(withID: splitID) {
                            SplitMergedTabRow(primary: tab, split: splitTab)
                        } else {
                            pinnedChip(for: tab)
                        }
                    }
                    .onDrag {
                        pinnedDragOverride = livePinned
                        draggingPinnedID = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: TabChipDropDelegate(
                        item: tab,
                        items: Binding(
                            get: { pinnedDragOverride ?? livePinned },
                            set: { pinnedDragOverride = $0 }
                        ),
                        draggingID: $draggingPinnedID,
                        onReorder: { newOrder in
                            browser.reorderTabs(newOrder)
                            pinnedDragOverride = nil
                        }
                    ))
                }

                if !displayedPinned.isEmpty && !displayedRegular.isEmpty {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)
                }

                ForEach(displayedRegular.filter { $0.id != browser.splitTabID }) { tab in
                    Group {
                        if let splitID = browser.splitTabID, tab.id == browser.currentTabID, let splitTab = browser.tab(withID: splitID) {
                            SplitMergedTabRow(primary: tab, split: splitTab)
                        } else {
                            regularChip(for: tab)
                        }
                    }
                    .onDrag {
                        regularDragOverride = liveRegular
                        draggingRegularID = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: TabChipDropDelegate(
                        item: tab,
                        items: Binding(
                            get: { regularDragOverride ?? liveRegular },
                            set: { regularDragOverride = $0 }
                        ),
                        draggingID: $draggingRegularID,
                        onReorder: { newOrder in
                            browser.reorderTabs(newOrder)
                            regularDragOverride = nil
                        }
                    ))
                }

                Button { browser.createTab() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                // See the matching comment in SidebarView: `ContentView`
                // already animates `isFullScreenActive` at the root, so this
                // just sets the value rather than opening a second, competing
                // animation transaction.
                Button { browser.isFullScreenActive = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(GlassPanel(cornerRadius: 12) { Color.clear })
    }

    private var sidebarToggleChip: some View {
        Button {
            browser.isSidebarVisible = true
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func pinnedChip(for tab: BrowserTab) -> some View {
        let isActive = browser.currentTabID == tab.id
        return Button {
            browser.select(tab: tab)
        } label: {
            FaviconView(host: tab.host, size: 16)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? settings.accentColor.opacity(0.3) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Unpin Tab", systemImage: "pin.slash") { browser.togglePin(tab) }
            Button("Duplicate Tab", systemImage: "plus.square.on.square") { browser.duplicateTab(tab) }
            if !isActive {
                Button("Split View", systemImage: "rectangle.split.2x1") { browser.openInSplit(tab) }
            }
            Button("Archive Tab", systemImage: "archivebox") { browser.archive(tab) }
            Divider()
            Button("Close Tab", systemImage: "xmark", role: .destructive) { browser.closeTab(tab) }
        }
    }

    private func regularChip(for tab: BrowserTab) -> some View {
        let isActive = browser.currentTabID == tab.id
        return Button {
            browser.select(tab: tab)
        } label: {
            HStack(spacing: 5) {
                FaviconView(host: tab.host, size: 13)
                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.caption2)
                    .lineLimit(1)
                if let controller = browser.webControllers[tab.id] {
                    AudioIndicatorBadge(controller: controller, diameter: 15)
                }
                // Matches TabRowView in the full sidebar: only the tab
                // you're currently on gets an always-visible close button.
                if isActive {
                    Button {
                        browser.closeTab(tab)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                }
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? settings.accentColor.opacity(0.3) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 160)
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", systemImage: tab.isPinned ? "pin.slash" : "pin") {
                browser.togglePin(tab)
            }
            Button("Duplicate Tab", systemImage: "plus.square.on.square") { browser.duplicateTab(tab) }
            if !isActive {
                Button("Split View", systemImage: "rectangle.split.2x1") { browser.openInSplit(tab) }
            } else if browser.splitTabID != nil {
                Button("Close Split View", systemImage: "rectangle.split.2x1", role: .destructive) { browser.closeSplit() }
            }
            Button("Archive Tab", systemImage: "archivebox") { browser.archive(tab) }
            Divider()
            Button("Close Tab", systemImage: "xmark", role: .destructive) { browser.closeTab(tab) }
        }
    }
}
