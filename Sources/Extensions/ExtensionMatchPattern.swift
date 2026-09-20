import Foundation

/// Parses and evaluates Chrome-style match patterns, e.g.:
///   https://example.com/*
///   https://*.example.com/*
///   http://*/*
///   https://*/*
///   <all_urls>
///
/// Grammar (per the WebExtension spec, minus the deprecated `file://` /
/// `ftp://` schemes which have no place in a WKWebView-based browser):
///   <url-pattern> := <scheme>://<host><path>
///   <scheme>      := '*' | 'http' | 'https'
///   <host>        := '*' | '*.' <any char except '/' and '*'>+
///   <path>        := '/' <any chars>
enum ExtensionMatchPattern {
    struct Parsed: Equatable {
        let isAllURLs: Bool
        let scheme: String   // "*", "http", "https"
        let host: String     // "*", "*.example.com", "example.com"
        let path: String     // e.g. "/*", "/foo/*"
    }

    /// Parses a single pattern string. Returns nil if the pattern is malformed.
    static func parse(_ pattern: String) -> Parsed? {
        if pattern == "<all_urls>" {
            return Parsed(isAllURLs: true, scheme: "*", host: "*", path: "/*")
        }
        guard let schemeRange = pattern.range(of: "://") else { return nil }
        let scheme = String(pattern[pattern.startIndex..<schemeRange.lowerBound])
        guard scheme == "*" || scheme == "http" || scheme == "https" else { return nil }

        let rest = pattern[schemeRange.upperBound...]
        guard let pathStart = rest.firstIndex(of: "/") else { return nil }
        let host = String(rest[rest.startIndex..<pathStart])
        let path = String(rest[pathStart...])
        guard !host.isEmpty else { return nil }
        return Parsed(isAllURLs: false, scheme: scheme, host: host, path: path)
    }

    /// Whether `url` is matched by ANY of `patterns` (the normal way
    /// `matches`/`host_permissions` arrays are evaluated — it's an OR).
    static func matches(url: URL, anyOf patterns: [String]) -> Bool {
        patterns.contains { matches(url: url, pattern: $0) }
    }

    static func matches(url: URL, pattern: String) -> Bool {
        guard let parsed = parse(pattern) else { return false }
        guard let scheme = url.scheme?.lowercased() else { return false }

        if parsed.isAllURLs {
            return scheme == "http" || scheme == "https"
        }
        guard schemeMatches(parsed.scheme, scheme) else { return false }
        guard let host = url.host?.lowercased() else { return false }
        guard hostMatches(parsed.host, host) else { return false }
        return pathMatches(parsed.path, url.path.isEmpty ? "/" : url.path)
    }

    private static func schemeMatches(_ pattern: String, _ actual: String) -> Bool {
        pattern == "*" ? (actual == "http" || actual == "https") : pattern == actual
    }

    private static func hostMatches(_ pattern: String, _ actual: String) -> Bool {
        let pattern = pattern.lowercased()
        if pattern == "*" { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2)) // drop "*."
            return actual == suffix || actual.hasSuffix("." + suffix)
        }
        return pattern == actual
    }

    private static func pathMatches(_ pattern: String, _ actual: String) -> Bool {
        // Path patterns use only '*' as a wildcard (matches zero or more of
        // any character); everything else is literal. Convert to a regex.
        var regexString = "^"
        for char in pattern {
            if char == "*" {
                regexString += ".*"
            } else {
                regexString += NSRegularExpression.escapedPattern(for: String(char))
            }
        }
        regexString += "$"
        guard let regex = try? NSRegularExpression(pattern: regexString) else { return false }
        let range = NSRange(actual.startIndex..<actual.endIndex, in: actual)
        return regex.firstMatch(in: actual, range: range) != nil
    }

    /// True if `pattern` is syntactically well-formed.
    static func isValid(_ pattern: String) -> Bool {
        parse(pattern) != nil
    }
}

#if DEBUG
/// Lightweight, dependency-free sanity checks. There's no Swift toolchain
/// available in the environment these were authored in, so this couldn't be
/// run through XCTest before landing — call `ExtensionMatchPattern.runSelfTest()`
/// once (e.g. from a debug menu action) to verify on-device instead of
/// trusting this blind. Each assertion documents the exact case it covers.
enum ExtensionMatchPatternSelfTest {
    static func run() -> [String] {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        check("exact host", ExtensionMatchPattern.matches(url: URL(string: "https://example.com/")!, pattern: "https://example.com/*"))
        check("subdomain wildcard matches bare domain", ExtensionMatchPattern.matches(url: URL(string: "https://example.com/")!, pattern: "https://*.example.com/*"))
        check("subdomain wildcard matches subdomain", ExtensionMatchPattern.matches(url: URL(string: "https://www.example.com/")!, pattern: "https://*.example.com/*"))
        check("subdomain wildcard rejects different domain", !ExtensionMatchPattern.matches(url: URL(string: "https://evil.com/")!, pattern: "https://*.example.com/*"))
        check("scheme wildcard", ExtensionMatchPattern.matches(url: URL(string: "http://example.com/")!, pattern: "*://example.com/*"))
        check("all_urls matches https", ExtensionMatchPattern.matches(url: URL(string: "https://anything.test/x")!, pattern: "<all_urls>"))
        check("all_urls rejects non-http(s)", !ExtensionMatchPattern.matches(url: URL(string: "trident://start")!, pattern: "<all_urls>"))
        check("path wildcard narrows correctly", !ExtensionMatchPattern.matches(url: URL(string: "https://example.com/other")!, pattern: "https://example.com/foo/*"))
        check("path wildcard allows match", ExtensionMatchPattern.matches(url: URL(string: "https://example.com/foo/bar")!, pattern: "https://example.com/foo/*"))
        check("http-only wildcard host", ExtensionMatchPattern.matches(url: URL(string: "http://anything.test/")!, pattern: "http://*/*"))
        check("malformed pattern rejected", !ExtensionMatchPattern.isValid("not-a-pattern"))
        check("ftp scheme rejected", !ExtensionMatchPattern.isValid("ftp://example.com/*"))

        return failures
    }
}
#endif
