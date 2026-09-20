import Foundation

/// Decoded `manifest.json`. Every field beyond the required MV3 minimum
/// (`manifest_version`, `name`, `version`) is optional — real-world
/// extensions omit large parts of this, and a missing/unrecognized field
/// must never fail the whole parse.
struct ExtensionManifest: Decodable {
    struct Action: Decodable {
        let defaultPopup: String?
        let defaultTitle: String?
        let defaultIcon: [String: String]?

        enum CodingKeys: String, CodingKey {
            case defaultPopup = "default_popup"
            case defaultTitle = "default_title"
            case defaultIcon = "default_icon"
        }
    }

    struct ContentScript: Decodable {
        let matches: [String]
        let js: [String]
        let css: [String]
        let runAt: RunAt

        enum RunAt: String, Decodable {
            case documentStart = "document_start"
            case documentEnd = "document_end"
            case documentIdle = "document_idle"
        }

        enum CodingKeys: String, CodingKey {
            case matches, js, css
            case runAt = "run_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            matches = try c.decodeIfPresent([String].self, forKey: .matches) ?? []
            js = try c.decodeIfPresent([String].self, forKey: .js) ?? []
            css = try c.decodeIfPresent([String].self, forKey: .css) ?? []
            runAt = try c.decodeIfPresent(RunAt.self, forKey: .runAt) ?? .documentIdle
        }
    }

    struct Background: Decodable {
        let serviceWorker: String?
        enum CodingKeys: String, CodingKey { case serviceWorker = "service_worker" }
    }

    struct DeclarativeNetRequest: Decodable {
        struct RuleResource: Decodable {
            let id: String
            let enabled: Bool
            let path: String
        }
        let ruleResources: [RuleResource]
        enum CodingKeys: String, CodingKey { case ruleResources = "rule_resources" }
    }

    let manifestVersion: Int
    let name: String
    let version: String
    let description: String?
    let icons: [String: String]?
    let action: Action?
    let permissions: [String]
    let hostPermissions: [String]
    let contentScripts: [ContentScript]
    let background: Background?
    let optionsPage: String?
    let declarativeNetRequest: DeclarativeNetRequest?

    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case name, version, description, icons, action, permissions
        case hostPermissions = "host_permissions"
        case contentScripts = "content_scripts"
        case background
        case optionsPage = "options_page"
        case declarativeNetRequest = "declarative_net_request"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try c.decode(Int.self, forKey: .manifestVersion)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        icons = try c.decodeIfPresent([String: String].self, forKey: .icons)
        action = try c.decodeIfPresent(Action.self, forKey: .action)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        hostPermissions = try c.decodeIfPresent([String].self, forKey: .hostPermissions) ?? []
        contentScripts = try c.decodeIfPresent([ContentScript].self, forKey: .contentScripts) ?? []
        background = try c.decodeIfPresent(Background.self, forKey: .background)
        optionsPage = try c.decodeIfPresent(String.self, forKey: .optionsPage)
        declarativeNetRequest = try c.decodeIfPresent(DeclarativeNetRequest.self, forKey: .declarativeNetRequest)
    }

    /// Paths of every enabled ruleset, ready to hand to `ExtensionNetworkRules`.
    var enabledRulesetPaths: [String] {
        (declarativeNetRequest?.ruleResources ?? []).filter(\.enabled).map(\.path)
    }
}

enum ExtensionManifestError: LocalizedError {
    case notFound
    case invalidJSON(String)
    case unsupportedManifestVersion(Int)
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "manifest.json was not found."
        case .invalidJSON(let detail):
            return "manifest.json could not be parsed: \(detail)"
        case .unsupportedManifestVersion(let v):
            if v == 2 {
                return "Manifest V2 extensions are not currently supported.\nPlease use a Manifest V3 version of this extension."
            }
            return "This extension uses manifest_version \(v), which is not currently supported. Trident supports Manifest V3."
        case .missingRequiredField(let field):
            return "manifest.json is missing the required field \"\(field)\"."
        }
    }
}

enum ExtensionManifestParser {
    static func parse(data: Data) throws -> ExtensionManifest {
        // Decode manifest_version first, standalone, so we can give a
        // specific "MV2 not supported" message rather than a generic
        // decode failure when that's the actual, very common, case.
        struct VersionProbe: Decodable { let manifest_version: Int? }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
              let version = probe.manifest_version else {
            throw ExtensionManifestError.missingRequiredField("manifest_version")
        }
        guard version == 3 else {
            throw ExtensionManifestError.unsupportedManifestVersion(version)
        }

        do {
            return try JSONDecoder().decode(ExtensionManifest.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw ExtensionManifestError.missingRequiredField(key.stringValue)
        } catch {
            throw ExtensionManifestError.invalidJSON(error.localizedDescription)
        }
    }
}
