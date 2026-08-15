import Foundation
import SwiftData

/// A single browsing tab. Named `BrowserTab` to avoid clashing with SwiftUI's `Tab`.
@Model
final class BrowserTab {
    @Attribute(.unique) var id: UUID
    var spaceID: UUID
    var urlString: String
    var title: String
    var faviconURLString: String?
    var isPinned: Bool
    var isPrivate: Bool
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date
    var lastAccessedAt: Date
    var useDesktopMode: Bool

    init(
        id: UUID = UUID(),
        spaceID: UUID,
        urlString: String,
        title: String = "New Tab",
        isPinned: Bool = false,
        isPrivate: Bool = false,
        sortOrder: Int = 0,
        useDesktopMode: Bool = true
    ) {
        self.id = id
        self.spaceID = spaceID
        self.urlString = urlString
        self.title = title
        self.faviconURLString = nil
        self.isPinned = isPinned
        self.isPrivate = isPrivate
        self.isArchived = false
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.useDesktopMode = useDesktopMode
    }

    var url: URL? { URL(string: urlString) }

    var host: String { url?.host ?? "" }
}
