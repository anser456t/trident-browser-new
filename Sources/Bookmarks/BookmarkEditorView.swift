import SwiftUI
import SwiftData

struct BookmarkEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let bookmark: BookmarkItem
    let folders: [BookmarkFolder]

    @State private var title: String = ""
    @State private var urlString: String = ""
    @State private var folderID: UUID?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("URL", text: $urlString)
                Picker("Folder", selection: $folderID) {
                    Text("None").tag(UUID?.none)
                    ForEach(folders) { folder in
                        Text(folder.name).tag(UUID?.some(folder.id))
                    }
                }
                Button("Delete Bookmark", role: .destructive) {
                    context.delete(bookmark)
                    persist()
                    if saveError == nil { dismiss() }
                }
            }
            .navigationTitle("Edit Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        bookmark.title = title
                        bookmark.urlString = urlString
                        bookmark.folderID = folderID
                        persist()
                        if saveError == nil { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            title = bookmark.title
            urlString = bookmark.urlString
            folderID = bookmark.folderID
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
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
            print("[BookmarkEditorView] save failed: \(error)")
            saveError = error.localizedDescription
        }
    }
}
