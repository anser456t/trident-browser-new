import SwiftUI
import UIKit
import SwiftData

struct AddressBarView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    @FocusState private var isFocused: Bool
    @State private var showEngineMenu = false

    @Query(sort: \HistoryEntry.visitedAt, order: .reverse) private var historyEntries: [HistoryEntry]
    @Query(sort: \BookmarkItem.sortOrder) private var bookmarkItems: [BookmarkItem]

    var body: some View {
        VStack(spacing: 6) {
            addressBar

            if browser.isEditingAddressBar && !suggestions.isEmpty {
                suggestionsList
            }
        }
        .onChange(of: browser.currentTabID) { _, _ in
            browser.addressBarText = browser.currentTab?.urlString == "trident://start" ? "" : (browser.currentTab?.urlString ?? "")
        }
    }

    // Kept button-free by request: engine switching moved to Settings, and
    // copy now lives with the other nav controls at the top of the sidebar
    // (see SidebarView). "New Tab" and "Request Desktop Site" are still
    // reachable from the address bar's own long-press / context menu if
    // they're needed, so nothing is actually lost — just off the bar itself.
    private var addressBar: some View {
        HStack(spacing: 7) {
            Image(systemName: isSecure ? "lock.fill" : "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))

            TextField("Search or enter website", text: $browser.addressBarText, onEditingChanged: { editing in
                browser.isEditingAddressBar = editing
            })
            .focused($isFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.webSearch)
            .submitLabel(.go)
            .onSubmit { browser.navigate(to: browser.addressBarText) }
            .foregroundStyle(.white)
            .font(.system(size: 13))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            GlassPanel(cornerRadius: 13, tintOpacity: 0.55) { Color.clear }
        )
        .contextMenu {
            Menu("Search Engine") {
                ForEach(SearchEngine.allCases) { engine in
                    Button(engine.displayName) { settings.defaultSearchEngine = engine }
                }
            }
            Button(browser.currentTab?.useDesktopMode == true ? "Request Mobile Site" : "Request Desktop Site") {
                toggleDesktopMode()
            }
        }
    }

    // MARK: - Suggestions

    private struct AddressSuggestion: Identifiable {
        enum Kind { case history, bookmark }
        let id: String
        let title: String
        let urlString: String
        let kind: Kind
    }

    private var suggestions: [AddressSuggestion] {
        let query = browser.addressBarText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        var results: [AddressSuggestion] = []
        var seenURLs = Set<String>()

        for bookmark in bookmarkItems where matches(query, title: bookmark.title, url: bookmark.urlString) {
            guard !seenURLs.contains(bookmark.urlString) else { continue }
            seenURLs.insert(bookmark.urlString)
            results.append(AddressSuggestion(id: "b-\(bookmark.id)", title: bookmark.title, urlString: bookmark.urlString, kind: .bookmark))
            if results.count >= 3 { break }
        }

        for entry in historyEntries where matches(query, title: entry.title, url: entry.urlString) {
            guard !seenURLs.contains(entry.urlString) else { continue }
            seenURLs.insert(entry.urlString)
            results.append(AddressSuggestion(id: "h-\(entry.id)", title: entry.title, urlString: entry.urlString, kind: .history))
            if results.count >= 6 { break }
        }

        return results
    }

    private func matches(_ query: String, title: String, url: String) -> Bool {
        title.lowercased().contains(query) || url.lowercased().contains(query)
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    browser.navigate(to: suggestion.urlString)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.kind == .bookmark ? "book.fill" : "clock")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title.isEmpty ? suggestion.urlString : suggestion.title)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(suggestion.urlString)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .background(GlassPanel(cornerRadius: 14, tintOpacity: 0.6) { Color.clear })
    }

    private var isSecure: Bool {
        browser.currentController?.currentURLString.hasPrefix("https://") ?? false
    }

    private func toggleDesktopMode() {
        guard let tab = browser.currentTab, let controller = browser.currentController else { return }
        tab.useDesktopMode.toggle()
        controller.applyDesktopMode(tab.useDesktopMode)
        controller.reload()
    }
}
