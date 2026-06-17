//
//  MenuEditorWindowController.swift
//  Didact
//
//  Lets the user customise a monitor's menu after the fact: reorder the top-level
//  controls, remove ones they don't want, and insert dividers between them. It
//  edits the flat `controls` list (each entry's definition is preserved untouched —
//  only arrangement changes) and saves a user-directory profile that overrides the
//  bundled one. A "divider" is a header entry (group/section), which the menu
//  renders as a separator.
//
//  Programmatic window with a drag-reorderable table, in the style of
//  TeachWizardWindowController / ListenWindowController.
//

import AppKit

@MainActor
final class MenuEditorWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let config: MonitorConfig
    private var controls: [Control]
    private let onSaved: (MonitorConfig) -> Void
    private let onClose: () -> Void

    private var window: NSWindow?
    private var table: NSTableView?
    private var removeButton: NSButton?
    private var saveButton: NSButton?

    private let rowType = NSPasteboard.PasteboardType("com.gingerbeardman.Didact.menurow")

    init(config: MonitorConfig, onSaved: @escaping (MonitorConfig) -> Void, onClose: @escaping () -> Void) {
        self.config = config
        self.controls = config.controls
        self.onSaved = onSaved
        self.onClose = onClose
    }

    func show() {
        if window == nil { buildWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Edit Menu — \(config.name)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.minSize = NSSize(width: 320, height: 280)

        let content = NSView()

        let caption = NSTextField(wrappingLabelWithString:
            "Drag to reorder. Untick a control to hide it from the menu (you can show it again any time). Add dividers to group controls.")
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabelColor
        caption.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 24
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("control"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([rowType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        scroll.documentView = table
        self.table = table

        let remove = NSButton(title: "Remove Divider", target: self, action: #selector(removeTapped))
        remove.bezelStyle = .rounded
        remove.isEnabled = false
        self.removeButton = remove
        let divider = NSButton(title: "Insert Divider", target: self, action: #selector(insertDividerTapped))
        divider.bezelStyle = .rounded
        let leftButtons = NSStackView(views: [remove, divider])
        leftButtons.translatesAutoresizingMaskIntoConstraints = false
        leftButtons.spacing = 8

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"   // Esc
        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        self.saveButton = save
        let rightButtons = NSStackView(views: [cancel, save])
        rightButtons.translatesAutoresizingMaskIntoConstraints = false
        rightButtons.spacing = 8

        [caption, scroll, leftButtons, rightButtons].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            caption.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            caption.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: leftButtons.topAnchor, constant: -14),

            leftButtons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            leftButtons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            rightButtons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            rightButtons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])

        window.contentView = content
        self.window = window
        updateButtons()
    }

    private func updateButtons() {
        // "Remove Divider" applies only to selected dividers; controls are hidden
        // (non-destructively) via their checkbox, never removed.
        let selection = table?.selectedRowIndexes ?? []
        removeButton?.isEnabled = selection.contains { $0 < controls.count && controls[$0].isHeader }
        saveButton?.isEnabled = cleaned(controls).contains { !$0.isHeader }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { controls.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let control = controls[row]
        if control.isHeader {
            let id = NSUserInterfaceItemIdentifier("divider")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
                let c = NSTableCellView()
                let tf = NSTextField(labelWithString: "")
                tf.translatesAutoresizingMaskIntoConstraints = false
                tf.alignment = .center
                tf.textColor = .tertiaryLabelColor
                c.addSubview(tf); c.textField = tf; c.identifier = id
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
            cell.textField?.stringValue = "—————  divider  —————"
            return cell
        }
        // A checkbox whose state IS the control's visibility; the row view is the
        // checkbox itself so the whole row reads as one tickable item.
        let id = NSUserInterfaceItemIdentifier("control")
        let box = (tableView.makeView(withIdentifier: id, owner: self) as? NSButton) ?? {
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleVisibility(_:)))
            b.identifier = id
            b.lineBreakMode = .byTruncatingTail
            return b
        }()
        box.title = "\(control.label ?? "Control")   ·   \(control.kind.rawValue)"
        box.state = (control.hidden == true) ? .off : .on
        return box
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    // Drag-to-reorder.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let s = item.string(forType: rowType), let src = Int(s), src < controls.count else { return false }
        var dest = row
        let moved = controls.remove(at: src)
        if src < dest { dest -= 1 }
        controls.insert(moved, at: min(dest, controls.count))
        tableView.reloadData()
        tableView.selectRowIndexes([min(dest, controls.count - 1)], byExtendingSelection: false)
        updateButtons()
        return true
    }

    // MARK: - Actions

    /// Toggle a control's visibility (hide is reversible — the control stays in the
    /// profile). Resolve the row live so it survives reordering.
    @objc private func toggleVisibility(_ sender: NSButton) {
        guard let table else { return }
        let r = table.row(for: sender)
        guard r >= 0, r < controls.count else { return }
        controls[r].hidden = (sender.state == .on) ? nil : true
        updateButtons()
    }

    /// Remove only selected dividers — controls are hidden via their checkbox.
    @objc private func removeTapped() {
        guard let table else { return }
        let dividers = table.selectedRowIndexes.filter { $0 < controls.count && controls[$0].isHeader }.sorted(by: >)
        guard !dividers.isEmpty else { return }
        for i in dividers { controls.remove(at: i) }
        table.reloadData()
        table.deselectAll(nil)
        updateButtons()
    }

    @objc private func insertDividerTapped() {
        let at = (table?.selectedRow ?? -1) >= 0 ? table!.selectedRow + 1 : controls.count
        controls.insert(Control(kind: .section), at: min(at, controls.count))
        table?.reloadData()
        table?.selectRowIndexes([min(at, controls.count - 1)], byExtendingSelection: false)
        updateButtons()
    }

    @objc private func cancelTapped() { window?.close() }

    @objc private func saveTapped() {
        let final = cleaned(controls)
        guard final.contains(where: { !$0.isHeader }) else { return }
        let updated = MonitorConfig(name: config.name, match: config.match, edid: config.edid,
                                    controls: final, comment: config.comment, schemaVersion: config.schemaVersion)
        do {
            try MonitorConfigStore.save(updated, overwriting: true)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        onSaved(updated)
        window?.close()
    }

    /// Tidy the saved list: no leading, trailing, or doubled dividers (the menu
    /// dedups these at render anyway, but a clean file is nicer to re-edit).
    private func cleaned(_ items: [Control]) -> [Control] {
        var out: [Control] = []
        for c in items {
            if c.isHeader, out.isEmpty || out.last?.isHeader == true { continue }
            out.append(c)
        }
        while out.last?.isHeader == true { out.removeLast() }
        return out
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) { onClose() }
}
