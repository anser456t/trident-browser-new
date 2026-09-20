import Foundation
import SwiftData

/// Persisted record for one installed WebExtension. The actual extension
/// files (manifest.json, background.js, content scripts, icons, popup.html,
/// ...) live on disk under `ExtensionRepository.directory(for:)` — this
/// model only stores metadata + install state, mirroring how `DownloadItem`
/// tracks a file that lives in the Downloads folder rather than embedding
/// bytes in the database.
@Model
final class WebExtension {
    /// Stable, deterministic ID derived from the package contents (see
    /// `ExtensionManager.stableID(for:)`) — NOT random, so re-importing the
    /// same package (e.g. after a reinstall) resolves to the same identity
    /// instead of creating a duplicate.
    @Attribute(.unique) var id: String
    var name: String
    var version: String
    var extensionDescription: String
    var isEnabled: Bool
    var installedAt: Date

    /// Raw manifest JSON, kept verbatim so the manifest can be re-parsed
    /// after an app update without re-reading the extension's own files.
    var manifestJSON: Data

    /// Permissions actually granted at install time (the user may only see
    /// prompts for a subset of what's requested — this is what's honored).
    var grantedPermissions: [String]
    var grantedHostPermissions: [String]

    init(id: String, name: String, version: String, extensionDescription: String,
         manifestJSON: Data, grantedPermissions: [String], grantedHostPermissions: [String]) {
        self.id = id
        self.name = name
        self.version = version
        self.extensionDescription = extensionDescription
        self.isEnabled = true
        self.installedAt = Date()
        self.manifestJSON = manifestJSON
        self.grantedPermissions = grantedPermissions
        self.grantedHostPermissions = grantedHostPermissions
    }

    var manifest: ExtensionManifest? {
        try? ExtensionManifestParser.parse(data: manifestJSON)
    }
}
