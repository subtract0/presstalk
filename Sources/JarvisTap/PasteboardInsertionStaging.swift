import AppKit

struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems = items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        _ = pasteboard.writeObjects(restoredItems)
    }
}

struct PasteboardInsertionStaging {
    let snapshot: PasteboardSnapshot
    let stagedChangeCount: Int

    static func stage(_ text: String, on pasteboard: NSPasteboard) -> PasteboardInsertionStaging {
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return PasteboardInsertionStaging(snapshot: snapshot, stagedChangeCount: pasteboard.changeCount)
    }

    func restoreIfUnchanged(on pasteboard: NSPasteboard) {
        guard pasteboard.changeCount == stagedChangeCount else { return }
        snapshot.restore(to: pasteboard)
    }
}
