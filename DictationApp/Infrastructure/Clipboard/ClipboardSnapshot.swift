import AppKit

struct ClipboardSnapshot {
    struct Item {
        struct Representation {
            let type: NSPasteboard.PasteboardType
            let data: Data
        }

        let representations: [Representation]
    }

    let items: [Item]

    static func materialize(
        from pasteboard: NSPasteboard
    ) -> ClipboardSnapshot {
        ClipboardSnapshot(
            items: (pasteboard.pasteboardItems ?? []).map { item in
                Item(
                    representations: item.types.compactMap { type in
                        guard let data = item.data(forType: type) else {
                            return nil
                        }

                        return Item.Representation(
                            type: type,
                            data: data
                        )
                    }
                )
            }
        )
    }
}
