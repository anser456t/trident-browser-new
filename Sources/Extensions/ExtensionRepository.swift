import Foundation

/// Owns the on-disk layout for installed extensions:
///
///   Application Support/Extensions/<extension-id>/
///       manifest.json
///       icon.png
///       background.js
///       content.js
///       popup.html
///       ...
///       .storage.local.json   (written by ExtensionLocalStorage, not this type)
///
/// Nothing else in the extension system should build these paths by hand —
/// that's the whole point of having this type exist.
enum ExtensionRepository {
    static var rootDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A folder inside the app's Documents directory — which, thanks to
    /// `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` already
    /// being set in Info.plist, shows up in the Files app under
    /// **On My iPad/iPhone → Trident**. Dropping a `.zip` in here (via
    /// AirDrop, copy-paste, Save to Files, iCloud sync, etc.) is a second,
    /// independent way to install an extension that doesn't go through
    /// `.fileImporter`/`UIDocumentPickerViewController` at all — useful
    /// exactly when that picker itself is misbehaving.
    static var dropFolderDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Add Extension Here", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func directory(for extensionID: String) -> URL {
        rootDirectory.appendingPathComponent(extensionID, isDirectory: true)
    }

    static func fileURL(extensionID: String, relativePath: String) -> URL {
        directory(for: extensionID).appendingPathComponent(relativePath)
    }

    @discardableResult
    static func createDirectory(for extensionID: String) throws -> URL {
        let dir = directory(for: extensionID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func remove(extensionID: String) {
        try? FileManager.default.removeItem(at: directory(for: extensionID))
    }

    static func exists(extensionID: String) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: extensionID).path)
    }
}
