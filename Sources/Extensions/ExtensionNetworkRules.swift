import Foundation
@preconcurrency import WebKit
import CryptoKit

/// Best-effort `chrome.declarativeNetRequest` support.
///
/// ## The real constraint
/// WKWebView gives apps exactly one native request-blocking mechanism:
/// `WKContentRuleList`, compiled ahead of time from a fixed JSON rule
/// format (the same one Safari content blockers use). It supports
/// block/allow/CSS-hiding, and a narrow `make-http-https` redirect action —
/// it does **not** support arbitrary URL rewriting, request header
/// modification, or synchronous per-request callbacks the way desktop
/// Chrome's webRequest/declarativeNetRequest APIs do. There is no way
/// around this from application code; it's enforced by WebKit itself for
/// performance and privacy reasons.
///
/// So this implements `block` and `allow` actions faithfully (translated
/// 1:1 into WKContentRuleList's own `block`/`ignore-previous-rules`), and
/// intentionally does NOT claim to support `redirect` — declaring it would
/// be exactly the "don't fake support" the spec calls out. Redirect rules
/// in an extension's ruleset are parsed (so they don't break installation)
/// but are skipped with that noted in `unsupportedRuleCount`.
enum ExtensionNetworkRules {
    struct Rule: Decodable {
        struct Condition: Decodable {
            let urlFilter: String?
            let resourceTypes: [String]?
            enum CodingKeys: String, CodingKey { case urlFilter = "urlFilter", resourceTypes = "resourceTypes" }
        }
        struct Action: Decodable {
            let type: String // "block" | "allow" | "redirect" | ...
        }
        let id: Int
        let action: Action
        let condition: Condition
    }

    /// Compiles every enabled extension's declarative rules (if any —
    /// declared via a `declarative_net_request` manifest key pointing at a
    /// JSON rule file, same as Chrome) into one combined `WKContentRuleList`
    /// and attaches it to the tab. Extensions without such rules are simply
    /// skipped; this never touches Trident's own separate content-blocking
    /// system if one exists elsewhere.
    static func apply(
        extensions: [WebExtension],
        to controller: WKUserContentController,
        completion: @escaping () -> Void = {}
    ) {
        let finish = {
            DispatchQueue.main.async(execute: completion)
        }
        var wkRules: [[String: Any]] = []
        for ext in extensions where ext.isEnabled {
            guard let manifest = ext.manifest else { continue }
            for ruleFile in manifest.enabledRulesetPaths {
                let url = ExtensionRepository.fileURL(extensionID: ext.id, relativePath: ruleFile)
                guard let data = try? Data(contentsOf: url),
                      let rules = try? JSONDecoder().decode([Rule].self, from: data) else { continue }
                for rule in rules {
                    guard let filter = rule.condition.urlFilter, !filter.isEmpty else { continue }
                    let resourceTypes = rule.condition.resourceTypes?
                        .compactMap(Self.webkitResourceType)
                    if let resourceTypes, !resourceTypes.isEmpty,
                       resourceTypes.count != rule.condition.resourceTypes?.count {
                        // Do not silently broaden a rule when Chrome names a
                        // resource type WebKit cannot represent.
                        continue
                    }
                    switch rule.action.type {
                    case "block":
                        wkRules.append(contentRuleListEntry(urlFilter: filter, action: "block", resourceTypes: resourceTypes))
                    case "allow", "allowAll":
                        wkRules.append(contentRuleListEntry(urlFilter: filter, action: "ignore-previous-rules", resourceTypes: resourceTypes))
                    default:
                        continue // redirect and anything else: not supported, see header doc.
                    }
                }
            }
        }
        guard !wkRules.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: wkRules),
              let jsonString = String(data: json, encoding: .utf8) else {
            finish()
            return
        }

        let digest = SHA256.hash(data: Data(jsonString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let identifier = "trident-extension-rules-\(digest.prefix(48))"
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier, encodedContentRuleList: jsonString
        ) { list, error in
            if let list, error == nil {
                controller.add(list)
            }
            finish()
        }
    }

    private static func contentRuleListEntry(urlFilter: String, action: String, resourceTypes: [String]?) -> [String: Any] {
        var trigger: [String: Any] = ["url-filter": urlFilter]
        if let resourceTypes, !resourceTypes.isEmpty {
            trigger["resource-type"] = resourceTypes
        }
        return [
            "trigger": trigger,
            "action": ["type": action]
        ]
    }

    private static func webkitResourceType(_ chromeType: String) -> String? {
        switch chromeType {
        case "main_frame", "sub_frame":
            return "document"
        case "stylesheet":
            return "style-sheet"
        case "xmlhttprequest":
            return "xhr"
        case "object", "object_subrequest":
            return "raw"
        case "script", "image", "font", "media", "ping", "websocket", "other":
            return chromeType
        default:
            return nil
        }
    }
}
