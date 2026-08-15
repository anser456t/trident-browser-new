import SwiftUI
import SwiftData
import QuickLook

struct DownloadsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \DownloadItem.startedAt, order: .reverse) private var downloads: [DownloadItem]
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            List {
                ForEach(downloads) { item in
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: item))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.fileName).lineLimit(1)
                            switch item.status {
                            case .inProgress:
                                ProgressView(value: item.progress)
                                Text(item.progressSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            case .completed:
                                Text("Completed · \(item.totalBytesFormatted)").font(.caption).foregroundStyle(.green)
                            case .failed:
                                Text("Failed").font(.caption).foregroundStyle(.red)
                            case .cancelled:
                                Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if item.status == .completed, let path = item.localPathString {
                            Button {
                                previewURL = URL(fileURLWithPath: path)
                            } label: {
                                Image(systemName: "eye")
                            }
                            ShareLink(item: URL(fileURLWithPath: path)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        Button(role: .destructive) {
                            if let path = item.localPathString {
                                try? FileManager.default.removeItem(atPath: path)
                            }
                            context.delete(item)
                            try? context.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if downloads.isEmpty {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Files you download from the web will appear here."))
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .quickLookPreview($previewURL)
    }

    private func iconName(for item: DownloadItem) -> String {
        switch item.fileExtension {
        case "PDF": return "doc.richtext"
        case "PNG", "JPG", "JPEG", "GIF", "HEIC": return "photo"
        case "ZIP": return "archivebox"
        case "MP4", "MOV": return "film"
        default: return "doc"
        }
    }
}
