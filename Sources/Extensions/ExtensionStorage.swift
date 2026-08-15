import Foundation

/// Backs `chrome.storage.local` for a single extension. Each extension gets
/// its own JSON file inside its own directory — there is no shared table
/// keyed by extension ID that a bug could cross-query, so one extension
/// physically cannot reach another's data through this API.
///
/// `chrome.storage.sync` is not implemented (iCloud key-value storage would
/// be the natural backing, but wiring that up is out of scope for this
/// pass). The `ExtensionStorageBacking` protocol below is what makes adding
/// it later a matter of a new conforming type, not a rewrite of the bridge
/// that calls it.
protocol ExtensionStorageBacking {
    func get(_ keys: [String]?) -> [String: Any]
    func set(_ items: [String: Any])
    func remove(_ keys: [String])
    func clear()
}

final class ExtensionLocalStorage: ExtensionStorageBacking {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "trident.extension-storage", attributes: .concurrent)
    private var cache: [String: Any]

    /// 5 MB mirrors Chrome's default `storage.local` quota, so extensions
    /// written against that assumption behave the same way here.
    static let quotaBytes = 5 * 1024 * 1024

    init(extensionDirectory: URL) {
        fileURL = extensionDirectory.appendingPathComponent(".storage.local.json")
        if let data = try? Data(contentsOf: fileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            cache = json
        } else {
            cache = [:]
        }
    }

    func get(_ keys: [String]?) -> [String: Any] {
        queue.sync {
            guard let keys else { return cache }
            var result: [String: Any] = [:]
            for key in keys { if let value = cache[key] { result[key] = value } }
            return result
        }
    }

    func set(_ items: [String: Any]) {
        queue.sync(flags: .barrier) {
            for (key, value) in items { cache[key] = value }
            persist()
        }
    }

    func remove(_ keys: [String]) {
        queue.sync(flags: .barrier) {
            for key in keys { cache.removeValue(forKey: key) }
            persist()
        }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            cache = [:]
            persist()
        }
    }

    /// Rough byte usage — enough to reject writes that would blow the quota
    /// without needing an exact accounting scheme.
    var estimatedByteCount: Int {
        queue.sync {
            (try? JSONSerialization.data(withJSONObject: cache)).map(\.count) ?? 0
        }
    }

    private func persist() {
        guard let data = try? JSONSerialization.data(withJSONObject: cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Owns one `ExtensionLocalStorage` per extension ID, created on first
/// access and reused — this is the isolation boundary the bridge calls
/// through so it's structurally impossible to pass extension A's storage
/// object while thinking you have extension B's.
final class ExtensionStorageRegistry {
    static let shared = ExtensionStorageRegistry()
    private var instances: [String: ExtensionLocalStorage] = [:]
    private let lock = NSLock()

    func storage(for extensionID: String, directory: URL) -> ExtensionLocalStorage {
        lock.lock()
        defer { lock.unlock() }
        if let existing = instances[extensionID] { return existing }
        let created = ExtensionLocalStorage(extensionDirectory: directory)
        instances[extensionID] = created
        return created
    }

    /// Called on uninstall so a reinstalled extension with the same ID
    /// doesn't inherit stale in-memory state from before the on-disk file
    /// was deleted.
    func discard(extensionID: String) {
        lock.lock()
        defer { lock.unlock() }
        instances.removeValue(forKey: extensionID)
    }
}
