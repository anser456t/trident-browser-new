import Foundation
import SwiftData

/// Registers and tracks downloads. The actual byte transfer is handled natively
/// by WKDownload (see WebViewController) — this class exists so the Downloads UI
/// and SwiftData persistence stay in sync with what WKDownload is doing.
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    var modelContext: ModelContext?

    /// Last-seen (timestamp, bytesWritten) per download, used to compute the
    /// instantaneous transfer rate shown in the Downloads UI.
    private var lastSample: [UUID: (date: Date, bytes: Int64)] = [:]

    private init() {}

    /// Files land in the app's own Documents/Downloads folder. Because Info.plist
    /// enables `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`,
    /// anything saved here shows up automatically in the on-device Files app
    /// under "On My iPad/iPhone ▸ Trident" — no extra step needed.
    static var downloadsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    func registerDownload(fileName: String, sourceURLString: String, localPath: String) -> DownloadItem {
        let item = DownloadItem(fileName: fileName, sourceURLString: sourceURLString)
        item.localPathString = localPath
        item.status = .inProgress
        modelContext?.insert(item)
        try? modelContext?.save()
        return item
    }

    func markCompleted(id: UUID) {
        lastSample[id] = nil
        update(id) { item in
            item.status = .completed
            item.completedAt = Date()
            if let path = item.localPathString {
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
                if let size { item.totalBytes = size; item.bytesWritten = size }
            }
        }
    }

    func markFailed(id: UUID) {
        lastSample[id] = nil
        update(id) { $0.status = .failed }
    }

    func updateProgress(id: UUID, fraction: Double) {
        update(id) { $0.fractionCompleted = fraction }
    }

    /// Called with the byte counts straight off `WKDownload`'s underlying
    /// `Progress` object, so the Downloads list can show real speed and
    /// remaining-data figures instead of just a bare percentage.
    func updateProgress(id: UUID, bytesWritten: Int64, totalBytes: Int64) {
        let now = Date()
        var rate: Double = 0
        if let previous = lastSample[id] {
            let elapsed = now.timeIntervalSince(previous.date)
            let delta = bytesWritten - previous.bytes
            if elapsed > 0.05, delta >= 0 {
                rate = Double(delta) / elapsed
            }
        }
        lastSample[id] = (now, bytesWritten)

        update(id) { item in
            item.bytesWritten = bytesWritten
            if totalBytes > 0 { item.totalBytes = totalBytes }
            if totalBytes > 0 { item.fractionCompleted = Double(bytesWritten) / Double(totalBytes) }
            if rate > 0 { item.bytesPerSecond = rate }
        }
    }

    private func update(_ id: UUID, _ mutate: (DownloadItem) -> Void) {
        guard let context = modelContext,
              let item = try? context.fetch(FetchDescriptor<DownloadItem>(predicate: #Predicate { $0.id == id })).first
        else { return }
        mutate(item)
        try? context.save()
    }
}
