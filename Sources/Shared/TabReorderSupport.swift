import SwiftUI
import UniformTypeIdentifiers

/// Drives live reordering for a horizontal strip of draggable tab chips.
/// Works on a local `[BrowserTab]` snapshot bound to the caller so the strip
/// reflows immediately as items are dragged past each other, then commits the
/// final order via `onReorder` (which persists it through `BrowserViewModel`).
struct TabChipDropDelegate: DropDelegate {
    let item: BrowserTab
    @Binding var items: [BrowserTab]
    @Binding var draggingID: UUID?
    let onReorder: ([BrowserTab]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggingID }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else { return }

        if items[toIndex].id != draggingID {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        onReorder(items)
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
