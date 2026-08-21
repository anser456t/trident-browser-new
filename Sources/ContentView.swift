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

                // In true full screen the web content area deliberately runs
                // edge-to-edge, including up under the status bar — which
                // meant the page showed straight through behind the
                // clock/battery/wifi icons. When the user hasn't opted to
                // hide the status bar outright (see `.statusBar(hidden:)`
                // below), this draws a solid strip behind just that icon row
                // instead, so nothing peeks through underneath them.
                if browser.isFullScreenActive && !settings.hideStatusBarInFullScreen && geo.safeAreaInsets.top > 0 {
                    Color.black.opacity(0.001)
                        .background(.ultraThinMaterial)
                        .frame(height: geo.safeAreaInsets.top)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                        .transition(.opacity)
                }

                // Normal browsing intentionally does NOT draw anything extra
                // behind the status bar anymore. It used to get its own
                // separate `.ultraThinMaterial` strip here — but that's a
                // completely different blur (UIKit's vibrancy material) from
                // `AppBackgroundView`'s own `.blur(radius:)`, which already
                // covers the whole screen including this area. Layering the
                // two produced a visible seam right at the status bar edge.
                // Status bar is left fully transparent so the one blurred
                // background is all that ever shows through, everywhere.

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
            .statusBar(hidden: browser.isFullScreenActive && settings.hideStatusBarInFullScreen)
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

        Group {
            if showsChrome {
                // Sidebar has NO card of its own now — its controls sit
                // directly on the blurred `AppBackgroundView`, exactly like
                // the red mockup: the sidebar region is just "background,
                // with sidebar stuff drawn on top of it", not a separate
                // panel. Only the web content gets a floating card (glass
                // background + border + shadow + rounded corners) — that's
                // the one piece meant to look like a window sitting above
                // the backdrop, drop shadow included.
                HStack(spacing: 0) {
                    if sidebarShouldShow {
                        SidebarView()
                            .frame(maxHeight: .infinity)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        SidebarResizeHandle()
                    }

                    contentColumn(showsChrome: true, roundCorners: sidebarShouldShow)
                }
                // With the sidebar hidden, the webpage is the primary
                // surface and should run all the way to the bottom edge.
                // Keeping the normal window margin here leaves a small,
                // distracting strip beneath WKWebView in landscape.
                .padding(.leading, safeAreaInsets.leading + settings.windowMargin)
                .padding(.trailing, safeAreaInsets.trailing + settings.windowMargin)
                .padding(.top, safeAreaInsets.top + settings.windowMargin)
                .padding(.bottom, safeAreaInsets.bottom + (sidebarShouldShow ? settings.windowMargin : 0))
            } else {
                // Full screen: no sidebar, no card, true edge-to-edge.
                contentColumn(showsChrome: false, roundCorners: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The right-hand column: compact tab strip / private banner / web
    /// content. In normal browsing this whole column is wrapped in a single
    /// floating `GlassPanel` — the "webpage card" from the mockup. In full
    /// screen it's plain, unwrapped content instead. `roundCorners` is
    /// separate from `showsChrome`: the card itself (margin/blur/tint/
    /// shadow) still shows whether or not the sidebar is open, but the
    /// corner-radius setting should only round it while the sidebar is
    /// actually showing next to it — with the sidebar hidden the card spans
    /// the full width and squared-off corners read as a normal window
    /// rather than a floating card, which is what looked wrong before.
    @ViewBuilder
    private func contentColumn(showsChrome: Bool, roundCorners: Bool) -> some View {
        let inner = VStack(spacing: 6) {
            if !sidebarShouldShow && showsChrome {
                CompactTabStripView(showsSidebarToggle: !isHomeTab)
            }

            if browser.isPrivateModeActive && showsChrome {
                PrivateBrowsingBanner()
            }

            webContentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if showsChrome {
            GlassPanel(
                cornerRadius: roundCorners ? settings.sidebarCornerRadius : 0,
                tintOpacity: settings.sidebarTransparency,
                blurAmount: settings.sidebarBlur
            ) {
                inner
            }
        } else {
            inner
        }
    }

    @ViewBuilder
    private var webContentArea: some View {
        // The merged window's own `GlassPanel` (see `mainLayout`) already
        // clips sidebar + content + divider together into one rounded
        // shape, so nothing in here needs its own corner radius or
        // background/border/shadow anymore — panes are just plain content.
        if let splitTabID = browser.splitTabID, let splitTab = browser.tab(withID: splitTabID), let primaryTab = browser.currentTab {
            GeometryReader { geo in
                let dividerWidth: CGFloat = 6
                let usable = geo.size.width - dividerWidth
                let leadingWidth = max(200, usable * browser.splitDividerFraction)

                HStack(spacing: 0) {
                    pane(for: primaryTab, controller: browser.currentController)
                        .frame(width: leadingWidth)

                    SplitDividerHandle(usableWidth: usable, fraction: $browser.splitDividerFraction)
                        .frame(width: dividerWidth)

                    pane(for: splitTab, controller: browser.webControllers[splitTabID])
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .topTrailing) {
                            Button { browser.closeSplit() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.black.opacity(0.35)))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .padding(8)
                        }
                }
            }
        } else {
            pane(for: browser.currentTab, controller: browser.currentController)
        }
    }

    /// Renders one tab's content: Start page, loading web view, or error
    /// page. Shared by both the normal single-pane layout and each side of
    /// Split View.
    @ViewBuilder
    private func pane(for tab: BrowserTab?, controller: WebViewController?) -> some View {
        if let tab {
            if tab.urlString == "trident://start" {
                StartPageView()
            } else if let controller {
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
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A slim, draggable grip on the sidebar's trailing edge. Press and drag
/// horizontally to resize the sidebar; the width is clamped so it can never
/// crush the content area, even in a narrow multitasking window.
private struct SplitDividerHandle: View {
    let usableWidth: CGFloat
    @Binding var fraction: Double
    @State private var isDragging = false
    @State private var dragStartFraction: Double?

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(isDragging ? 0.35 : 0.16))
                .frame(width: 3, height: 44)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartFraction == nil { dragStartFraction = fraction }
                    isDragging = true
                    guard usableWidth > 0, let start = dragStartFraction else { return }
                    let delta = value.translation.width / usableWidth
                    fraction = min(0.8, max(0.2, start + delta))
                }
                .onEnded { _ in
                    isDragging = false
                    dragStartFraction = nil
                }
        )
    }
}

private struct SidebarResizeHandle: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    @State private var dragStartWidth: Double?
    @State private var isDragging = false

    var body: some View {
        // Sits in the gap between the sidebar (no card of its own) and the
        // content card, so its width tracks `settings.windowMargin` — the
        // same value used for the outer margins — rather than a fixed size,
        // so the drag target roughly matches however wide that gap actually
        // is on screen.
        ZStack {
            Capsule()
                .fill(Color.white.opacity(isDragging ? 0.3 : 0.14))
                .frame(width: 3, height: 44)
        }
        .frame(width: max(10, settings.windowMargin))
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
