import Foundation
import SwiftData
import CryptoKit

enum ExtensionInstallError: LocalizedError {
    case manifestNotFound
    case alreadyInstalled(String)
    case manifest(ExtensionManifestError)
    case archive(Error)

    var errorDescription: String? {
        switch self {
        case .manifestNotFound:
            return "Unable to install extension\n\nmanifest.json was not found."
        case .alreadyInstalled(let name):
            return "\"\(name)\" is already installed."
        case .manifest(let e):
            return "Unable to install extension\n\n\(e.errorDescription ?? "The manifest is invalid.")"
        case .archive(let e):
            return "Unable to install extension\n\n\((e as? LocalizedError)?.errorDescription ?? e.localizedDescription)"
        }
    }
}

/// A parsed, extracted-to-a-temp-directory package that hasn't been
/// committed to the extension library yet. The UI shows
/// `permissionRequests` to the user (per the spec's "never silently grant
/// dangerous permissions" requirement) before `ExtensionManager.finalize`
/// moves it into place.
struct PendingExtensionInstall: Identifiable {
    let id: String
    let manifest: ExtensionManifest
    let tempDirectory: URL
    let permissionRequests: [ExtensionPermissionRequest]
}

@MainActor
final class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()

    @Published private(set) var extensions: [WebExtension] = []
    var modelContext: ModelContext?

    private init() {}

    func load(context: ModelContext) {
        modelContext = context
        let descriptor = FetchDescriptor<WebExtension>(sortBy: [SortDescriptor(\.installedAt)])
        extensions = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Install (phase 1: extract + parse + validate, no side effects outside temp storage)

    func prepareInstall(fromZipAt sourceURL: URL) throws -> PendingExtensionInstall {
        let entries: [ExtensionZipArchive.Entry]
        do {
            entries = try ExtensionZipArchive.readEntries(at: sourceURL)
        } catch {
            throw ExtensionInstallError.archive(error)
        }

        // manifest.json is normally at the archive root, but some tooling
        // wraps the extension in a single top-level folder — search one
        // level deep too, matching Chrome's own leniency here.
        guard let manifestEntry = entries.first(where: {
            $0.path == "manifest.json" || $0.path.hasSuffix("/manifest.json") && $0.path.split(separator: "/").count == 2
        }) else {
            throw ExtensionInstallError.manifestNotFound
        }
        let packageRoot = manifestEntry.path == "manifest.json" ? "" : String(manifestEntry.path.dropLast("manifest.json".count))

        let manifest: ExtensionManifest
        do {
            manifest = try ExtensionManifestParser.parse(data: manifestEntry.data)
        } catch let e as ExtensionManifestError {
            throw ExtensionInstallError.manifest(e)
        }

        let stableID = Self.stableID(manifestData: manifestEntry.data)
        if extensions.contains(where: { $0.id == stableID }) {
            throw ExtensionInstallError.alreadyInstalled(manifest.name)
        }

        // Extract everything under packageRoot into a scratch directory.
        // Nothing here touches ExtensionRepository's permanent location yet
        // — if the user cancels at the permission prompt, this directory is
        // simply discarded.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-extension-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for entry in entries {
            guard entry.path.hasPrefix(packageRoot) else { continue }
            let relativePath = String(entry.path.dropFirst(packageRoot.count))
            guard !relativePath.isEmpty else { continue }
            let destination = tempDir.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: destination)
        }

        return PendingExtensionInstall(
            id: stableID,
            manifest: manifest,
            tempDirectory: tempDir,
            permissionRequests: ExtensionPermissionRequest.requests(for: manifest)
        )
    }

    // MARK: - Install (phase 2: user approved permissions -> commit)

    @discardableResult
    func finalizeInstall(_ pending: PendingExtensionInstall) throws -> WebExtension {
        let permanentDir = try ExtensionRepository.createDirectory(for: pending.id)
        // Move rather than copy: the temp directory was scratch space only.
        for item in (try? FileManager.default.contentsOfDirectory(at: pending.tempDirectory, includingPropertiesForKeys: nil)) ?? [] {
            let destination = permanentDir.appendingPathComponent(item.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: item, to: destination)
        }
        try? FileManager.default.removeItem(at: pending.tempDirectory)

        let manifestData = try Data(contentsOf: permanentDir.appendingPathComponent("manifest.json"))
        let granted = pending.manifest.permissions.filter { ExtensionPermission.supportedRawValues.contains($0) }
        let record = WebExtension(
            id: pending.id,
            name: pending.manifest.name,
            version: pending.manifest.version,
            extensionDescription: pending.manifest.description ?? "",
            manifestJSON: manifestData,
            grantedPermissions: granted,
            grantedHostPermissions: pending.manifest.hostPermissions
        )
        modelContext?.insert(record)
        try? modelContext?.save()
        extensions.append(record)
        return record
    }

    func cancelPendingInstall(_ pending: PendingExtensionInstall) {
        try? FileManager.default.removeItem(at: pending.tempDirectory)
    }

    // MARK: - Files-app drop folder (fallback path when the system picker misbehaves)

    struct DropFolderScanResult {
        let pending: [PendingExtensionInstall]
        let failures: [(fileName: String, message: String)]
    }

    /// Looks for `.zip` files sitting in `ExtensionRepository.dropFolderDirectory`
    /// (the "Add Extension Here" folder visible in Files), and calls
    /// `prepareInstall` on each one found. Every file — whether it parses
    /// successfully or not — is moved into a `Processed` subfolder
    /// afterward so the same file is never picked up twice and so it's
    /// obvious in Files which files have already been handled.
    func scanDropFolder() -> DropFolderScanResult {
        let dropDir = ExtensionRepository.dropFolderDirectory
        let processedDir = dropDir.appendingPathComponent("Processed", isDirectory: true)
        try? FileManager.default.createDirectory(at: processedDir, withIntermediateDirectories: true)

        let fm = FileManager.default
        let zipFiles = (try? fm.contentsOfDirectory(at: dropDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "zip" } ?? []

        var pendingInstalls: [PendingExtensionInstall] = []
        var failures: [(fileName: String, message: String)] = []

        for fileURL in zipFiles {
            let fileName = fileURL.lastPathComponent
            do {
                let pending = try prepareInstall(fromZipAt: fileURL)
                pendingInstalls.append(pending)
            } catch {
                failures.append((fileName, error.localizedDescription))
            }
            // Move out of the drop folder either way — a failed file stays
            // available (renamed, not deleted) so the user can inspect it,
            // but won't be retried every time the folder is scanned.
            var destination = processedDir.appendingPathComponent(fileName)
            var suffix = 1
            while fm.fileExists(atPath: destination.path) {
                let base = fileURL.deletingPathExtension().lastPathComponent
                destination = processedDir.appendingPathComponent("\(base)-\(suffix).zip")
                suffix += 1
            }
            try? fm.moveItem(at: fileURL, to: destination)
        }

        return DropFolderScanResult(pending: pendingInstalls, failures: failures)
    }

    // MARK: - Lifecycle

    func setEnabled(_ ext: WebExtension, enabled: Bool) {
        ext.isEnabled = enabled
        try? modelContext?.save()
    }

    func uninstall(_ ext: WebExtension) {
        ExtensionServiceWorkerManager.shared.unload(extensionID: ext.id)
        ExtensionStorageRegistry.shared.discard(extensionID: ext.id)
        ExtensionRepository.remove(extensionID: ext.id)
        modelContext?.delete(ext)
        try? modelContext?.save()
        extensions.removeAll { $0.id == ext.id }
    }

    // MARK: - Queries used by content-script injection / the toolbar

    var enabledExtensions: [WebExtension] { extensions.filter(\.isEnabled) }

    func extensions(matching url: URL) -> [WebExtension] {
        enabledExtensions.filter { ext in
            guard let manifest = ext.manifest else { return false }
            return manifest.contentScripts.contains { script in
                ExtensionMatchPattern.matches(url: url, anyOf: script.matches)
            }
        }
    }

    /// SHA-256 over the manifest bytes. Deterministic across reinstalls of
    /// an unmodified package, stable across app relaunches (per the spec's
    /// "must remain unchanged when the app restarts" requirement), and
    /// changes if the extension's manifest changes — which is the right
    /// behavior for a version bump to be treated as an update path by
    /// anything keying off this ID.
    static func stableID(manifestData: Data) -> String {
        SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined()
    }
}
