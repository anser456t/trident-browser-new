import Foundation
@preconcurrency import WebKit

/// Manages `background.js` execution for extensions that declare one.
///
/// ## The honest iOS limitation
/// A real Chrome MV3 service worker can be woken by the browser at any time
/// — including while the browser itself isn't running — to handle events
/// like alarms or push messages. That model has no iOS equivalent for a
/// third-party app extension system: WKWebView JavaScript (including
/// timers) is suspended the moment Trident is backgrounded, and there is no
/// API that lets an app run another app's arbitrary JS while suspended or
/// terminated. iOS background execution APIs (BGTaskScheduler, background
/// fetch, etc.) are for the *host app's own* code, gated by entitlements,
/// and are not a general "run this JS periodically" facility — bridging an
/// extension's `background.js` through them isn't something Apple's
/// platform allows either.
///
/// So: what this actually implements is a **foreground-only, lazily-loaded**
/// background page. It loads `background.js` in a hidden `WKWebView` the
/// first time something needs it (an event, a message, activation) while
/// Trident is in the foreground, keeps it alive while there's recent
/// activity, and unloads it after an idle timeout or when Trident
/// backgrounds. This covers the common real-world pattern of "background.js
/// mostly just relays messages between popup and content scripts while the
/// browser is open" — it does not cover alarms, push, or anything requiring
/// the extension to run while the app isn't.
@MainActor
final class ExtensionServiceWorkerManager {
    static let shared = ExtensionServiceWorkerManager()

    private final class Worker {
        let webView: WKWebView
        let bridge: ExtensionAPIBridge
        var lastActivity: Date = Date()
        init(webView: WKWebView, bridge: ExtensionAPIBridge) {
            self.webView = webView
            self.bridge = bridge
        }
    }

    private var workers: [String: Worker] = [:]
    private let idleTimeout: TimeInterval = 120

    /// Ensures `ext`'s background.js is loaded and returns whether it was
    /// (already running or just started). No-ops if the extension declares
    /// no background script or is disabled.
    @discardableResult
    func ensureLoaded(_ ext: WebExtension, browser: BrowserViewModel?) -> Bool {
        guard ext.isEnabled, let serviceWorkerPath = ext.manifest?.background?.serviceWorker else { return false }
        if let existing = workers[ext.id] {
            existing.lastActivity = Date()
            return true
        }
        let fileURL = ExtensionRepository.fileURL(extensionID: ext.id, relativePath: serviceWorkerPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        guard let scriptData = try? Data(contentsOf: fileURL), let script = String(data: scriptData, encoding: .utf8) else { return false }

        let config = WKWebViewConfiguration()
        let bridge = ExtensionAPIBridge(browser: browser, hostTab: nil, fixedResolveWorld: .page)
        config.userContentController.add(bridge, name: ExtensionAPIBridge.handlerName)
        let webView = WKWebView(frame: .zero, configuration: config)
        // Never attached to the view hierarchy — this is intentionally an
        // off-screen worker, not something the user ever sees.
        let shim = ExtensionAPIBridge.shimScript(extensionID: ext.id)
        let html = "<script>\(shim)\n\(script)</script>"
        webView.loadHTMLString(html, baseURL: URL(string: "trident-extension://\(ext.id)/"))

        workers[ext.id] = Worker(webView: webView, bridge: bridge)
        return true
    }

    func markActivity(extensionID: String) {
        workers[extensionID]?.lastActivity = Date()
    }

    func unload(extensionID: String) {
        workers.removeValue(forKey: extensionID)
    }

    /// Called from app-level scenePhase handling — there is no reliable
    /// reason to keep any of these alive once Trident itself is suspended.
    func unloadAll() {
        workers.removeAll()
    }

    /// Call periodically (e.g. from a lightweight foreground timer) to
    /// release workers nobody has talked to in a while.
    func sweepIdleWorkers() {
        let cutoff = Date().addingTimeInterval(-idleTimeout)
        for (id, worker) in workers where worker.lastActivity < cutoff {
            workers.removeValue(forKey: id)
        }
    }
}
