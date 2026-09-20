import Foundation
import SwiftData
import SwiftUI
import Combine
import UIKit

@MainActor
final class BrowserViewModel: ObservableObject {
    let context: ModelContext
    private let settings: AppSettings

    @Published var spaces: [Space] = []
    @Published var currentSpaceID: UUID?
    @Published var tabs: [BrowserTab] = []
    @Published var currentTabID: UUID?
    @Published var isPrivateModeActive: Bool = false
    @Published var isSidebarVisible: Bool = true
    @Published var addressBarText: String = ""
    @Published var isEditingAddressBar: Bool = false
    @Published var toastMessage: String?
    /// True while the immersive full-screen reading mode is active: sidebar,
    /// address bar, and tab strip are all hidden and the web content fills
    /// the entire screen edge-to-edge.
    @Published var isFullScreenActive: Bool = false
    /// Live sidebar width while the user is dragging its resize handle. `nil`
    /// when not actively dragging, in which case `settings.sidebarWidth` applies.
    @Published var sidebarDragWidth: Double?
    /// The widest the sidebar is allowed to render at, recalculated in real
    /// time from the window's current size (see `ContentView`). Keeps the
    /// sidebar from ever crushing the content area in a narrow multitasking
    /// window or a resized windowed-mode session.
    @Published var maxAllowedSidebarWidth: Double = 400
    /// When set, `ContentView` renders this tab's web content side-by-side
    /// with the current tab (Split View) instead of full-width. `nil` means
    /// no split is active.
    @Published var splitTabID: UUID?
    /// Fraction (0...1) of the content area's width given to the leading
    /// (primary) pane while Split View is active. Persists across tab
    /// switches within the session so dragging the divider "sticks".
    @Published var splitDividerFraction: Double = 0.5

    /// Live WKWebView controllers, keyed by tab id. Created lazily, evicted for archived tabs.
    @Published private(set) var webControllers: [UUID: WebViewController] = [:]

    private struct ClosedTabSnapshot {
        let spaceID: UUID
        let urlString: String
        let title: String
        let faviconURLString: String?
        let isPinned: Bool
        let isPrivate: Bool
        let sortOrder: Int
        let useDesktopMode: Bool
    }

    private var recentlyClosedStack: [(snapshot: ClosedTabSnapshot, closedAt: Date)] = []
    private var controllerCancellables: [UUID: Set<AnyCancellable>] = [:]

    init(context: ModelContext, settings: AppSettings) {
        self.context = context
        self.settings = settings
        loadSpaces()
        loadTabs()
        applyArchivePolicy()
        DownloadManager.shared.modelContext = context
        DownloadManager.shared.setHistoryRetained(settings.downloadHistoryRetained)
        ExtensionManager.shared.load(context: context)
        for ext in ExtensionManager.shared.enabledExtensions {
            ExtensionServiceWorkerManager.shared.ensureLoaded(ext, browser: self)
        }

        // Restore the Space the user was last looking at (falling back to the
        // first Space if it was deleted, or none was ever recorded — e.g.
        // first launch). Without this, every relaunch reset to `spaces.first`
        // regardless of where the user actually left off, which made tabs
        // living in any other Space effectively invisible.
        if let savedSpaceIDString = settings.lastActiveSpaceIDString,
           let savedSpaceID = UUID(uuidString: savedSpaceIDString),
           spaces.contains(where: { $0.id == savedSpaceID }) {
            currentSpaceID = savedSpaceID
        } else {
            currentSpaceID = spaces.first?.id
        }

        // Restore the exact tab the user was on within that Space, not just
        // "the first tab" — private tabs are never restored across launches.
        if let savedTabIDString = settings.lastActiveTabIDString,
           let savedTabID = UUID(uuidString: savedTabIDString),
           let savedTab = tabs.first(where: { $0.id == savedTabID }),
           savedTab.spaceID == currentSpaceID, !savedTab.isArchived, !savedTab.isPrivate {
            currentTabID = savedTabID
        }
        // On a fresh install (or right after the last tab is closed and the
        // DB genuinely has zero rows) there's no tab to select, so
        // `currentTab`/`currentController` stay nil forever and the content
        // area just shows its `ProgressView()` placeholder — permanently,
        // since nothing here ever creates the first tab for the user. Any
        // other tab-open action "fixes" it only because *that* action
        // happens to create a tab. Do it here instead, unconditionally.
        if currentTabID == nil {
            currentTabID = firstSelectableTab()?.id ?? createTab(activate: false).id
        }
        if let id = currentTabID { activateWebController(for: id) }
        persistActiveSelection()
    }

