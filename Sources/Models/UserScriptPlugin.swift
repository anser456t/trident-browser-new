import Foundation
import SwiftData

/// A lightweight "plugin" — a user script injected into matching pages, similar
/// in spirit to Tampermonkey/Greasemonkey userscripts. This is the realistic
/// scope for third-party extensibility inside a custom WKWebView-based browser;
/// Safari's native App Extension API isn't available to non-Safari browsers.
@Model
final class UserScriptPlugin {
    @Attribute(.unique) var id: UUID
    var name: String
    /// A substring to match against the page's hostname, or "*" to run on every site.
    var matchPattern: String
    var code: String
    var isEnabled: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, matchPattern: String = "*", code: String = "", isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.matchPattern = matchPattern
        self.code = code
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
}
