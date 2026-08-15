import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// Extensions in Trident come in two forms:
///  - Web Extensions: real Manifest V3 packages (see `ExtensionManager`).
///  - User Scripts: lightweight Tampermonkey/Greasemonkey-style JS
///    injection, which predates Web Extension support and keeps working
///    unchanged alongside it.
struct ExtensionsSettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var browser: BrowserViewModel
    @ObservedObject private var extensionManager = ExtensionManager.shared

    @Query(sort: \UserScriptPlugin.createdAt) private var scripts: [UserScriptPlugin]
    @State private var editingScript: UserScriptPlugin?
    @State private var showingNewScript = false

    @State private var selectedExtension: WebExtension?
    @State private var isImportingZip = false
    @State private var installQueue: [PendingExtensionInstall] = []
    @State private var installError: String?
    @State private var dropFolderFailures: [(fileName: String, message: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("Installed Extensions") {
                if extensionManager.extensions.isEmpty {
                    Text("No extensions installed yet. Add a Manifest V3 WebExtension package (.zip) to get started.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(extensionManager.extensions) { ext in
                        Button {
                            selectedExtension = ext
                        } label: {
                            HStack(spacing: 12) {
                                extensionIcon(ext)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ext.name).foregroundStyle(.primary)
                                    if !ext.extensionDescription.isEmpty {
                                        Text(ext.extensionDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { ext.isEnabled },
                                    set: { extensionManager.setEnabled(ext, enabled: $0) }
                                ))
                                .labelsHidden()
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                HStack {
                    Button("Add Extension") { isImportingZip = true }
                    Button("Open Extensions Folder") { openDropFolderInFiles() }
                }
                Text("Or open the Files app, go to On My iPad/iPhone → Trident → \"Add Extension Here\", and copy a .zip there — Trident checks that folder automatically whenever this screen opens.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            settingsGroup("User Scripts") {
                if scripts.isEmpty {
                    Text("No user scripts yet. Add one to inject custom JavaScript into matching websites — similar to Tampermonkey or Greasemonkey.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scripts) { script in
                        Button {
                            editingScript = script
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(script.name).foregroundStyle(.primary)
                                    Text(script.matchPattern == "*" ? "Runs on all sites" : "Runs on \(script.matchPattern)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { script.isEnabled },
                                    set: { script.isEnabled = $0; try? context.save() }
                                ))
                                .labelsHidden()
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                Button("Add User Script") { showingNewScript = true }
            }

            settingsGroup("About Extensions") {
                Text("Extensions and user scripts take effect for newly opened tabs. Existing open tabs keep running with what was active when they loaded — reload or reopen a tab to pick up changes. Extensions never run in Private tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editingScript) { script in
            UserScriptEditorView(script: script)
        }
        .sheet(isPresented: $showingNewScript) {
            UserScriptEditorView(script: nil)
        }
        .sheet(item: $selectedExtension) { ext in
            ExtensionDetailView(extensionID: ext.id)
        }
        .sheet(item: Binding(
            get: { installQueue.first },
            set: { if $0 == nil && !installQueue.isEmpty { installQueue.removeFirst() } }
        )) { pending in
            ExtensionPermissionPromptView(
                pending: pending,
                onAllow: {
                    do {
                        try extensionManager.finalizeInstall(pending)
                        browser.showToast("\(pending.manifest.name) installed")
                    } catch {
                        installError = error.localizedDescription
                    }
                    if !installQueue.isEmpty { installQueue.removeFirst() }
                },
                onCancel: {
                    extensionManager.cancelPendingInstall(pending)
                    if !installQueue.isEmpty { installQueue.removeFirst() }
                }
            )
        }
        // .zip alone is too strict: depending on how the file reached the
        // device (AirDrop, a share sheet, a cloud provider), iOS sometimes
        // tags it with a more generic UTI and the picker grays it out even
        // though it's a perfectly valid zip. .archive and .data widen what's
        // selectable; ExtensionZipArchive still verifies the actual bytes
        // are a real ZIP afterward; a non-zip file just surfaces a clear
        // "not a valid ZIP archive" error rather than being silently
        // accepted.
        .fileImporter(isPresented: $isImportingZip, allowedContentTypes: [.zip, .archive, .data]) { result in
            switch result {
            case .success(let url):
                importZip(at: url)
            case .failure(let error):
                installError = error.localizedDescription
            }
        }
        .onAppear { scanDropFolder() }
        .alert("Couldn't Install Extension", isPresented: Binding(
            get: { installError != nil }, set: { if !$0 { installError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installError ?? "")
        }
        .alert("Some Files Couldn't Be Installed", isPresented: Binding(
            get: { !dropFolderFailures.isEmpty }, set: { if !$0 { dropFolderFailures = [] } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dropFolderFailures.map { "\($0.fileName): \($0.message)" }.joined(separator: "\n\n"))
        }
    }

    private func importZip(at url: URL) {
        // Security-scoped: .fileImporter hands back a URL outside our
        // sandbox that must be explicitly accessed before reading.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            installQueue.append(try extensionManager.prepareInstall(fromZipAt: url))
        } catch {
            installError = error.localizedDescription
        }
    }

    /// Checks the Files-app-visible "Add Extension Here" folder for zips the
    /// user copy-pasted in directly — the workaround for when the system
    /// document picker itself is misbehaving.
    private func scanDropFolder() {
        let result = extensionManager.scanDropFolder()
        installQueue.append(contentsOf: result.pending)
        if !result.failures.isEmpty {
            dropFolderFailures = result.failures
        }
    }

    private func openDropFolderInFiles() {
        // shareddocuments:// deep-links straight into this app's folder
        // inside the Files app — the standard way for an app to open Files
        // to its own on-device storage.
        guard let path = ExtensionRepository.dropFolderDirectory.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "shareddocuments://\(path)") else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private func extensionIcon(_ ext: WebExtension) -> some View {
        if let manifest = ext.manifest, let iconPath = manifest.icons?.values.first,
           let data = try? Data(contentsOf: ExtensionRepository.fileURL(extensionID: ext.id, relativePath: iconPath)),
           let image = UIImage(data: data) {
            Image(uiImage: image).resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "puzzlepiece.extension.fill")
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
        }
    }
}

struct ExtensionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var extensionManager = ExtensionManager.shared
    let extensionID: String

    private var ext: WebExtension? { extensionManager.extensions.first { $0.id == extensionID } }

    var body: some View {
        NavigationStack {
            Form {
                if let ext {
                    Section {
                        VStack(alignment: .center, spacing: 8) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.purple)
                            Text(ext.name).font(.headline)
                            Text("Version \(ext.version)").font(.caption).foregroundStyle(.secondary)
                            if !ext.extensionDescription.isEmpty {
                                Text(ext.extensionDescription).font(.caption).multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)

                    Section("Permissions") {
                        if ext.grantedPermissions.isEmpty && ext.grantedHostPermissions.isEmpty {
                            Text("No special permissions granted.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(ext.grantedPermissions, id: \.self) { raw in
                            if let permission = ExtensionPermission(rawValue: raw) {
                                Label(permission.displayDescription, systemImage: "checkmark.shield")
                            }
                        }
                        ForEach(ext.grantedHostPermissions, id: \.self) { host in
                            Label("Website Access: \(host)", systemImage: "network")
                        }
                    }

                    Section {
                        Toggle("Enable Extension", isOn: Binding(
                            get: { ext.isEnabled },
                            set: { extensionManager.setEnabled(ext, enabled: $0) }
                        ))
                        Button("Remove Extension", role: .destructive) {
                            extensionManager.uninstall(ext)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Extension Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

extension WebExtension: Identifiable {}
