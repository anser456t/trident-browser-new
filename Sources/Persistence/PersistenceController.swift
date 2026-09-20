import Foundation
import SwiftData

enum PersistenceController {
    /// Set when the on-disk store failed to open and the app had to fall
    /// back to an in-memory (non-persistent) store. When this is non-nil,
    /// EVERYTHING resets every launch — not just tabs and bookmarks — which
    /// is consistent with tabs, favorites, and quick access all vanishing
    /// while URL/visited-link state that WebKit itself keeps (separate from
    /// our database) appears to "remain".
    private(set) static var storeLoadFailure: String?

    /// Shared SwiftData container for all persisted browser data.
    static let container: ModelContainer = {
        let schema = Schema([
            Space.self,
            BrowserTab.self,
            BookmarkFolder.self,
            BookmarkItem.self,
            HistoryEntry.self,
            DownloadItem.self,
            UserScriptPlugin.self,
            WebExtension.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // This is the only place that can tell us WHY the on-disk store
            // didn't open (migration failure, corrupt store, permissions,
            // disk full, etc). Swallowing it silently — as this used to do —
            // is exactly what made this bug undiagnosable: the app looked
            // fine, just quietly reset its data every launch.
            let message = "Trident's on-disk data store failed to open and was replaced with a temporary in-memory store for this session, so nothing will be saved when the app closes.\n\nUnderlying error: \(error)"
            print("[PersistenceController] \(message)")
            storeLoadFailure = message
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: schema, configurations: [fallback]))
                ?? fatalErrorContainer()
        }
    }()

    private static func fatalErrorContainer() -> ModelContainer {
        fatalError("Unable to create ModelContainer for Trident.")
    }
}
