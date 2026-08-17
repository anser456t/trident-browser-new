import Foundation
@preconcurrency import WebKit
import Combine
import SwiftUI

/// Owns a single `WKWebView` instance for one tab and publishes its live state
/// (title, URL, loading progress, back/forward availability) to SwiftUI.
final class WebViewController: NSObject, ObservableObject, Identifiable {
    let id: UUID
    let webView: WKWebView

    @Published var title: String = "New Tab"
    @Published var currentURLString: String = ""
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var loadError: BrowserLoadError?
    @Published var host: String = ""
    /// Whether this tab currently has audio (or video) playing. Backed by
    /// WebKit's private `_isPlayingAudio` KVO key — there's no public API
    /// for this. Every WKWebView-based third-party browser that shows a
    /// "tab is making noise" indicator uses this same key; it's been stable
    /// across iOS releases for years. Since Trident is sideloaded rather
    /// than App Store-distributed, using an underscored key here isn't a
    /// review risk — worst case on a future OS the KVO simply never fires
    /// and the indicator stays off, it can't crash.
    @Published var isPlayingAudio: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var pendingDownloads: [ObjectIdentifier: UUID] = [:]
    private var isObservingAudioKVO = false

    var onCreateNewTab: ((URL) -> Void)?
    /// Called when the user picks "Open in New Tab" from a long-pressed link
    /// — unlike `onCreateNewTab` (used for `window.open`/target=_blank, which
    /// switches to the new tab immediately since the site expects that),
    /// this opens the tab in the background so the user stays on the page
    /// they long-pressed from, matching Safari/Arc's long-press-link behavior.
    var onOpenLinkInNewTab: ((URL) -> Void)?
    /// Called the moment a download is handed off to WKDownload, so the UI can show a toast.
    var onDownloadWillStart: (() -> Void)?

    static func makeConfiguration(isPrivate: Bool, javaScriptEnabled: Bool, userScripts: [UserScriptPlugin], extensions: [WebExtension] = [], browser: BrowserViewModel? = nil) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = javaScriptEnabled
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Let video (e.g. 4K streams) play picture-in-picture and go fullscreen —
        // WKWebView otherwise already streams whatever resolution a site serves;
        // there's no separate "quality" switch to flip on our side.
        config.allowsPictureInPictureMediaPlayback = true
        // Without this, sites that request the HTML5 Fullscreen API on a
        // <video> (or any element — YouTube's own player included) get told
        // fullscreen isn't supported, because WKWebView doesn't honor
        // `element.requestFullscreen()` until this is turned on explicitly.
        config.preferences.isElementFullscreenEnabled = true

        for script in userScripts where script.isEnabled && !script.code.isEmpty {
            let escapedPattern = script.matchPattern
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let guarded = """
            (function() {
              try {
                var pattern = "\(escapedPattern)";
                if (pattern === "*" || pattern.length === 0 || window.location.hostname.indexOf(pattern) !== -1) {
                  \(script.code)
                }
              } catch (e) { console.error("Trident userscript error:", e); }
            })();
            """
            let wkScript = WKUserScript(source: guarded, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            config.userContentController.addUserScript(wkScript)
        }

        // Extensions are never private-mode-eligible in this pass — running
        // third-party content scripts inside a Private tab, where the whole
        // point is minimizing what can observe browsing, is a deliberate
        // scope cut, not an oversight.
        if !isPrivate && !extensions.isEmpty {
            for wkScript in ExtensionContentScriptInjector.userScripts(for: extensions) {
                config.userContentController.addUserScript(wkScript)
            }
        }

        return config
    }

    private var extensionBridge: ExtensionAPIBridge?

    init(id: UUID, isPrivate: Bool, useDesktopMode: Bool, javaScriptEnabled: Bool, userScripts: [UserScriptPlugin] = [], extensions: [WebExtension] = [], browser: BrowserViewModel? = nil) {
        self.id = id
        let config = WebViewController.makeConfiguration(isPrivate: isPrivate, javaScriptEnabled: javaScriptEnabled, userScripts: userScripts, extensions: extensions, browser: browser)
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        if !isPrivate && !extensions.isEmpty {
            let bridge = ExtensionAPIBridge(browser: browser, hostTab: self)
            config.userContentController.add(bridge, name: ExtensionAPIBridge.handlerName)
            extensionBridge = bridge
            ExtensionNetworkRules.apply(extensions: extensions, to: config.userContentController)
        }

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // WKWebView's internal scroll view otherwise auto-insets its content
        // for the window's safe area (home indicator, notch) regardless of
        // what SwiftUI around it does — that's what leaves a strip of empty
        // space at the bottom even after the SwiftUI layer goes edge to edge
        // in full-screen mode. Disabling it hands that entirely to our own
        // `.ignoresSafeArea()` layout instead.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        applyDesktopMode(useDesktopMode)
        observe()
    }

