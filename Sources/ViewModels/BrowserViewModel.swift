import Foundation
import SwiftData
import SwiftUI
import Combine

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

    /// Live WKWebView controllers, keyed by tab id. Created lazily, evicted for archived tabs.
    @Published private(set) var webControllers: [UUID: WebViewController] = [:]

    private var recentlyClosedStack: [(tab: BrowserTab, closedAt: Date)] = []

    init(context: ModelContext, settings: AppSettings) {
        self.context = context
        self.settings = settings
        loadSpaces()
        loadTabs()
        applyArchivePolicy()
        DownloadManager.shared.modelContext = context
        ExtensionManager.shared.load(context: context)

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
        tabs = (try? context.fetch(descriptor)) ?? []
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
        tabs.filter { $0.spaceID == spaceID && $0.isArchived }
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

    // MARK: - Tab lifecycle

    @discardableResult
    func createTab(urlString: String = "trident://start", pinned: Bool = false, activate: Bool = true) -> BrowserTab {
        let spaceID = currentSpaceID ?? spaces.first!.id
        let maxOrder = tabs.filter { $0.spaceID == spaceID }.map(\.sortOrder).max() ?? 0
        let tab = BrowserTab(
            spaceID: spaceID,
            urlString: urlString,
            isPinned: pinned,
            isPrivate: isPrivateModeActive,
            sortOrder: maxOrder + 1,
            useDesktopMode: settings.defaultWebsiteMode == .desktop
        )
        context.insert(tab)
        saveContext()
        tabs.append(tab)
        if activate { select(tab: tab) }
        return tab
    }

    func select(tab: BrowserTab) {
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
        recentlyClosedStack.append((tab, Date()))
        webControllers[tab.id] = nil
        tabs.removeAll { $0.id == tab.id }
        context.delete(tab)
        saveContext()

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
        guard let last = recentlyClosedStack.popLast() else { return }
        context.insert(last.tab)
        saveContext()
        tabs.append(last.tab)
        select(tab: last.tab)
    }

    func togglePin(_ tab: BrowserTab) {
        tab.isPinned.toggle()
        saveContext()
    }

    func duplicateTab(_ tab: BrowserTab) {
        let copy = createTab(urlString: tab.urlString, pinned: tab.isPinned, activate: false)
        copy.title = tab.title
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
        webControllers[tab.id] = nil
        saveContext()
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
            javaScriptEnabled: settings.javaScriptEnabled,
            userScripts: scripts,
            extensions: extensions,
            browser: self
        )
        controller.onCreateNewTab = { [weak self] url in
            self?.createTab(urlString: url.absoluteString)
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
        controller.$currentURLString
            .removeDuplicates()
            .sink { [weak self, weak tab] urlString in
                guard let self, let tab, !urlString.isEmpty else { return }
                tab.urlString = urlString
                try? self.context.save()
                if !tab.isPrivate {
                    self.recordHistory(title: tab.title, urlString: urlString)
                }
            }
            .store(in: &cancellables)

        controller.$title
            .removeDuplicates()
            .sink { [weak tab, weak self] title in
                guard let tab, let self else { return }
                tab.title = title
                try? self.context.save()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

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
        let related = tabs.filter { $0.spaceID == space.id }
        related.forEach { context.delete($0) }
        tabs.removeAll { $0.spaceID == space.id }
        context.delete(space)
        spaces.removeAll { $0.id == space.id }
        saveContext()
        if currentSpaceID == space.id {
            currentSpaceID = spaces.first?.id
            currentTabID = firstSelectableTab()?.id
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
