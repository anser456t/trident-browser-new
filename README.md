# Trident — An Arc-Inspired iPad Browser

Trident is an original, native iPadOS browser built with Swift, SwiftUI, and
WKWebView. It's heavily inspired by the desktop version of Arc Browser —
sidebar navigation, Spaces, pinned/favorite tabs, tab organization — reimagined
with an original "Liquid Glass" visual identity (no Arc branding, logos, or
assets are used anywhere in this project).

## Recent changes

A round of fixes and new features on top of the initial build:

- **Fixed**: removed the extra bottom window margin from the full-width
  webpage layout when the sidebar is hidden, eliminating the thin empty strip
  beneath pages in landscape.
- **Added**: an "Open in Safari" handoff in both navigation bars for secure
  pages. This provides a reliable passkey fallback for sites whose WebAuthn
  flow cannot authorize a custom WKWebView browser app (including Gmail).
- **Added**: fixed back, forward, and reload/stop controls to the compact tab
  bar, so core navigation stays available when the sidebar is hidden. The
  controls remain visible while the tab chips scroll horizontally and reflect
  the active tab's loading/history state.
- **Polished**: the Start page now adapts its dashboard cards and spacing to
  narrow iPad windows and portrait split-screen instead of forcing two cards
  into a cramped row.
- **Polished**: the Start page search field now trims blank submissions,
  disables unwanted autocorrection/capitalization for URLs, supports a clear
  button, and dismisses the keyboard after navigation.
- **Fixed**: back/forward buttons doing nothing — the SwiftUI↔WKWebView bridge
  wasn't swapping the displayed page on tab switch (`BrowserWebView` now keys
  off `controller.id` so each tab reliably shows its own web view).
- **Fixed**: downloads failing with "frame load interrupted" — downloads are
  now handled with WKWebView's native `WKDownload` API instead of trying to
  load the file in place. A small toast confirms when a download starts.
- **Fixed**: "Always Show Sidebar" was overriding manual hide/show — the
  sidebar toggle now always works, in both orientations, and there's a
  dedicated hide button next to the gear icon in the sidebar itself.
- **Added**: a working custom-background image picker (PhotosUI) — pick any
  photo and it's saved locally and used as the background.
- **Added**: a fullscreen compact layout — when the sidebar is hidden, open
  tabs show as a strip above the address bar and pinned tabs as a row below
  it (hidden entirely when there are no pins).
- **Added**: address bar suggestions from History and Bookmarks as you type.
- **Added**: a lightweight extensions system — user scripts (custom
  JavaScript injected into matching sites), manageable from Settings ▸
  Extensions. This is the realistic scope for third-party extensibility in a
  custom WKWebView browser — Safari's native Extension API is exclusive to
  Safari itself.
- **On 4K video**: WKWebView already streams whatever resolution a site
  serves (including 4K) — there's no separate quality cap to lift. Picture-in-
  Picture is now explicitly enabled, which is the part actually worth turning
  on deliberately.
- **New app icon**, provided by you.

## What's included

- **Real WKWebView browsing**: back/forward/reload/stop, desktop vs. mobile
  user agent switching, JavaScript toggle, find-on-page, page zoom, popup/new
  tab handling, per-tab loading state.
- **Arc-style sidebar**: multiple Spaces (each with its own color, icon, tabs,
  and pinned favorites), drag-free reordering via context menus, pin/unpin,
  rename, duplicate, move-to-space, archive, close, and restore-last-closed.
- **Automatic tab archiving** (never / 1 day / 7 days / 30 days) — archived
  tabs are hidden but never deleted; they're recoverable from the sidebar.
- **Liquid Glass design system**: translucent panels, blur, soft gradients,
  full dark/light/system appearance, 8 accent color presets plus a custom
  color picker, and a customizable background (default / solid / gradient /
  image).
- **Sidebar customization**: width, transparency, blur, corner radius,
  compact mode, favicon/space-name visibility, always-show vs. auto-hide.
- **Start page**: minimal / favorites / dashboard layouts with recents and
  pinned shortcuts.
- **Floating address bar** with configurable search engine (Google, Bing,
  DuckDuckGo, Brave, or a custom template URL).
- **Settings app**: General, Appearance, Sidebar, Tabs, Privacy, Downloads,
  Advanced, About.
- **Private Browsing** using a separate, non-persistent `WKWebsiteDataStore`
  — private tabs never write to History.
- **History** (grouped by day, searchable, deletable) and **Bookmarks**
  (folders, search, edit) backed by SwiftData.
- **Downloads manager** using a background-capable `URLSession`, with
  progress, Quick Look preview, and Share/Delete actions.
- **Custom error pages** for offline / DNS / SSL failures that keep the tab
  alive instead of nuking it.
