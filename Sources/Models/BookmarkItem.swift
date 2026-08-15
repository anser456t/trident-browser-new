import Foundation
import SwiftData

@Model
final class BookmarkFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var parentID: UUID?
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

@Model
final class BookmarkItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var urlString: String
    var folderID: UUID?
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, folderID: UUID? = nil, sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.folderID = folderID
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var url: URL? { URL(string: urlString) }
}
