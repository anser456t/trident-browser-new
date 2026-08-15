import Foundation
import SwiftData
import SwiftUI

@Model
final class Space {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var symbolName: String
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, colorHex: String = "#8B5CF6", symbolName: String = "square.stack", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var color: Color { Color(hex: colorHex) }

    static func defaultSpaces() -> [Space] {
        [
            Space(name: "Personal", colorHex: "#A78BFA", symbolName: "person.crop.circle", sortOrder: 0),
            Space(name: "Work", colorHex: "#60A5FA", symbolName: "briefcase", sortOrder: 1)
        ]
    }
}