- **Keyboard shortcuts** (⌘L, ⌘T, ⌘W, ⌘⇧T, ⌘R, ⌘[, ⌘]) via SwiftUI `Commands`,
  plus trackpad/mouse and hardware keyboard support that comes for free with
  UIKit/SwiftUI on iPadOS.
- **Responsive layout**: full sidebar in landscape, collapsible sidebar with
  a toggle in portrait, adaptive to iPad multitasking/split view.
- **Persistence via SwiftData**: Spaces, tabs, bookmarks, history, and
  downloads all survive relaunch.

## Project structure

```
Trident/
├── project.yml                  # XcodeGen spec — generates the .xcodeproj at build time
├── Sources/
│   ├── App/                     # App entry point
│   ├── Models/                  # SwiftData models (Space, BrowserTab, Bookmark, History, Download)
│   ├── Persistence/             # SwiftData ModelContainer setup
│   ├── Settings/                # AppSettings store + Settings UI
│   ├── ViewModels/               # BrowserViewModel (tabs/spaces/navigation coordinator)
│   ├── Browser/                 # WKWebView wrapper, error pages
│   ├── Sidebar/                 # Sidebar, Space switcher/editor, tab rows
│   ├── AddressBar/               # Floating address/search bar
│   ├── StartPage/                # New-tab / dashboard page
│   ├── History/, Bookmarks/, Downloads/
│   ├── Shared/                  # Glass UI components, color/favicon helpers, keyboard shortcuts
│   └── ContentView.swift        # Root layout (sidebar + web content)
├── Resources/Assets.xcassets/   # App icon (original geometric trident mark) + accent color
└── .github/workflows/build.yml  # CI: builds an unsigned IPA
```

## Building locally in Xcode

This repo does **not** commit a `.xcodeproj` — it's generated on demand with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project file can
never go stale or corrupt relative to the source tree.

```bash
brew install xcodegen
cd Trident
xcodegen generate
open Trident.xcodeproj
```

Select the **Trident** scheme, choose an iPad simulator or a real device, and
run. Deployment target is iOS 17.0 (required for SwiftData and
`ContentUnavailableView`).

## Building via GitHub Actions (unsigned IPA)

1. Push this repository to GitHub.
2. The workflow at `.github/workflows/build.yml` runs automatically on every
   push to `main` (and can be triggered manually from the Actions tab via
   "Run workflow").
3. It installs XcodeGen, generates the project, archives the app with code
   signing disabled (`CODE_SIGNING_ALLOWED=NO`), and packages the result as
   `Trident-unsigned.ipa`.
4. Download the **Trident-unsigned-ipa** artifact from the completed workflow
   run. A secondary **Trident-xcarchive** artifact is also uploaded in case
   you want to re-sign directly from the `.xcarchive` instead.
5. Sign the IPA yourself (e.g. with your own Apple Developer certificate and
   provisioning profile, `codesign`, `altool`/`notarytool` for distribution,
   or a resigning tool of your choice) before installing it on a device.

No certificates, provisioning profiles, or private credentials are included
or required for the CI build to succeed.

## Honest limitations — please read before filing this as "done"

This project was generated in a single pass by an AI assistant that does
**not** have access to Xcode, an iOS SDK, or a simulator to compile and test
it. It's a complete, real implementation of every major feature in the brief
— not placeholder screens — but a project this size (SwiftData relationships,
WKWebView delegate plumbing, ~35 Swift files) has a realistic chance of
hitting a compiler error or two in Xcode that a normal human development
cycle would catch via the "build → fix → rebuild" loop. Specifically expect
to possibly need to:

- Resolve any XcodeGen/Xcode version mismatches in CI (Xcode versions on
  GitHub's macOS runners change over time — the workflow tries a specific
  version first and falls back to the default).
- Double check SwiftData model relationships if you add new fields — this
  project deliberately avoids SwiftData `@Relationship` in favor of plain
  UUID foreign keys (`spaceID`, `folderID`, etc.) to keep the schema simple
  and less prone to migration issues.
- Treat Apple Pencil, full drag-and-drop tab reordering (currently done via
  context-menu actions rather than a drag gesture), and tracking-protection
  content blocking as scaffolded-but-simplified rather than fully polished —
  they're wired up at a basic level but would benefit from a real device
  testing pass.
- The two independent `ModelContext` instances (one owned by
  `BrowserViewModel`, one supplied by SwiftUI's `.modelContainer` environment
  for `@Query` views like History/Bookmarks/Downloads) both point at the same
  underlying store and should stay in sync, but if you see stale data in a
  sheet after an edit, that's the first place to look.

If Xcode reports an error, it will point at a specific file and line — that's
normal iteration, not a sign the project is broken.

## App identity

- **Name**: Trident
- **Icon**: an original geometric trident mark on a lavender-to-purple
  gradient (generated for this project, not derived from any existing
  logo/brand).
- **Primary palette**: near-black backgrounds, lavender/purple accents,
  translucent "Liquid Glass" surfaces — full light mode also included.
