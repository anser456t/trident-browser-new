import SwiftUI

/// Horizontal strip of Space icons at the top of the sidebar. Tapping switches
/// Spaces with a spring animation; long-press opens the editor. Icons only —
/// no name label underneath, since the highlighted icon is enough on its own
/// to show which Space is active.
struct SpaceSwitcherView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @State private var editingSpace: Space?
    @State private var showingNewSpace = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(browser.spaces) { space in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        browser.switchSpace(to: space)
                    }
                } label: {
                    Image(systemName: space.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(space.id == browser.currentSpaceID ? .white : .white.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(space.color.opacity(space.id == browser.currentSpaceID ? 0.9 : 0.18))
                        )
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .contextMenu {
                    Button("Rename / Edit") { editingSpace = space }
                    if browser.spaces.count > 1 {
                        Button("Delete Space", role: .destructive) { browser.deleteSpace(space) }
                    }
                }
            }

            Button { showingNewSpace = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(PressFeedbackButtonStyle())
        }
        .sheet(item: $editingSpace) { space in
            SpaceEditorView(space: space)
        }
        .sheet(isPresented: $showingNewSpace) {
            SpaceEditorView(space: nil)
        }
    }
}
