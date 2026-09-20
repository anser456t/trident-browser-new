import Foundation
import SwiftData

enum DownloadStatus: String, Codable {
    case inProgress, completed, failed, cancelled
}

@Model
final class DownloadItem {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var sourceURLString: String
    var localPathString: String?
    var totalBytes: Int64
    var bytesWritten: Int64
    var fractionCompleted: Double
    var statusRaw: String
    var startedAt: Date
    var completedAt: Date?
    /// Instantaneous transfer rate in bytes/sec, recomputed each time
    /// `DownloadManager.updateProgress` sees new bytes. Not persisted across
    /// launches (it's meaningless once a download isn't actively running).
    /// The `= 0` default here (not just in `init`) is required: SwiftData's
    /// lightweight migration only knows how to backfill this field for rows
    /// that existed before it was added if the property declaration itself
    /// carries a default. Without it, migrating an old on-disk store throws
    /// "Cannot migrate store in-place: Validation error missing attribute
    /// values on mandatory destination attribute" and the app silently
    /// falls back to a wiped, in-memory-only store every launch.
    var bytesPerSecond: Double = 0

    init(id: UUID = UUID(), fileName: String, sourceURLString: String, totalBytes: Int64 = 0) {
        self.id = id
        self.fileName = fileName
        self.sourceURLString = sourceURLString
        self.localPathString = nil
        self.totalBytes = totalBytes
        self.bytesWritten = 0
        self.fractionCompleted = 0
        self.statusRaw = DownloadStatus.inProgress.rawValue
        self.startedAt = Date()
        self.completedAt = nil
        self.bytesPerSecond = 0
    }

    var status: DownloadStatus {
        get { DownloadStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    var progress: Double {
        if status == .completed { return 1 }
        if totalBytes > 0 { return Double(bytesWritten) / Double(totalBytes) }
        return fractionCompleted
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.uppercased()
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var bytesWrittenFormatted: String { Self.byteFormatter.string(fromByteCount: bytesWritten) }
    var totalBytesFormatted: String { Self.byteFormatter.string(fromByteCount: totalBytes) }
    var remainingBytesFormatted: String { Self.byteFormatter.string(fromByteCount: max(0, totalBytes - bytesWritten)) }
    var speedFormatted: String { Self.byteFormatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s" }

    /// e.g. "4.2 MB of 12 MB · 1.1 MB/s"
    var progressSummary: String {
        guard status == .inProgress else { return status == .completed ? totalBytesFormatted : "" }
        if totalBytes > 0 {
            var summary = "\(bytesWrittenFormatted) of \(totalBytesFormatted)"
            if bytesPerSecond > 0 { summary += " · \(speedFormatted)" }
            return summary
        } else if bytesPerSecond > 0 {
            return "\(bytesWrittenFormatted) · \(speedFormatted)"
        }
        return "Starting…"
    }
}
