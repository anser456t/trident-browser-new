import SwiftUI

/// App-level keyboard commands (Command+L, Command+T, etc). Attached via
/// `.commands` in the App scene so they work with a hardware keyboard/trackpad.
struct TridentCommands: Commands {
    @ObservedObject var browser: BrowserViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { browser.createTab() }
                .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                if let tab = browser.currentTab { browser.closeTab(tab) }
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Reopen Closed Tab") { browser.restoreLastClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Focus Address Bar") { browser.isEditingAddressBar = true }
                .keyboardShortcut("l", modifiers: .command)

            Button("Reload Page") { browser.reload() }
                .keyboardShortcut("r", modifiers: .command)

            Button("Back") { browser.goBack() }
                .keyboardShortcut("[", modifiers: .command)

            Button("Forward") { browser.goForward() }
                .keyboardShortcut("]", modifiers: .command)

            Button("Find on Page") { }
                .keyboardShortcut("f", modifiers: .command)
        }
    }
}
