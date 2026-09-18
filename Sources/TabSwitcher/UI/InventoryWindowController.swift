import AppKit
import TabCore

/// Phase 1 demo surface: an outline of every app and its windows, with per-source
/// timings. Deliberately plain AppKit — this window is a diagnostic, not the product.
/// The real overlay arrives in Phase 2 and shares none of this code.
@MainActor
final class InventoryWindowController: NSWindowController {
    private let inventory = WindowInventory()
    private let focus = FocusController()
    private let outline = NSOutlineView()
    private let status = NSTextField(labelWithString: "")
    private var groups: [AppGroup] = []
    private var groupNativeTabs = true

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TabSwitcher — window inventory (Phase 1)"
        window.center()
        self.init(window: window)
        build()
        Task { await reload() }
    }

    private func build() {
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(reloadNow))
        let tabsToggle = NSButton(
            checkboxWithTitle: "Break out native tabs",
            target: self,
            action: #selector(toggleNativeTabs)
        )
        tabsToggle.state = .on

        status.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 6

        let column = NSTableColumn(identifier: .init("main"))
        column.width = 700
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 22
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(activateSelection)

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true

        let controls = NSStackView(views: [refresh, tabsToggle])
        controls.orientation = .horizontal
        controls.spacing = 12

        let stack = NSStackView(views: [controls, scroll, status])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        window?.contentView = stack
    }

    @objc private func reloadNow() { Task { await reload() } }

    @objc private func toggleNativeTabs(_ sender: NSButton) {
        groupNativeTabs = sender.state == .on
        Task { await reload() }
    }

    private func reload() async {
        guard AXWindowReader.isTrusted(prompting: true) else {
            status.stringValue = """
                Accessibility permission not granted.
                System Settings → Privacy & Security → Accessibility, then Refresh.
                Without it we can read window geometry but not titles, tabs, or raise anything.
                """
            return
        }
        let result = await inventory.enumerate(
            options: .init(groupNativeTabs: groupNativeTabs)
        )
        groups = result.groups
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        status.stringValue = result.diagnostics.joined(separator: "\n")
    }

    @objc private func activateSelection() {
        guard let ref = outline.item(atRow: outline.selectedRow) as? WindowEntry else { return }
        Task {
            let element = await inventory.element(for: ref.windowID)
            focus.rememberFront()
            let outcome = await focus.commit(ref, element: element)
            await inventory.noteActivation(app: ref.pid, window: ref.windowID)
            status.stringValue = "raise \"\(ref.title)\" → \(outcome)"
        }
    }
}

extension InventoryWindowController: NSOutlineViewDataSource {
    func outlineView(_ view: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case nil: groups.count
        case let group as AppGroup: group.windows.count
        default: 0
        }
    }

    func outlineView(_ view: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case nil: groups[index]
        case let group as AppGroup: group.windows[index]
        default: fatalError("unreachable: only apps have children")
        }
    }

    func outlineView(_ view: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is AppGroup
    }
}

extension InventoryWindowController: NSOutlineViewDelegate {
    func outlineView(_ view: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
        let label = NSTextField(labelWithString: describe(item))
        label.font = item is AppGroup
            ? .systemFont(ofSize: 12, weight: .medium)
            : .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = item is AppGroup ? .labelColor : .secondaryLabelColor
        return label
    }

    private func describe(_ item: Any) -> String {
        switch item {
        case let group as AppGroup:
            "\(group.app.localizedName)  —  \(group.windows.count) window\(group.windows.count == 1 ? "" : "s")"
                + (group.expandable ? "  ⧉" : "")
        case let window as WindowEntry:
            "\(badges(window.flags))  \(window.title)   [id \(window.windowID)]"
        default:
            ""
        }
    }

    private func badges(_ flags: WindowFlags) -> String {
        var marks: [String] = []
        if flags.contains(.main) { marks.append("main") }
        if flags.contains(.minimized) { marks.append("min") }
        if flags.contains(.nativeTab) { marks.append("tab") }
        if !flags.contains(.onCurrentSpace) { marks.append("other-space") }
        return marks.isEmpty ? "    " : "[\(marks.joined(separator: ","))]"
    }
}