    private func observe() {
        webView.publisher(for: \.title).sink { [weak self] newTitle in
            self?.title = (newTitle?.isEmpty == false) ? (newTitle ?? "New Tab") : "New Tab"
        }.store(in: &cancellables)

        webView.publisher(for: \.url).sink { [weak self] url in
            guard let self, let url else { return }
            self.currentURLString = url.absoluteString
            self.host = url.host ?? ""
        }.store(in: &cancellables)

        webView.publisher(for: \.isLoading).sink { [weak self] loading in
            self?.isLoading = loading
        }.store(in: &cancellables)

        webView.publisher(for: \.estimatedProgress).sink { [weak self] progress in
            self?.estimatedProgress = progress
        }.store(in: &cancellables)

        webView.publisher(for: \.canGoBack).sink { [weak self] value in
            self?.canGoBack = value
        }.store(in: &cancellables)

        webView.publisher(for: \.canGoForward).sink { [weak self] value in
            self?.canGoForward = value
        }.store(in: &cancellables)

        // `WKWebView` has no public property for "is this page making
        // sound right now" — this KVO key is the standard workaround (see
        // the doc comment on `isPlayingAudio`). Guarded with `respondsTo`
        // so it's a silent no-op rather than a crash if a future WebKit
        // ever removes the key.
        if webView.responds(to: NSSelectorFromString("_isPlayingAudio")) {
            webView.addObserver(self, forKeyPath: "_isPlayingAudio", options: [.new, .initial], context: nil)
            isObservingAudioKVO = true
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "_isPlayingAudio" else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        let playing = (change?[.newKey] as? NSNumber)?.boolValue ?? false
        DispatchQueue.main.async { [weak self] in
            self?.isPlayingAudio = playing
        }
    }

    deinit {
        if isObservingAudioKVO {
            webView.removeObserver(self, forKeyPath: "_isPlayingAudio")
        }
    }

    func applyDesktopMode(_ desktop: Bool) {
        if desktop {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        } else {
            webView.customUserAgent = nil
        }
    }

    func load(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        loadError = nil
        webView.load(URLRequest(url: url))
    }

    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func setZoom(_ scale: Double) {
        webView.pageZoom = CGFloat(scale)
    }

    func findOnPage(_ text: String) {
        guard #available(iOS 16.0, *) else { return }
        let config = WKFindConfiguration()
        webView.find(text, configuration: config, completionHandler: { _ in })
    }
}

struct BrowserLoadError: Identifiable {
    enum Kind { case offline, dns, ssl, generic }
    let id = UUID()
    let kind: Kind
    let message: String
    let failingURL: URL?
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        setError(from: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        setError(from: error)
    }

    private func setError(from error: Error) {
        let nsError = error as NSError
        // Cancelled loads (e.g. user navigated away, or a download hand-off) are not real errors.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }

        let kind: BrowserLoadError.Kind
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut:
            kind = .offline
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            kind = .dns
        case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid:
            kind = .ssl
        default:
            kind = .generic
        }
        loadError = BrowserLoadError(kind: kind, message: nsError.localizedDescription, failingURL: webView.url)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Open target="_blank" links that create a new window in a new tab instead of failing silently.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            onCreateNewTab?(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Anything the web view can't render itself (e.g. a PDF the user wants to
        // save, a zip, an .ipa, etc.) is handed off to WKDownload instead of being
        // loaded in place — this is what fixes "frame load interrupted".
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        onDownloadWillStart?()
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        onDownloadWillStart?()
    }
}

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            onCreateNewTab?(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // Long-press on a link inside the page — shows "Open in New Tab" /
    // "Copy Link" / "Share" in the native context menu, same as Safari.
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo, completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let url = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }
        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let openInNewTab = UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                self?.onOpenLinkInNewTab?(url)
            }
            let copyLink = UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.url = url
            }
            let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                guard let scene = webView.window?.windowScene,
                      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                root.present(activityVC, animated: true)
            }
            return UIMenu(title: url.absoluteString, children: [openInNewTab, copyLink, share])
        }
        completionHandler(config)
    }
}

extension WebViewController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let destination = DownloadManager.downloadsDirectory.appendingPathComponent(suggestedFilename)
        try? FileManager.default.removeItem(at: destination)
        let item = DownloadManager.shared.registerDownload(
            fileName: suggestedFilename,
            sourceURLString: response.url?.absoluteString ?? "",
            localPath: destination.path
        )
        pendingDownloads[ObjectIdentifier(download)] = item.id

        download.progress.publisher(for: \.completedUnitCount)
            .combineLatest(download.progress.publisher(for: \.totalUnitCount))
            .receive(on: DispatchQueue.main)
            .sink { completed, total in
                DownloadManager.shared.updateProgress(id: item.id, bytesWritten: completed, totalBytes: total)
            }
            .store(in: &cancellables)

        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let itemID = pendingDownloads[ObjectIdentifier(download)] {
            DownloadManager.shared.markCompleted(id: itemID)
        }
        pendingDownloads[ObjectIdentifier(download)] = nil
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let itemID = pendingDownloads[ObjectIdentifier(download)] {
            DownloadManager.shared.markFailed(id: itemID)
        }
        pendingDownloads[ObjectIdentifier(download)] = nil
    }
}
