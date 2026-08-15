import SwiftUI
import SwiftData

@main
struct TridentApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var browser: BrowserViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var storeLoadFailure: String?
    private let context: ModelContext

    init() {
        // IMPORTANT: `PersistenceController.container` is a lazy static — it
        // only actually runs its do/catch (and sets `storeLoadFailure`) the
        // first time something touches it. That happens right here. Property
        // wrapper defaults declared on `storeLoadFailure` above would have
        // been evaluated by Swift *before* this init body runs at all, i.e.
        // before the container was ever forced to load — which is exactly
        // why the alert never fired no matter what actually happened.
        let context = ModelContext(PersistenceController.container)
        self.context = context
        _storeLoadFailure = State(initialValue: PersistenceController.storeLoadFailure)
        _browser = StateObject(wrappedValue: BrowserViewModel(context: context, settings: .shared))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browser)
                .environmentObject(settings)
                .modelContainer(PersistenceController.container)
                .alert("Data Didn't Load", isPresented: Binding(
                    get: { storeLoadFailure != nil },
                    set: { if !$0 { storeLoadFailure = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(storeLoadFailure ?? "")
                }
        }
        .commands {
            TridentCommands(browser: browser)
        }
        // Every tab/space mutation already calls `context.save()` on the spot,
        // but that's not a hard guarantee nothing is left pending the instant
        // iOS suspends or kills the app in the background — which is exactly
        // when a swipe-to-quit can happen. Flushing again here on every
        // backgrounding transition is what makes tabs reliably still be
        // there the next time the app launches, instead of only "usually".
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                do {
                    try context.save()
                } catch {
                    print("[TridentApp] background save failed: \(error)")
                }
                ExtensionServiceWorkerManager.shared.unloadAll()
            }
        }
    }
}
