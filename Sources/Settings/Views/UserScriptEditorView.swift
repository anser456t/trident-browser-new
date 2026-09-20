import SwiftUI
import SwiftData

/// Add/edit sheet for a `UserScriptPlugin`. Passing `script: nil` creates a
/// new one on save; passing an existing instance edits it in place.
struct UserScriptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let script: UserScriptPlugin?

    @State private var name: String = ""
    @State private var matchPattern: String = "*"
    @State private var code: String = ""
    @State private var saveError: String?

    private var isNew: Bool { script == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Match Pattern (\"*\" for all sites, or a hostname substring like \"example.com\")", text: $matchPattern)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } header: {
                    Text("Details")
                }

                Section {
                    TextEditor(text: $code)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 220)
                } header: {
                    Text("JavaScript")
                } footer: {
                    Text("Runs at document end on pages whose hostname matches the pattern above.")
                }

                if !isNew {
                    Section {
                        Button("Delete User Script", role: .destructive) {
                            if let script { context.delete(script) }
                            persist()
                            if saveError == nil { dismiss() }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New User Script" : "Edit User Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let script {
                            script.name = name
                            script.matchPattern = matchPattern.isEmpty ? "*" : matchPattern
                            script.code = code
                        } else {
                            let created = UserScriptPlugin(name: name.isEmpty ? "Untitled Script" : name,
                                                            matchPattern: matchPattern.isEmpty ? "*" : matchPattern,
                                                            code: code)
                            context.insert(created)
                        }
                        persist()
                        if saveError == nil { dismiss() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            guard let script else { return }
            name = script.name
            matchPattern = script.matchPattern
            code = script.code
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func persist() {
        do {
            try context.save()
        } catch {
            print("[UserScriptEditorView] save failed: \(error)")
            saveError = error.localizedDescription
        }
    }
}
