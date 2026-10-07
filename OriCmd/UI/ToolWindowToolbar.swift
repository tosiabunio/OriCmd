import AppKit

/// The fixed toolbar of a tool window (Compare, Synchronize): its commands as symbol
/// buttons, grouped as given, each named in its tooltip and in the overflow menu.
/// The window enables them as its state changes.
final class ToolWindowToolbar: NSObject, NSToolbarDelegate {
    struct Button {
        let id: String
        let label: String
        let symbol: String
        let action: Selector
    }

    let toolbar: NSToolbar
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private var order: [NSToolbarItem.Identifier] = []

    /// `groups`: buttons that belong together, apart from the next group; `trailing`:
    /// groups at the far end.
    init(identifier: String, groups: [[Button]], trailing: [[Button]] = [], target: AnyObject) {
        toolbar = NSToolbar(identifier: identifier)
        super.init()
        func add(_ groups: [[Button]]) {
            for (index, group) in groups.enumerated() {
                if index > 0 { order.append(.space) }
                for button in group {
                    let id = NSToolbarItem.Identifier(button.id)
                    let item = NSToolbarItem(itemIdentifier: id)
                    item.image = NSImage(systemSymbolName: button.symbol, accessibilityDescription: button.label)
                    item.label = button.label
                    item.paletteLabel = button.label
                    item.toolTip = button.label
                    item.target = target
                    item.action = button.action
                    item.isBordered = true
                    item.autovalidates = false
                    items[id] = item
                    order.append(id)
                }
            }
        }
        add(groups)
        if !trailing.isEmpty {
            order.append(.flexibleSpace)
            add(trailing)
        }
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    func item(_ id: String) -> NSToolbarItem? {
        items[NSToolbarItem.Identifier(id)]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { order }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { order }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        items[identifier]
    }
}