    // MARK: - Loading

    func loadSpaces() {
        let descriptor = FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)])
        spaces = (try? context.fetch(descriptor)) ?? []
        if spaces.isEmpty {
            let defaults = Space.defaultSpaces()
            defaults.forEach { context.insert($0) }
            saveContext()
            spaces = defaults
        }
    }

    func loadTabs() {
        let descriptor = FetchDescriptor<BrowserTab>(sortBy: [SortDescriptor(\.sortOrder)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        // Private tabs were persisted by older builds. Remove those legacy
        // records instead of allowing them to survive a relaunch.
        let legacyPrivateTabs = fetched.filter(\.isPrivate)
        legacyPrivateTabs.forEach { context.delete($0) }
        if !legacyPrivateTabs.isEmpty {
            saveContext()
        }
        tabs = fetched.filter { !$0.isPrivate }
    }

    private func firstSelectableTab() -> BrowserTab? {
        tabs.first { $0.spaceID == currentSpaceID && !$0.isArchived && $0.isPrivate == isPrivateModeActive }
    }

    /// Every mutation in this view model routes its save through here so a
    /// failure is at least visible in the console instead of being silently
    /// swallowed by `try?` — which is what made tabs/bookmarks appearing to
    /// vanish on relaunch impossible to diagnose remotely.
    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("[BrowserViewModel] context.save() failed: \(error)")
            showToast("Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Derived collections

    func pinnedTabs(for spaceID: UUID) -> [BrowserTab] {
        tabs.filter { $0.spaceID == spaceID && $0.isPinned && !$0.isArchived && $0.isPrivate == isPrivateModeActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func regularTabs(for spaceID: UUID) -> [BrowserTab] {
        tabs.filter { $0.spaceID == spaceID && !$0.isPinned && !$0.isArchived && $0.isPrivate == isPrivateModeActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func archivedTabs(for spaceID: UUID) -> [BrowserTab] {
        tabs.filter { $0.spaceID == spaceID && $0.isArchived && $0.isPrivate == isPrivateModeActive }
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
    }

    var currentTab: BrowserTab? {
        guard let id = currentTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    var currentController: WebViewController? {
        guard let id = currentTabID else { return nil }
        return webControllers[id]
    }

    var currentSpace: Space? {
        spaces.first { $0.id == currentSpaceID }
    }

    // MARK: - Split View

    /// Opens `tab` alongside the current tab in a second pane. Splitting a
    /// tab with itself is a no-op — there'd be nothing to compare it to.
    func openInSplit(_ tab: BrowserTab) {
        guard tab.id != currentTabID,
              tab.spaceID == currentSpaceID,
              !tab.isArchived,
              tab.isPrivate == isPrivateModeActive else { return }
        splitTabID = tab.id
        activateWebController(for: tab.id)
    }

    func closeSplit() {
        splitTabID = nil
    }

    /// Promotes the split pane to be the primary tab and closes the split —
    /// used when the user wants to "swap" which side is primary.
    func swapSplitToPrimary() {
        guard let splitTabID, let tab = tab(withID: splitTabID) else { return }
        self.splitTabID = nil
        select(tab: tab)
    }

    // MARK: - Tab lifecycle

    @discardableResult
    func createTab(urlString: String = "trident://start", pinned: Bool = false, activate: Bool = true) -> BrowserTab {
        let spaceID = currentSpaceID ?? spaces.first!.id
        let tabsInSpace = tabs.filter { $0.spaceID == spaceID }
        let order: Int
        if settings.openNewTabsAdjacent,
           let current = currentTab,
           current.spaceID == spaceID,
           current.isPrivate == isPrivateModeActive {
            order = current.sortOrder + 1
            for existing in tabsInSpace where existing.sortOrder >= order {
                existing.sortOrder += 1
            }
        } else {
            order = (tabsInSpace.map(\.sortOrder).max() ?? 0) + 1
        }
        let tab = BrowserTab(
            spaceID: spaceID,
            urlString: urlString,
            isPinned: pinned,
            isPrivate: isPrivateModeActive,
            sortOrder: order,
            useDesktopMode: settings.defaultWebsiteMode == .desktop
        )
        if !tab.isPrivate {
            context.insert(tab)
            saveContext()
        }
        tabs.append(tab)
        if activate { select(tab: tab) }
        return tab
    }

    func select(tab: BrowserTab) {
        guard tab.spaceID == currentSpaceID,
              !tab.isArchived,
              tab.isPrivate == isPrivateModeActive else { return }
        // Selecting the tab that's currently in the split pane as the new
        // primary would show the same page in both panes — treat it as
        // "promote split to primary" instead, which is the only sensible
        // outcome and matches what the user's tap looks like they meant.
        if splitTabID == tab.id {
            splitTabID = nil
        }
        currentTabID = tab.id
        tab.lastAccessedAt = Date()
        saveContext()
        activateWebController(for: tab.id)
        addressBarText = tab.urlString == "trident://start" ? "" : tab.urlString
        persistActiveSelection()
    }

    /// Records which Space and tab are currently active so the next launch
    /// can restore them. Private tabs are deliberately not remembered here —
    /// `loadTabs`/`select` never mark a private tab as the saved selection in
    /// a way that would resurrect it, consistent with private tabs not
    /// carrying over browsing state either.
    private func persistActiveSelection() {
        settings.lastActiveSpaceIDString = currentSpaceID?.uuidString
        if let tab = currentTab, !tab.isPrivate {
            settings.lastActiveTabIDString = tab.id.uuidString
        }
    }

    func closeTab(_ tab: BrowserTab) {
        let snapshot = ClosedTabSnapshot(
            spaceID: tab.spaceID,
            urlString: tab.urlString,
            title: tab.title,
            faviconURLString: tab.faviconURLString,
            isPinned: tab.isPinned,
            isPrivate: tab.isPrivate,
            sortOrder: tab.sortOrder,
            useDesktopMode: tab.useDesktopMode
        )
        recentlyClosedStack.append((snapshot, Date()))
        releaseWebController(for: tab.id)
        tabs.removeAll { $0.id == tab.id }
        if !tab.isPrivate {
            context.delete(tab)
            saveContext()
        }

        if splitTabID == tab.id {
            splitTabID = nil
        }

        if currentTabID == tab.id {
            if let next = firstSelectableTab() {
                select(tab: next)
            } else {
                currentTabID = nil
                let fresh = createTab()
                select(tab: fresh)
            }
        }
    }

    func restoreLastClosedTab() {
        guard let index = recentlyClosedStack.lastIndex(where: { $0.snapshot.isPrivate == isPrivateModeActive }),
              let space = spaces.first(where: { $0.id == recentlyClosedStack[index].snapshot.spaceID }) else { return }
        let last = recentlyClosedStack.remove(at: index)
        let snapshot = last.snapshot
        let tab = BrowserTab(
            spaceID: space.id,
            urlString: snapshot.urlString,
            title: snapshot.title,
            isPinned: snapshot.isPinned,
            isPrivate: snapshot.isPrivate,
            sortOrder: snapshot.sortOrder,
            useDesktopMode: snapshot.useDesktopMode
        )
        tab.faviconURLString = snapshot.faviconURLString
        tabs.append(tab)
        if !tab.isPrivate {
            context.insert(tab)
            saveContext()
        }
        currentSpaceID = space.id
        select(tab: tab)
    }

    func togglePin(_ tab: BrowserTab) {
        tab.isPinned.toggle()
        saveContext()
    }

    func duplicateTab(_ tab: BrowserTab) {
        let copy = createTab(urlString: tab.urlString, pinned: tab.isPinned, activate: false)
        copy.title = tab.title
        copy.faviconURLString = tab.faviconURLString
        if !copy.isPrivate { saveContext() }
    }

    func rename(_ tab: BrowserTab, to newTitle: String) {
        tab.title = newTitle
        saveContext()
    }

    func move(_ tab: BrowserTab, toSpace spaceID: UUID) {
        tab.spaceID = spaceID
        saveContext()
    }

    func archive(_ tab: BrowserTab) {
        tab.isArchived = true
        releaseWebController(for: tab.id)
        if !tab.isPrivate { saveContext() }
        if currentTabID == tab.id {
            splitTabID = nil
            if let next = firstSelectableTab() {
                select(tab: next)
            } else {
                let fresh = createTab()
                select(tab: fresh)
            }
        }
    }

    func unarchive(_ tab: BrowserTab) {
        tab.isArchived = false
        tab.lastAccessedAt = Date()
        saveContext()
    }

    /// Persists a new relative order for any homogeneous group of tabs (e.g. the
    /// pinned tabs in a Space, or the regular tabs in a Space). Since pinned and
    /// regular tabs are always filtered into separate arrays before sorting by
    /// `sortOrder`, re-numbering just the tabs in `newOrder` never collides with
    /// the other group.
    func reorderTabs(_ newOrder: [BrowserTab]) {
        for (index, tab) in newOrder.enumerated() {
            tab.sortOrder = index
        }
        saveContext()
    }

    func tab(withID id: UUID) -> BrowserTab? {
        tabs.first { $0.id == id }
    }

    private func applyArchivePolicy() {
        guard let interval = settings.archiveInterval.timeInterval else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        for tab in tabs where !tab.isArchived && !tab.isPinned && tab.lastAccessedAt < cutoff {
            tab.isArchived = true
        }
        saveContext()
    }

    // MARK: - Web controllers

    func activateWebController(for tabID: UUID) {
        guard webControllers[tabID] == nil, let tab = tabs.first(where: { $0.id == tabID }) else { return }
        let scripts = (try? context.fetch(FetchDescriptor<UserScriptPlugin>())) ?? []
        let extensions = ExtensionManager.shared.enabledExtensions
        let controller = WebViewController(
            id: tabID,
            isPrivate: tab.isPrivate,
            useDesktopMode: tab.useDesktopMode,
            trackingProtectionEnabled: settings.trackingProtectionEnabled,
            javaScriptEnabled: settings.javaScriptEnabled,
            userScripts: scripts,
            extensions: extensions,
            browser: self
        )
        controller.onCreateNewTab = { [weak self] url in
            self?.createTab(urlString: url.absoluteString)
        }
        controller.onOpenLinkInNewTab = { [weak self] url in
            self?.createTab(urlString: url.absoluteString, activate: false)
            self?.showToast("Opened in new tab")
        }
        controller.onDownloadWillStart = { [weak self] in
            self?.showToast("Download started")
        }
        webControllers[tabID] = controller
        if tab.urlString != "trident://start" {
            controller.load(urlString: tab.urlString)
        }
        observeControllerForHistoryAndTitle(controller, tab: tab)
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toastMessage == message { toastMessage = nil }
        }
    }

    private func observeControllerForHistoryAndTitle(_ controller: WebViewController, tab: BrowserTab) {
        var observations = Set<AnyCancellable>()
        controller.$currentURLString
            .removeDuplicates()
            .sink { [weak self, weak tab] urlString in
                guard let self, let tab, !urlString.isEmpty else { return }
                tab.urlString = urlString
                if !tab.isPrivate { self.saveContext() }
                if !tab.isPrivate {
                    self.recordHistory(title: tab.title, urlString: urlString)
                }
            }
            .store(in: &observations)

        controller.$title
            .removeDuplicates()
            .sink { [weak tab, weak self] title in
                guard let tab, let self else { return }
                tab.title = title
                if !tab.isPrivate { self.saveContext() }
            }
            .store(in: &observations)
        controllerCancellables[tab.id] = observations
    }

    private func releaseWebController(for tabID: UUID) {
        webControllers[tabID] = nil
        controllerCancellables[tabID] = nil
        if splitTabID == tabID {
            splitTabID = nil
        }
    }

    private func recordHistory(title: String, urlString: String) {
        let entry = HistoryEntry(title: title.isEmpty ? urlString : title, urlString: urlString)
        context.insert(entry)
        saveContext()
    }

    // MARK: - Navigation

    func navigate(to raw: String) {
        guard let tab = currentTab else { return }
        guard let url = InputInterpreter.resolve(raw, engine: settings.defaultSearchEngine, customTemplate: settings.customSearchEngineTemplate) else { return }
        activateWebController(for: tab.id)
        webControllers[tab.id]?.load(urlString: url.absoluteString)
        addressBarText = url.absoluteString
        isEditingAddressBar = false
    }

    func goBack() { currentController?.goBack() }
    func goForward() { currentController?.goForward() }
    func reload() { currentController?.reload() }
    func stop() { currentController?.stop() }

    /// Passkeys on arbitrary third-party sites may require the system browser's
    /// WebAuthn authorization path. Hand the current HTTPS page to Safari so
    /// Face ID, Touch ID, or the device passcode can complete the challenge.
    func openCurrentPageInSafari() {
        guard let urlString = currentController?.currentURLString,
              let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else {
            showToast("Safari handoff is available for secure web pages")
            return
        }
        UIApplication.shared.open(url)
    }

    // MARK: - Spaces

    @discardableResult
    func createSpace(name: String, colorHex: String, symbolName: String = "square.stack") -> Space {
        let order = (spaces.map(\.sortOrder).max() ?? -1) + 1
        let space = Space(name: name, colorHex: colorHex, symbolName: symbolName, sortOrder: order)
        context.insert(space)
        saveContext()
        spaces.append(space)
        currentSpaceID = space.id
        if firstSelectableTab() == nil { createTab() }
        return space
    }

    func deleteSpace(_ space: Space) {
        guard spaces.count > 1 else { return }
        let related = tabs.filter { $0.spaceID == space.id }
        related.forEach {
            releaseWebController(for: $0.id)
            if !$0.isPrivate { context.delete($0) }
        }
        tabs.removeAll { $0.spaceID == space.id }
        context.delete(space)
        spaces.removeAll { $0.id == space.id }
        saveContext()
        if currentSpaceID == space.id {
            currentSpaceID = spaces.first?.id
            if let next = firstSelectableTab() {
                currentTabID = next.id
                activateWebController(for: next.id)
            } else if currentSpaceID != nil {
                let fresh = createTab(activate: false)
                currentTabID = fresh.id
                activateWebController(for: fresh.id)
            } else {
                currentTabID = nil
            }
            persistActiveSelection()
        }
    }

    func switchSpace(to space: Space) {
        currentSpaceID = space.id
        if let tab = firstSelectableTab() {
            select(tab: tab)
        } else {
            let tab = createTab()
            select(tab: tab)
        }
    }

    // MARK: - Private mode

    func togglePrivateMode() {
        isPrivateModeActive.toggle()
        if let tab = firstSelectableTab() {
            select(tab: tab)
        } else {
            let tab = createTab()
            select(tab: tab)
        }
    }
}
