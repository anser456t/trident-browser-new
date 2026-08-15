import Foundation
@preconcurrency import WebKit

/// Turns each enabled extension's `content_scripts` entries into `WKUserScript`s,
/// wired into a tab's `WKWebViewConfiguration` the same way `UserScriptPlugin`
/// already is (see `WebViewController.makeConfiguration`) — match-pattern
/// checking happens in JS at document-load time rather than natively ahead of
/// time, because a `WKWebViewConfiguration` is fixed before any page has
/// loaded, so there's no page URL to check against yet. This mirrors exactly
/// how the existing user-script hostname guard already works; it's not a new
/// pattern, just a more precise (Chrome-style) match check.
///
/// Each extension's script runs in its own `WKContentWorld` — never `.page`
/// — so it can't read or clobber the page's own JavaScript, and can't see
/// (or be seen by) another extension's content script. This is the same
/// isolation model Chrome's own "isolated world" content scripts use.
enum ExtensionContentScriptInjector {
    /// A single shared helper, injected once per configuration into the
    /// page world only implicitly via each isolated world's own copy — kept
    /// tiny and dependency-free since it has to be re-embedded per pattern
    /// check rather than loaded as a module.
    private static let matchPatternJS = """
    function __tridentMatches(url, patterns) {
      function hostMatch(p, h) {
        if (p === '*') return true;
        if (p.indexOf('*.') === 0) {
          var suf = p.slice(2);
          return h === suf || h.slice(-(suf.length + 1)) === ('.' + suf);
        }
        return p === h;
      }
      function pathMatch(p, path) {
        var re = '^' + p.replace(/[.+?^${}()|[\\]\\\\]/g, '\\\\$&').replace(/\\*/g, '.*') + '$';
        try { return new RegExp(re).test(path); } catch (e) { return false; }
      }
      try {
        var u = new URL(url);
        for (var i = 0; i < patterns.length; i++) {
          var pat = patterns[i];
          if (pat === '<all_urls>') { if (u.protocol === 'http:' || u.protocol === 'https:') return true; continue; }
          var m = pat.match(/^(\\*|http|https):\\/\\/([^\\/]+)(\\/.*)$/);
          if (!m) continue;
          var scheme = m[1], host = m[2], path = m[3];
          var schemeOK = scheme === '*' ? (u.protocol === 'http:' || u.protocol === 'https:') : (u.protocol === scheme + ':');
          if (!schemeOK) continue;
          if (!hostMatch(host.toLowerCase(), u.hostname.toLowerCase())) continue;
          if (!pathMatch(path, u.pathname || '/')) continue;
          return true;
        }
      } catch (e) {}
      return false;
    }
    """

    static func userScripts(for extensions: [WebExtension]) -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        for ext in extensions where ext.isEnabled {
            guard let manifest = ext.manifest else { continue }
            let world = WKContentWorld.world(name: "trident-extension-\(ext.id)")

            for contentScript in manifest.contentScripts {
                let patternsJSON = (try? JSONSerialization.data(withJSONObject: contentScript.matches))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

                var body = ""
                for cssPath in contentScript.css {
                    guard let cssData = try? Data(contentsOf: ExtensionRepository.fileURL(extensionID: ext.id, relativePath: cssPath)),
                          let css = String(data: cssData, encoding: .utf8) else { continue }
                    let escaped = css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
                    body += "var __s = document.createElement('style'); __s.textContent = `\(escaped)`; document.documentElement.appendChild(__s);\n"
                }
                var jsBody = ""
                for jsPath in contentScript.js {
                    guard let jsData = try? Data(contentsOf: ExtensionRepository.fileURL(extensionID: ext.id, relativePath: jsPath)),
                          let js = String(data: jsData, encoding: .utf8) else { continue }
                    jsBody += js + "\n"
                }
                let apiShim = ExtensionAPIBridge.shimScript(extensionID: ext.id)

                let source = """
                (function() {
                  \(matchPatternJS)
                  if (!__tridentMatches(window.location.href, \(patternsJSON))) { return; }
                  try {
                    \(apiShim)
                    \(body)
                    \(jsBody)
                  } catch (e) { console.error('Trident extension "\(ext.name)" error:', e); }
                })();
                """

                let injectionTime: WKUserScriptInjectionTime =
                    contentScript.runAt == .documentStart ? .atDocumentStart : .atDocumentEnd
                scripts.append(WKUserScript(
                    source: source, injectionTime: injectionTime,
                    forMainFrameOnly: false, in: world
                ))
            }
        }
        return scripts
    }
}
