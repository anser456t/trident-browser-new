import SwiftUI
import SwiftData

struct HistoryView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HistoryEntry.visitedAt, order: .reverse) private var entries: [HistoryEntry]
    @Environment(\.modelContext) private var context
    @State private var searchText = ""

    private var grouped: [(day: String, items: [HistoryEntry])] {
        let filtered = searchText.isEmpty ? entries : entries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) || $0.urlString.localizedCaseInsensitiveContains(searchText)
        }
        let groups = Dictionary(grouping: filtered) { entry in
            entry.visitedAt.formatted(date: .abbreviated, time: .omitted)
        }
        return groups.keys.sorted(by: >).map { key in (day: key, items: groups[key]!.sorted { $0.visitedAt > $1.visitedAt }) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.day) { group in
                    Section(group.day) {
                        ForEach(group.items) { entry in
                            Button {
                                browser.createTab(urlString: entry.urlString)
                                dismiss()
                            } label: {
                                HStack {
                                    FaviconView(host: entry.url?.host ?? "", size: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title).lineLimit(1)
                                        Text(entry.urlString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            offsets.map { group.items[$0] }.forEach(context.delete)
                            try? context.save()
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search History")
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All", role: .destructive) {
                        entries.forEach(context.delete)
                        try? context.save()
                    }
                }
            }
        }
    }
}
