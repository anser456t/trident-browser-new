import SwiftUI
@preconcurrency import WebKit

/// Presents an extension's `action.default_popup` page. Popups get the same
/// `chrome.*` bridge as content scripts (storage, tabs, scripting, runtime),
/// resolved through the extension's own dedicated `WKWebView` rather than an
/// isolated content world, since a popup is a standalone page, not code
/// sharing a tab with an untrusted website.
struct ExtensionPopupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var browser: BrowserViewModel
    let extensionID: String

    private var ext: WebExtension? { ExtensionManager.shared.extensions.first { $0.id == extensionID } }

    var body: some View {
        NavigationStack {
            Group {
                if let ext, let popupPath = ext.manifest?.action?.defaultPopup {
                    ExtensionPopupWebView(extensionID: ext.id, popupPath: popupPath, browser: browser)
                } else {
                    Text("This extension doesn't have a popup.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle(ext?.manifest?.action?.defaultTitle ?? ext?.name ?? "Extension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ExtensionPopupWebView: UIViewRepresentable {
    let extensionID: String
    let popupPath: String
    let browser: BrowserViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let bridge = ExtensionAPIBridge(browser: browser, hostTab: nil, fixedResolveWorld: .page)
        config.userContentController.add(bridge, name: ExtensionAPIBridge.handlerName)
        context.coordinator.bridge = bridge // also keep our own strong ref for symmetry with the tab case

        let shim = ExtensionAPIBridge.shimScript(extensionID: extensionID)
        config.userContentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: config)
        let fileURL = ExtensionRepository.fileURL(extensionID: extensionID, relativePath: popupPath)
        webView.loadFileURL(fileURL, allowingReadAccessTo: ExtensionRepository.directory(for: extensionID))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var bridge: ExtensionAPIBridge?
    }
}
