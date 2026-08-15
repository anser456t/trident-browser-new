import Foundation
@preconcurrency import WebKit

/// In-memory pub/sub for `chrome.runtime.sendMessage` / `onMessage` and
/// `chrome.tabs.sendMessage`. Deliberately process-local and non-persistent
/// — messaging is a live, in-session concept in the WebExtension model, not
/// something that needs to survive a relaunch.
final class ExtensionMessageBroker {
    static let shared = ExtensionMessageBroker()
    /// extensionID -> listeners, each given (message, senderContext)
    private var listeners: [String: [(Any, String) -> Void]] = [:]
    private let lock = NSLock()

    func addListener(extensionID: String, _ listener: @escaping (Any, String) -> Void) {
        lock.lock(); defer { lock.unlock() }
        listeners[extensionID, default: []].append(listener)
    }

    func send(extensionID: String, message: Any, from context: String) {
        lock.lock()
        let subs = listeners[extensionID] ?? []
        lock.unlock()
        for listener in subs { listener(message, context) }
    }
}

/// The single entry point every extension API call crosses through. Per the
/// spec's security requirement, every operation validates, in order:
/// extension ID -> extension is installed & enabled -> permission granted
/// -> (if host-scoped) current tab's URL matches a granted host pattern
/// -> the specific operation is one this bridge actually implements.
/// Nothing here executes native code the extension supplies — every branch
/// below is a fixed, native Swift operation; the extension only chooses
/// *which* fixed operation and *what data* to pass to it.
@MainActor
final class ExtensionAPIBridge: NSObject, WKScriptMessageHandler {
    nonisolated static let handlerName = "tridentExtensionBridge"

    weak var browser: BrowserViewModel?
    /// The tab this bridge instance is attached to, for `activeTab`-style
    /// checks and as the implicit target of tab-relative operations. Nil
    /// for a bridge attached to a dedicated popup/background web view,
    /// where there's no "current tab" — those operate purely through
    /// `chrome.tabs.*` explicit tab IDs instead.
    weak var hostTab: WebViewController?
    /// Set for popup/background web views, which run their extension's own
    /// code directly in the page world of a dedicated `WKWebView` — there's
    /// no isolated-world lookup needed to resolve their promises.
    let fixedResolveWorld: WKContentWorld?

    nonisolated init(browser: BrowserViewModel?, hostTab: WebViewController?, fixedResolveWorld: WKContentWorld? = nil) {
        self.browser = browser
        self.hostTab = hostTab
        self.fixedResolveWorld = fixedResolveWorld
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let requestId = body["requestId"] as? String,
              let extensionID = body["extensionID"] as? String,
              let api = body["api"] as? String,
              let method = body["method"] as? String else { return }
        let args = body["args"] as? [String: Any] ?? [:]

        guard let webView = message.webView else { return }
        let world = fixedResolveWorld ?? .world(name: "trident-extension-\(extensionID)")

        handle(extensionID: extensionID, api: api, method: method, args: args) { [weak self] result in
            self?.resolve(requestId: requestId, result: result, in: webView, world: world)
        }
    }

