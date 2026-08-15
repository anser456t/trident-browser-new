import SwiftUI
import SwiftData
import UIKit

struct SidebarView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookmarkItem.sortOrder) private var bookmarkItems: [BookmarkItem]

    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingBookmarks = false
    @State private var showingDownloads = false
    @State private var showingAddQuickTile = false

    var body: some View {
        // Only the trailing corners (facing the web content) round off — the
        // sidebar's leading/top/bottom edges sit flush against the physical
        // screen edge now, so rounding them would just clip into empty space.
        // `ContentView.webContentArea` rounds its own leading corners by this
        // same `settings.sidebarCornerRadius` value, so the seam between the
        // two panels always lines up, and the corner-radius slider visibly
        // moves both sides together instead of only affecting the sidebar.
        GlassPanel(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0, bottomLeading: 0,
                bottomTrailing: settings.sidebarCornerRadius, topTrailing: settings.sidebarCornerRadius
            ),
            tintOpacity: settings.sidebarTransparency,
            blurAmount: settings.sidebarBlur
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Nav controls (back/forward/reload, fullscreen) live on the
                // same row as the sidebar-hide control, docked to it — this
                // keeps the address bar itself down to just the URL field and
                // its own menu, and this row is always the first thing in the
                // sidebar, never mixed into the tab list below.
                HStack(spacing: 4) {
                    toolbarIconButton("chevron.left") { browser.goBack() }
                        .disabled(!(browser.currentController?.canGoBack ?? false))
                    toolbarIconButton("chevron.right") { browser.goForward() }
                        .disabled(!(browser.currentController?.canGoForward ?? false))
                    toolbarIconButton(browser.currentController?.isLoading == true ? "xmark" : "arrow.clockwise") {
                        browser.currentController?.isLoading == true ? browser.stop() : browser.reload()
                    }
                    // Moved here from the address bar's own button row per
                    // request — copy sits with the other nav controls now,
                    // the address bar itself stays free of buttons.
                    toolbarIconButton("doc.on.doc") {
                        UIPasteboard.general.string = browser.currentTab?.urlString
                        browser.showToast("Link copied")
                    }

                    Spacer()

                    // `ContentView` already applies `.animation(value:)` to
                    // both of these properties at the root of the view tree.
                    // Wrapping the mutation in a *second*, explicitly-scoped
                    // `withAnimation` here raced that outer animation for
                    // ownership of the same layout transaction — while a
                    // page's own HTML5 video happened to be in native
                    // fullscreen, that race was enough to tear down WebKit's
                    // fullscreen presentation mid-transition and crash the
                    // app. Just set the value; the root animation handles it.
                    toolbarIconButton("arrow.up.left.and.arrow.down.right") {
                        browser.isFullScreenActive = true
                    }
                    toolbarIconButton("sidebar.left") {
                        browser.isSidebarVisible = false
                    }
                }

                AddressBarView()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        quickAction(icon: "plus", label: "New Tab") { browser.createTab() }
                        quickAction(icon: "eyeglasses", label: "Private") {
                            browser.isPrivateModeActive = true
                            browser.createTab()
                        }
                    }
                    HStack(spacing: 8) {
                        quickAction(icon: "plus", label: nil) { browser.createTab() }
                        quickAction(icon: "eyeglasses", label: nil) {
                            browser.isPrivateModeActive = true
                            browser.createTab()
                        }
                    }
                }

                sectionHeader("Quick Access")
                quickAccessTiles

                sectionHeader("Spaces")
                SpaceSwitcherView()

                if let spaceID = browser.currentSpaceID {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            let pinned = browser.pinnedTabs(for: spaceID)
                            if !pinned.isEmpty {
                                sectionHeader("Pinned")
                                VStack(spacing: 2) {
                                    tabRows(for: pinned)
                                }
                            }

                            let regular = browser.regularTabs(for: spaceID)
                            sectionHeader("Tabs (\(regular.count))")
                            VStack(spacing: 2) {
                                tabRows(for: regular)
                            }

                            let archived = browser.archivedTabs(for: spaceID)
                            if !archived.isEmpty {
                                sectionHeader("Archived")
                                VStack(spacing: 2) {
                                    ForEach(archived) { tab in
                                        Button {
                                            browser.unarchive(tab)
                                            browser.select(tab: tab)
                                        } label: {
                                            HStack {
                                                FaviconView(host: tab.host, size: 14)
                                                Text(tab.title).font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }

                Spacer(minLength: 0)
                Divider().overlay(Color.white.opacity(0.08))
                SidebarBottomBar(
                    showingSettings: $showingSettings,
                    showingHistory: $showingHistory,
                    showingBookmarks: $showingBookmarks,
                    showingDownloads: $showingDownloads
                )
            }
            .padding(12)
        }
        .frame(width: min(browser.sidebarDragWidth ?? settings.sidebarWidth, browser.maxAllowedSidebarWidth))
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingHistory) { HistoryView() }
        .sheet(isPresented: $showingBookmarks) { BookmarksView() }
        .sheet(isPresented: $showingDownloads) { DownloadsView() }
        .sheet(isPresented: $showingAddQuickTile) {
            QuickTileEditorSheet(nextSortOrder: (bookmarkItems.map(\.sortOrder).max() ?? -1) + 1)
        }
    }

    /// Row of pinned "shortcut" icons — unlike a tab in the list below, tapping
    /// one always opens a brand-new tab at that link rather than switching to
    /// an existing tab. Backed by the same `BookmarkItem` table Quick Access
    /// on the Start page uses, so tiles added from either place show up in both.
    /// A wrapping grid rather than a horizontal scroller, so a narrow sidebar
    /// never clips tiles off-screen — they flow onto additional rows instead.
    private var quickAccessTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 34), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(bookmarkItems.prefix(16)) { bookmark in
                Button {
                    browser.createTab()
                    browser.navigate(to: bookmark.urlString)
                } label: {
                    FaviconView(host: bookmark.url?.host ?? "", size: 18)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .contextMenu {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        modelContext.delete(bookmark)
                        try? modelContext.save()
                    }
                }
            }
            Button { showingAddQuickTile = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(PressFeedbackButtonStyle())
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 6)
    }

    /// Renders one row per tab — except while Split View is active, when the
    /// primary tab and its split partner merge into a single
    /// `SplitMergedTabRow` (wherever the primary tab happens to sit; pinned
    /// or regular) and the partner's own separate row is skipped so it
    /// doesn't also show up on its own elsewhere in the list.
    @ViewBuilder
    private func tabRows(for tabs: [BrowserTab]) -> some View {
        ForEach(tabs.filter { $0.id != browser.splitTabID }) { tab in
            if let splitID = browser.splitTabID, tab.id == browser.currentTabID, let splitTab = browser.tab(withID: splitID) {
                SplitMergedTabRow(primary: tab, split: splitTab)
            } else {
                TabRowView(tab: tab)
            }
        }
    }

    /// When `label` is nil, renders as an icon-only chip. `ViewThatFits`
    /// picks this variant automatically once the sidebar is too narrow for
    /// the full "New Tab" / "Private" / "Start" text to fit on one line —
    /// so the labels never wrap to a second line, they just disappear.
    private func quickAction(icon: String, label: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                if let label {
                    Text(label)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, label == nil ? 8 : 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }

    private func toolbarIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(6)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }
}

/// Sheet for adding a sidebar Quick Access tile. Writes to the same
/// `BookmarkItem` table as the Start page's Quick Access row.
private struct QuickTileEditorSheet: View {
    @EnvironmentObject var browser: BrowserViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let nextSortOrder: Int

    @State private var title = ""
    @State private var urlString = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)
                    TextField("URL", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Add Quick Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addAndDismiss() }.disabled(resolvedURLString == nil)
                }
            }
        }
        .onAppear {
            if let tab = browser.currentTab, tab.urlString != "trident://start" {
                urlString = tab.urlString
                title = tab.title
            }
        }
    }

    private var resolvedURLString: String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return candidate
    }

    private func addAndDismiss() {
        guard let resolved = resolvedURLString else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = BookmarkItem(
            title: name.isEmpty ? (URL(string: resolved)?.host ?? resolved) : name,
            urlString: resolved,
            sortOrder: nextSortOrder
        )
        modelContext.insert(bookmark)
        try? modelContext.save()
        dismiss()
    }
}
