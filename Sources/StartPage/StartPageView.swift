import SwiftUI
import SwiftData

struct StartPageView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookmarkItem.sortOrder) private var bookmarks: [BookmarkItem]
    @State private var quickSearchText = ""
    @State private var showingAddQuickAccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Order matches the layout Anser laid out by hand: greeting,
                // then search, then Quick Access, then the weather/screen
                // time/clock row.
                HomeGreetingHeader()
                    .frame(maxWidth: 900)

                searchField
                    .frame(maxWidth: 560)

                if settings.startPageStyle != .minimal {
                    quickAccessRow
                        .frame(maxWidth: 900)
                }

                HomeWidgetsRow()
                    .frame(maxWidth: 900)

                if settings.startPageStyle == .dashboard {
                    HStack(alignment: .top, spacing: 20) {
                        recentTabsCard
                        pinnedCard
                    }
                    .frame(maxWidth: 900)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .frame(maxWidth: .infinity)
        }
        .background(homeBackgroundLayer)
        .sheet(isPresented: $showingAddQuickAccess) {
            AddQuickAccessSheet(nextSortOrder: (bookmarks.map(\.sortOrder).max() ?? -1) + 1)
        }
    }

    /// The Home-specific "Background" personalization (Settings ▸ Home
    /// Screen ▸ Background) — a tint + frost layer behind the Start page's
    /// own content only, independent of the app-wide wallpaper.
    ///
    /// The "Blur" slider used to layer `.ultraThinMaterial` on top of a
    /// backdrop that's *already* gaussian-blurred by the app-wide
    /// `backgroundBlurAmount` — blurring already-blurred, detail-free
    /// content changes nothing visible, so the slider did nothing on its
    /// own unless the Tint Opacity color was also turned up. `.regularMaterial`
    /// has real visual weight/frosting on its own regardless of what's
    /// behind it, so this now visibly changes with the slider by itself.
    private var homeBackgroundLayer: some View {
        ZStack {
            if settings.homeBackgroundBlur > 0.001 {
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(min(settings.homeBackgroundBlur / 40.0, 1.0))
            }
            if settings.homeBackgroundOpacity > 0.001 {
                Color(hex: settings.homeBackgroundColorHex).opacity(settings.homeBackgroundOpacity)
            }
        }
        .ignoresSafeArea()
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            if !browser.isSidebarVisible {
                // `ContentView` already animates `isSidebarVisible` at the
                // root — see the comment in SidebarView for why stacking a
                // second explicit animation here is what caused crashes.
                Button {
                    browser.isSidebarVisible = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(.white.opacity(0.55))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                Divider().frame(height: 16).overlay(Color.white.opacity(0.15))
            }
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
            TextField("Search the web...", text: $quickSearchText)
                .foregroundStyle(.white)
                .onSubmit { browser.navigate(to: quickSearchText) }
                .submitLabel(.go)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(cardBackground(cornerRadius: 16))
    }

    private var quickAccessRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK ACCESS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(bookmarks.prefix(12)) { bookmark in
                        Button { browser.navigate(to: bookmark.urlString) } label: {
                            VStack(spacing: 8) {
                                FaviconView(host: bookmark.url?.host ?? "", size: 30)
                                    .frame(width: 52, height: 52)
                                    .background(tileBackground)
                                Text(bookmark.title).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                modelContext.delete(bookmark)
                                do { try modelContext.save() } catch { print("[StartPageView] save failed: \(error)"); browser.showToast("Save failed: \(error.localizedDescription)") }
                            }
                        }
                    }
                    Button { showingAddQuickAccess = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 52, height: 52)
                                .background(tileBackground)
                            Text("Add").font(.caption2).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(cardBackground(cornerRadius: 18))
    }

    /// The three Home-screen-personalization sliders (corner radius,
    /// transparency, blur) previously only reached the small Quick Access
    /// tile squares — and `homeCardBlur` wasn't wired to anything at all, so
    /// that slider did nothing no matter where you dragged it. All of the
    /// Start page's card surfaces now share this single background so every
    /// slider visibly changes every card.
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        GlassPanel(cornerRadius: cornerRadius, tintOpacity: settings.homeCardTransparency, blurAmount: settings.homeCardBlur) { Color.clear }
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: settings.homeCardCornerRadius, style: .continuous)
            .fill(Color.white.opacity(settings.homeCardTransparency))
            .background(
                RoundedRectangle(cornerRadius: settings.homeCardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(min(settings.homeCardBlur / 40.0, 1.0))
            )
            .clipShape(RoundedRectangle(cornerRadius: settings.homeCardCornerRadius, style: .continuous))
    }

    private var recentTabsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Tabs").font(.headline).foregroundStyle(.white)
            ForEach(browser.tabs.sorted(by: { $0.lastAccessedAt > $1.lastAccessedAt }).prefix(5)) { tab in
                Button { browser.select(tab: tab) } label: {
                    HStack {
                        FaviconView(host: tab.host, size: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tab.title).font(.caption).foregroundStyle(.white).lineLimit(1)
                            Text(tab.host).font(.caption2).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(cornerRadius: 16))
    }

    private var pinnedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pinned").font(.headline).foregroundStyle(.white)
            if let spaceID = browser.currentSpaceID {
                ForEach(browser.pinnedTabs(for: spaceID).prefix(6)) { tab in
                    Button { browser.select(tab: tab) } label: {
                        HStack {
                            FaviconView(host: tab.host, size: 16)
                            Text(tab.title).font(.caption).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(cornerRadius: 16))
    }
}

/// Sheet presented by the "Add" tile in Quick Access. Creates a `BookmarkItem`
/// (Quick Access reads straight from the bookmarks table), so anything added
/// here also shows up in the regular Bookmarks list.
private struct AddQuickAccessSheet: View {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addAndDismiss() }
                        .disabled(resolvedURLString == nil)
                }
            }
        }
        .onAppear {
            // Prefill from the page currently open, if there is one — the
            // common case is "add the site I'm looking at right now".
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
        do { try modelContext.save() } catch { print("[StartPageView] save failed: \(error)"); browser.showToast("Save failed: \(error.localizedDescription)") }
        dismiss()
    }
}
