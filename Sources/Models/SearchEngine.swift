import Foundation

/// Supported search engines. `.custom` lets the user provide their own template URL.
enum SearchEngine: String, CaseIterable, Codable, Identifiable {
    case google, bing, duckduckgo, brave, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckduckgo: return "DuckDuckGo"
        case .brave: return "Brave Search"
        case .custom: return "Custom"
        }
    }

    /// `%s` is replaced with the URL-encoded query.
    var queryTemplate: String {
        switch self {
        case .google: return "https://www.google.com/search?q=%s"
        case .bing: return "https://www.bing.com/search?q=%s"
        case .duckduckgo: return "https://duckduckgo.com/?q=%s"
        case .brave: return "https://search.brave.com/search?q=%s"
        case .custom: return ""
        }
    }

    func searchURL(for query: String, customTemplate: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let template = (self == .custom) ? customTemplate : queryTemplate
        guard !template.isEmpty else { return nil }
        let urlString = template.replacingOccurrences(of: "%s", with: encoded)
        return URL(string: urlString)
    }
}

/// Determines whether user input should be treated as a URL or a search query.
enum InputInterpreter {
    static func resolve(_ raw: String, engine: SearchEngine, customTemplate: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil, looksLikeHost(trimmed) {
            return url
        }

        if !trimmed.contains(" "), trimmed.contains("."), let url = URL(string: "https://" + trimmed), looksLikeHost(trimmed) {
            return url
        }

        return engine.searchURL(for: trimmed, customTemplate: customTemplate)
    }

    private static func looksLikeHost(_ s: String) -> Bool {
        let candidate = s.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        guard let hostPart = candidate.split(separator: "/").first else { return false }
        return hostPart.contains(".") && !hostPart.contains(" ")
    }
}