    private func resolve(requestId: String, result: Result<Any, ExtensionBridgeError>, in webView: WKWebView, world: WKContentWorld) {
        let payload: [String: Any]
        switch result {
        case .success(let value):
            payload = ["requestId": requestId, "ok": true, "value": value]
        case .failure(let error):
            payload = ["requestId": requestId, "ok": false, "error": error.errorDescription ?? "Unknown error"]
        }
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: json, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            webView.evaluateJavaScript("window.__tridentResolve && window.__tridentResolve(\(jsonString));", in: nil, in: world) { _ in }
        }
    }

    // MARK: - Validation + dispatch

    private func handle(extensionID: String, api: String, method: String, args: [String: Any],
                         completion: @escaping (Result<Any, ExtensionBridgeError>) -> Void) {
        guard let ext = ExtensionManager.shared.extensions.first(where: { $0.id == extensionID }) else {
            return completion(.failure(.unknownExtension))
        }
        guard ext.isEnabled else { return completion(.failure(.disabled)) }

        func requirePermission(_ permission: ExtensionPermission) -> Bool {
            ext.grantedPermissions.contains(permission.rawValue)
        }
        func currentTabHostAllowed() -> Bool {
            guard let urlString = hostTab?.currentURLString, let url = URL(string: urlString) else { return false }
            return ExtensionMatchPattern.matches(url: url, anyOf: ext.grantedHostPermissions)
                || (ext.manifest?.contentScripts.contains { ExtensionMatchPattern.matches(url: url, anyOf: $0.matches) } ?? false)
        }

        switch (api, method) {
        case ("runtime", "getURL"):
            let path = args["path"] as? String ?? ""
            completion(.success("trident-extension://\(extensionID)/\(path)"))

        case ("runtime", "sendMessage"):
            ExtensionMessageBroker.shared.send(extensionID: extensionID, message: args["message"] ?? [:], from: "runtime")
            completion(.success([:]))

        case ("storage", "get"):
            guard requirePermission(.storage) else { return completion(.failure(.permissionDenied("storage"))) }
            let storage = ExtensionStorageRegistry.shared.storage(for: extensionID, directory: ExtensionRepository.directory(for: extensionID))
            let keys = args["keys"] as? [String]
            completion(.success(storage.get(keys)))

        case ("storage", "set"):
            guard requirePermission(.storage) else { return completion(.failure(.permissionDenied("storage"))) }
            let storage = ExtensionStorageRegistry.shared.storage(for: extensionID, directory: ExtensionRepository.directory(for: extensionID))
            let items = args["items"] as? [String: Any] ?? [:]
            if storage.estimatedByteCount > ExtensionLocalStorage.quotaBytes {
                return completion(.failure(.quotaExceeded))
            }
            storage.set(items)
            completion(.success([:]))

        case ("storage", "remove"):
            guard requirePermission(.storage) else { return completion(.failure(.permissionDenied("storage"))) }
            let storage = ExtensionStorageRegistry.shared.storage(for: extensionID, directory: ExtensionRepository.directory(for: extensionID))
            storage.remove(args["keys"] as? [String] ?? [])
            completion(.success([:]))

        case ("storage", "clear"):
            guard requirePermission(.storage) else { return completion(.failure(.permissionDenied("storage"))) }
            ExtensionStorageRegistry.shared.storage(for: extensionID, directory: ExtensionRepository.directory(for: extensionID)).clear()
            completion(.success([:]))

        case ("tabs", "query"):
            guard requirePermission(.tabs) else { return completion(.failure(.permissionDenied("tabs"))) }
            guard let browser else { return completion(.success([])) }
            let results = browser.tabs.filter { !$0.isPrivate }.map { Self.tabDictionary($0, browser: browser) }
            completion(.success(results))

        case ("tabs", "get"):
            guard requirePermission(.tabs) else { return completion(.failure(.permissionDenied("tabs"))) }
            guard let browser, let idString = args["tabId"] as? String, let uuid = UUID(uuidString: idString),
                  let tab = browser.tabs.first(where: { $0.id == uuid }) else { return completion(.failure(.notFound)) }
            completion(.success(Self.tabDictionary(tab, browser: browser)))

        case ("tabs", "create"):
            guard requirePermission(.tabs) else { return completion(.failure(.permissionDenied("tabs"))) }
            guard let browser else { return completion(.failure(.notFound)) }
            let urlString = args["url"] as? String ?? "trident://start"
            let tab = browser.createTab(urlString: urlString)
            completion(.success(Self.tabDictionary(tab, browser: browser)))

        case ("tabs", "update"):
            guard requirePermission(.tabs) else { return completion(.failure(.permissionDenied("tabs"))) }
            guard let browser, let idString = args["tabId"] as? String, let uuid = UUID(uuidString: idString),
                  let tab = browser.tabs.first(where: { $0.id == uuid }) else { return completion(.failure(.notFound)) }
            if let urlString = args["url"] as? String { tab.urlString = urlString; browser.activateWebController(for: tab.id); browser.webControllers[tab.id]?.load(urlString: urlString) }
            completion(.success(Self.tabDictionary(tab, browser: browser)))

        case ("tabs", "remove"):
            guard requirePermission(.tabs) else { return completion(.failure(.permissionDenied("tabs"))) }
            guard let browser, let idString = args["tabId"] as? String, let uuid = UUID(uuidString: idString),
                  let tab = browser.tabs.first(where: { $0.id == uuid }) else { return completion(.failure(.notFound)) }
            browser.closeTab(tab)
            completion(.success([:]))

        case ("tabs", "sendMessage"):
            guard requirePermission(.tabs) else { return completion(.failure(.permissionDenied("tabs"))) }
            ExtensionMessageBroker.shared.send(extensionID: extensionID, message: args["message"] ?? [:], from: "tabs")
            completion(.success([:]))

        case ("scripting", "executeScript"), ("scripting", "insertCSS"):
            guard requirePermission(.scripting) else { return completion(.failure(.permissionDenied("scripting"))) }
            guard currentTabHostAllowed() else { return completion(.failure(.hostNotPermitted)) }
            guard let webView = hostTab?.webView else { return completion(.failure(.notFound)) }
            if method == "executeScript", let code = args["code"] as? String {
                webView.evaluateJavaScript(code, in: nil, in: .world(name: "trident-extension-\(extensionID)")) { result in
                    switch result {
                    case .success(let value): completion(.success(String(describing: value)))
                    case .failure(let error): completion(.failure(.executionFailed(error.localizedDescription)))
                    }
                }
            } else if method == "insertCSS", let css = args["css"] as? String {
                let escaped = css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
                let js = "var __s = document.createElement('style'); __s.textContent = `\(escaped)`; document.documentElement.appendChild(__s);"
                webView.evaluateJavaScript(js, in: nil, in: .world(name: "trident-extension-\(extensionID)")) { result in
                    switch result {
                    case .success: completion(.success([:]))
                    case .failure(let error): completion(.failure(.executionFailed(error.localizedDescription)))
                    }
                }
            } else {
                completion(.failure(.invalidArguments))
            }

        default:
            completion(.failure(.unsupportedOperation("\(api).\(method)")))
        }
    }

    private static func tabDictionary(_ tab: BrowserTab, browser: BrowserViewModel) -> [String: Any] {
        [
            "id": tab.id.uuidString,
            "url": tab.urlString,
            "title": tab.title,
            "active": tab.id == browser.currentTabID,
            "pinned": tab.isPinned
        ]
    }

    // MARK: - JS shim

    /// Injected into every content-script / popup / background context.
    /// Every call funnels through `postMessage` to this bridge and returns
    /// a Promise resolved from native code — there is no synchronous path
    /// and no way for extension JS to reach anything not listed here.
    nonisolated static func shimScript(extensionID: String) -> String {
        """
        (function() {
          if (window.chrome && window.chrome.__tridentInstalled) { return; }
          var EXT_ID = "\(extensionID)";
          var pending = {};
          window.__tridentResolve = window.__tridentResolve || function(payload) {
            var entry = pending[payload.requestId];
            if (!entry) return;
            delete pending[payload.requestId];
            if (payload.ok) entry.resolve(payload.value); else entry.reject(new Error(payload.error));
          };
          function call(api, method, args) {
            return new Promise(function(resolve, reject) {
              var requestId = EXT_ID + '-' + Math.random().toString(36).slice(2);
              pending[requestId] = { resolve: resolve, reject: reject };
              window.webkit.messageHandlers.\(handlerName).postMessage({
                requestId: requestId, extensionID: EXT_ID, api: api, method: method, args: args || {}
              });
            });
          }
          var messageListeners = [];
          window.chrome = window.chrome || {};
          window.chrome.__tridentInstalled = true;
          window.chrome.runtime = {
            id: EXT_ID,
            getURL: function(path) { return 'trident-extension://' + EXT_ID + '/' + path; },
            sendMessage: function(message) { return call('runtime', 'sendMessage', { message: message }); },
            onMessage: {
              addListener: function(fn) { messageListeners.push(fn); }
            }
          };
          window.chrome.storage = {
            local: {
              get: function(keys) { return call('storage', 'get', { keys: Array.isArray(keys) ? keys : (keys ? [keys] : null) }); },
              set: function(items) { return call('storage', 'set', { items: items }); },
              remove: function(keys) { return call('storage', 'remove', { keys: Array.isArray(keys) ? keys : [keys] }); },
              clear: function() { return call('storage', 'clear', {}); }
            }
          };
          window.chrome.tabs = {
            query: function(info) { return call('tabs', 'query', info || {}); },
            get: function(tabId) { return call('tabs', 'get', { tabId: tabId }); },
            create: function(props) { return call('tabs', 'create', props || {}); },
            update: function(tabId, props) { return call('tabs', 'update', Object.assign({ tabId: tabId }, props || {})); },
            remove: function(tabId) { return call('tabs', 'remove', { tabId: tabId }); },
            sendMessage: function(tabId, message) { return call('tabs', 'sendMessage', { tabId: tabId, message: message }); }
          };
          window.chrome.scripting = {
            executeScript: function(injection) { return call('scripting', 'executeScript', { code: injection && injection.func ? '(' + injection.func.toString() + ')()' : (injection && injection.code) }); },
            insertCSS: function(injection) { return call('scripting', 'insertCSS', { css: injection && injection.css }); }
          };
          window.chrome.action = {
            setBadgeText: function() { return Promise.resolve(); },
            setTitle: function() { return Promise.resolve(); },
            setIcon: function() { return Promise.resolve(); }
          };
        })();
        """
    }
}

enum ExtensionBridgeError: LocalizedError {
    case unknownExtension
    case disabled
    case permissionDenied(String)
    case hostNotPermitted
    case notFound
    case quotaExceeded
    case invalidArguments
    case executionFailed(String)
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .unknownExtension: return "Unknown extension."
        case .disabled: return "Extension is disabled."
        case .permissionDenied(let p): return "Extension does not have the \"\(p)\" permission."
        case .hostNotPermitted: return "Extension does not have permission for this site."
        case .notFound: return "Not found."
        case .quotaExceeded: return "Storage quota exceeded."
        case .invalidArguments: return "Invalid arguments."
        case .executionFailed(let m): return m
        case .unsupportedOperation(let op): return "\(op) is not supported."
        }
    }
}
