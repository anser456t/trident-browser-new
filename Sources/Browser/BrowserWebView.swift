import SwiftUI
import UIKit
import WebKit

/// SwiftUI bridge to a pre-existing `WKWebView` owned by `WebViewController`.
/// We never create the WKWebView here — that stays with the controller so
/// navigation state survives SwiftUI view identity churn (tab switches, etc).
struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var controller: WebViewController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op: state changes flow through `controller`'s published properties.
    }
}
