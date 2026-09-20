import Foundation
@preconcurrency import WebKit

/// Small built-in baseline for the user-facing tracking-protection switch.
/// This is deliberately conservative: it blocks well-known third-party
/// analytics/ad endpoints, but does not pretend to be a complete filter list.
enum TrackingProtectionRules {
    private static let rules: [[String: Any]] = [
        [
            "trigger": [
                "url-filter": ".*(doubleclick\\.net|google-analytics\\.com|googletagmanager\\.com|adservice\\.google\\.com|facebook\\.net|connect\\.facebook\\.net|ads-twitter\\.com).*",
                "load-type": ["third-party"]
            ],
            "action": ["type": "block"]
        ]
    ]

    static func apply(to controller: WKUserContentController, completion: @escaping () -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let encoded = String(data: data, encoding: .utf8) else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "trident-built-in-tracking-protection-v1",
            encodedContentRuleList: encoded
        ) { list, _ in
            if let list {
                controller.add(list)
            }
            DispatchQueue.main.async(execute: completion)
        }
    }
}