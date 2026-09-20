import SwiftUI
import SwiftData

struct BookmarksView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BookmarkFolder.sortOrder) private var folders: [BookmarkFolder]
    @Query(sort: \BookmarkItem.sortOrder) private var bookmarks: [BookmarkItem]
    @State private var searchText = ""
    @State private var editingBookmark: BookmarkItem?
    @State private var showingNewFolder = false
    @State private var newFolderName = ""

    private var rootBookmarks: [BookmarkItem] {
        let base = bookmarks.filter { $0.folderID == nil }
        return searchText.isEmpty ? base : base.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !rootBookmarks.isEmpty || searchText.isEmpty {
                    Section("Bookmarks") {
                        ForEach(rootBookmarks) { bookmark in
                            bookmarkRow(bookmark)
                        }
                        .onDelete { offsets in
                            offsets.map { rootBookmarks[$0] }.forEach(context.delete)
                            try? context.save()
                        }
                    }
                }

                ForEach(folders) { folder in
                    let items = bookmarks.filter { $0.folderID == folder.id }
                    if !items.isEmpty || searchText.isEmpty {
                        Section(folder.name) {
                            ForEach(items) { bookmark in
                                bookmarkRow(bookmark)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search Bookmarks")
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Folder") { showingNewFolder = true }
                        if let tab = browser.currentTab {
                            Button("Bookmark Current Tab") {
                                let item = BookmarkItem(title: tab.title, urlString: tab.urlString)
                                context.insert(item)
                                try? context.save()
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Folder", isPresented: $showingNewFolder) {
                TextField("Folder Name", text: $newFolderName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    guard !newFolderName.isEmpty else { return }
                    context.insert(BookmarkFolder(name: newFolderName))
                    try? context.save()
                    newFolderName = ""
                }
            }
        }
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditorView(bookmark: bookmark, folders: folders)
        }
    }

    private func bookmarkRow(_ bookmark: BookmarkItem) -> some View {
        Button {
            browser.createTab(urlString: bookmark.urlString)
            dismiss()
        } label: {
            HStack {
                FaviconView(host: bookmark.url?.host ?? "", size: 18)
                Text(bookmark.title).lineLimit(1)
                Spacer()
                Button {
                    editingBookmark = bookmark
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }
}
