import SwiftUI

struct ContentView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var orientationIsPortrait = false

    /// The user's manual toggle is always the source of truth. "Auto-hide in
    /// portrait" additionally forces it closed on rotation (see onChange below),
    /// but never blocks the user from opening or closing it by hand.
    private var sidebarShouldShow: Bool {
        browser.isSidebarVisible
    }

    private var isHomeTab: Bool {
        browser.currentTab?.urlString == "trident://start"
    }

    var body: some View {
        GeometryReader { geo in
            // Reading `geo.size` here reflects the window's *current* bounds on
            // every layout pass — including iPad windowed/Split View/Stage
            // Manager resizes and rotations — so nothing below this line ever
            // works off a stale size.
            let isPortrait = geo.size.height > geo.size.width

            ZStack(alignment: .topTrailing) {
                AppBackgroundView()

                mainLayout(safeAreaInsets: geo.safeAreaInsets)

                if browser.isFullScreenActive {
                    Button {
                        browser.isFullScreenActive = false
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(GlassPanel(cornerRadius: 20) { Color.clear })
                    }
                    .buttonStyle(.plain)
                    .padding(.top, max(geo.safeAreaInsets.top, 14))
                    .padding(.trailing, 14)
                    .transition(.opacity)
                }

                if let toast = browser.toastMessage {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(GlassPanel(cornerRadius: 14) { Color.clear })
                            .padding(.bottom, 34)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                    .allowsHitTesting(false)
                }
            }
            // The ZStack (and therefore `geo`) now spans the *entire* window,
            // safe areas included. Full-screen mode can then truly go edge to
            // edge with no residual gap on the sides/bottom, and normalLayout
            // adds the safe-area padding back in by hand via `geo.safeAreaInsets`
            // so content still avoids the notch / home indicator / rounded corners.
            .ignoresSafeArea()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: browser.toastMessage)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: browser.isFullScreenActive)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: browser.isSidebarVisible)
            .onAppear {
                orientationIsPortrait = isPortrait
                updateMaxSidebarWidth(for: geo.size)
            }
            .onChange(of: isPortrait) { _, newValue in
                orientationIsPortrait = newValue
                if newValue && settings.sidebarAutoHide {
                    browser.isSidebarVisible = false
                }
            }
            .onChange(of: geo.size) { _, newSize in
                // Keeps the sidebar (and therefore the whole layout) from ever
                // overflowing a narrower window — recalculated live so resizing
                // the app in iPad Split View / Slide Over / Stage Manager just works.
                updateMaxSidebarWidth(for: newSize)
            }
        }
        .preferredColorScheme(settings.colorSchemePreference.colorScheme)
        .tint(settings.accentColor)
    }

    private func updateMaxSidebarWidth(for size: CGSize) {
        browser.maxAllowedSidebarWidth = max(220, size.width - 160)
    }

    // MARK: - Layout
    //
    // `normalLayout` and `fullScreenContent` used to be two entirely separate
    // view builders, each with its own call to `webContentArea` — so toggling
    // full screen swapped the whole subtree, which meant the `WKWebView`
    // hosted inside `BrowserWebView` got torn out of one UIKit view hierarchy
    // and reinserted into a different one. That's fine for a webview sitting
    // idle, but if a page's own HTML5 video was in native fullscreen at that
    // exact moment (see `isElementFullscreenEnabled` in WebViewController),
    // WebKit's own fullscreen presentation gets orphaned mid-transition and
    // the app crashes. `webContentArea` now has exactly one call site that
    // stays mounted the whole time; entering/leaving full screen only
    // toggles which chrome is drawn *around* it and collapses the padding —
    // it never removes or recreates the web view itself.

    @ViewBuilder
    private func mainLayout(safeAreaInsets: EdgeInsets) -> some View {
        let showsChrome = !browser.isFullScreenActive

        HStack(spacing: 0) {
            if sidebarShouldShow && showsChrome {
                // Top/bottom padding here must match the web content column's
                // own top/bottom padding below exactly, or the two panels'
                // edges don't line up — that's what made the sidebar look
                // "floating" out of alignment with the page next to it. Both
                // now use the same `max(inset, safeArea)` formula per edge
                // (previously this used `.padding(.vertical:)` with a
                // halved top safe-area inset, which matched neither edge).
                // Flush to the leading/top/bottom edges — only the true safe
                // area (notch, home indicator, rounded display corners) ever
                // adds a gap here now. `settings.sidebarVerticalInset`
                // remains available as an explicit user-controlled "shrink
                // the sidebar" slider, but it's no longer treated as an
                // artificial minimum margin when it's 0.
                SidebarView()
                    .padding(.leading, safeAreaInsets.leading)
                    .padding(.top, safeAreaInsets.top + settings.sidebarVerticalInset)
                    .padding(.bottom, safeAreaInsets.bottom + settings.sidebarVerticalInset)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                SidebarResizeHandle()
            }

            VStack(spacing: 6) {
                if !sidebarShouldShow && showsChrome {
                    CompactTabStripView(showsSidebarToggle: !isHomeTab)
                }

                if browser.isPrivateModeActive && showsChrome {
                    PrivateBrowsingBanner()
                }

                webContentArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, !showsChrome ? 0 : (sidebarShouldShow ? 0 : safeAreaInsets.leading))
            .padding(.trailing, !showsChrome ? 0 : safeAreaInsets.trailing)
            .padding(.top, !showsChrome ? 0 : safeAreaInsets.top)
            .padding(.bottom, !showsChrome ? 0 : safeAreaInsets.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var webContentArea: some View {
        // Rounded corners look right in the normal windowed layout, but in
        // full-screen mode they read as leftover empty triangles of
        // background peeking through at the edges/corners — full screen
        // should be a true edge-to-edge rectangle, so the radius drops to 0
        // there instead of staying a fixed 20.
        let cornerRadius: CGFloat = browser.isFullScreenActive ? 0 : 20

        if let tab = browser.currentTab {
            if tab.urlString == "trident://start" {
                StartPageView()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .background(GlassPanel(cornerRadius: cornerRadius, tintOpacity: 0.35) { Color.clear })
            } else if let controller = browser.currentController {
                ZStack {
                    BrowserWebView(controller: controller)
                        .id(controller.id)
                    if let error = controller.loadError {
                        ErrorPageView(error: error) { controller.reload() }
                    }
                    if controller.isLoading {
                        VStack {
                            ProgressView(value: controller.estimatedProgress)
                                .tint(settings.accentColor)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A slim, draggable grip on the sidebar's trailing edge. Press and drag
/// horizontally to resize the sidebar; the width is clamped so it can never
/// crush the content area, even in a narrow multitasking window.
private struct SidebarResizeHandle: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    @State private var dragStartWidth: Double?
    @State private var isDragging = false

    var body: some View {
        // The old handle was a 44pt-tall capsule vertically centered in a
        // (usually much taller) sidebar, so most of the edge wasn't
        // draggable at all. This version makes the *entire* height of the
        // sidebar edge grabbable — the capsule is still what's drawn, but the
        // hit area behind it spans top to bottom.
        ZStack {
            Capsule()
                .fill(Color.white.opacity(isDragging ? 0.3 : 0.14))
                .frame(width: 3, height: 44)
        }
        .frame(width: 5)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    isDragging = true
                    if dragStartWidth == nil {
                        dragStartWidth = browser.sidebarDragWidth ?? settings.sidebarWidth
                    }
                    let base = dragStartWidth ?? settings.sidebarWidth
                    let proposed = base + value.translation.width
                    browser.sidebarDragWidth = min(max(proposed, 240), browser.maxAllowedSidebarWidth)
                }
                .onEnded { _ in
                    if let final = browser.sidebarDragWidth {
                        settings.sidebarWidth = final
                    }
                    browser.sidebarDragWidth = nil
                    dragStartWidth = nil
                    isDragging = false
                }
        )
    }
}

struct PrivateBrowsingBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "eyeglasses")
            Text("Private Browsing — history and cookies won't be saved for this tab.")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(GlassPanel(cornerRadius: 12, tintOpacity: 0.5) { Color.clear })
    }
}
