import Foundation

/// The subset of WebExtension API permissions Trident actually implements.
/// Anything an extension requests outside this set is still recorded (so it
/// shows up honestly in the permission prompt) but is never granted access —
/// there's no code path that would honor it.
enum ExtensionPermission: String, CaseIterable {
    case storage
    case tabs
    case activeTab
    case scripting

    var displayDescription: String {
        switch self {
        case .storage: return "Store extension settings"
        case .tabs: return "See your open tabs, titles, and URLs"
        case .activeTab: return "Access the page you're currently viewing when you click it"
        case .scripting: return "Insert JavaScript or CSS into webpages"
        }
    }

    static let supportedRawValues: Set<String> = Set(allCases.map(\.rawValue))
}

/// A single permission line the user is asked to approve, covering both
/// declared API permissions and host permissions (shown separately since
/// they read very differently — "storage" vs. "read and modify
/// youtube.com").
struct ExtensionPermissionRequest: Identifiable {
    enum Kind {
        case api(ExtensionPermission)
        case unsupportedAPI(String)
        case host(String)
    }
    let id = UUID()
    let kind: Kind

    var displayText: String {
        switch kind {
        case .api(let p): return p.displayDescription
        case .unsupportedAPI(let raw): return "\(raw) (not supported — will be ignored)"
        case .host(let pattern):
            if pattern == "<all_urls>" {
                return "Read and modify webpages on any site"
            }
            return "Read and modify webpages on \(Self.friendlyHost(pattern))"
        }
    }

    private static func friendlyHost(_ pattern: String) -> String {
        guard let parsed = ExtensionMatchPattern.parse(pattern) else { return pattern }
        return parsed.host.hasPrefix("*.") ? String(parsed.host.dropFirst(2)) : parsed.host
    }

    static func requests(for manifest: ExtensionManifest) -> [ExtensionPermissionRequest] {
        var requests: [ExtensionPermissionRequest] = []
        for raw in manifest.permissions {
            if let known = ExtensionPermission(rawValue: raw) {
                requests.append(ExtensionPermissionRequest(kind: .api(known)))
            } else {
                requests.append(ExtensionPermissionRequest(kind: .unsupportedAPI(raw)))
            }
        }
        for host in manifest.hostPermissions {
            requests.append(ExtensionPermissionRequest(kind: .host(host)))
        }
        // content_scripts' own `matches` imply host access too, and are the
        // most common way extensions actually request it (host_permissions
        // is often left empty when content_scripts already lists matches).
        for script in manifest.contentScripts {
            for pattern in script.matches where !manifest.hostPermissions.contains(pattern) {
                requests.append(ExtensionPermissionRequest(kind: .host(pattern)))
            }
        }
        return requests
    }
}
