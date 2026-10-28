import AppKit

enum SideRow {
    case header(key: String, title: String, collapsed: Bool, count: Int, named: Bool)
    case tab(id: ObjectIdentifier, title: String, index: Int, active: Bool, pinned: Bool)
}

final class TabSidebar: NSView {
    var onSelect: ((ObjectIdentifier) -> Void)?
    var onClose: ((ObjectIdentifier) -> Void)?
    var onNew: (() -> Void)?
    var onNewGroup: (() -> Void)?
    var onFilter: ((NSView) -> Void)?
    var onToggle: ((String) -> Void)?
    var onRenameGroup: ((String, String) -> Void)?
    var onNewInGroup: ((String) -> Void)?
    var onGroupMenu: ((String, NSView) -> Void)?
    var onTabMenu: ((ObjectIdentifier, NSView) -> Void)?
    var onRenameTab: ((ObjectIdentifier, String) -> Void)?
    var onReorder: ((String, Int) -> Void)?
    var onCollapseSidebar: (() -> Void)?

    private let plate = NSVisualEffectView()
    private let header = NSTextField(labelWithString: "标签")
    private let filter = NSButton()
    private let addGroup = NSButton()
    private let collapse = NSButton()
    private let add = NSButton()
    private let list = FlippedView(frame: .zero)
    private var rows: [SideRow] = []
    private var rowViews: [NSView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        appearance = NSAppearance(named: .darkAqua)
        plate.material = .hudWindow
        plate.blendingMode = .behindWindow
        plate.state = .active
        plate.autoresizingMask = [.width, .height]
        plate.alphaValue = 0.82
        plate.frame = bounds
        addSubview(plate, positioned: .below, relativeTo: nil)
        header.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        addSubview(header)
        configureIcon(filter, "line.3.horizontal.decrease", #selector(filterClick))
        configureIcon(addGroup, "folder.badge.plus", #selector(addGroupClick))
        configureIcon(add, "plus", #selector(addClick))
        configureIcon(collapse, "sidebar.left", #selector(collapseClick))
        collapse.contentTintColor = .white
        collapse.toolTip = "收起侧栏"
        addGroup.toolTip = "新建分组"
        add.toolTip = "新建标签"
        addSubview(filter)
        addSubview(collapse)
        addSubview(addGroup)
        addSubview(add)
        addSubview(list)
    }

    required init?(coder: NSCoder) { fatalError() }

    func render(_ rows: [SideRow]) {
        self.rows = rows
        list.subviews.forEach { $0.removeFromSuperview() }
        rowViews = rows.enumerated().map { makeRow(index: $0, row: $1) }
        rowViews.forEach { list.addSubview($0) }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    func beginRename(_ key: String) {
        guard let header = rowViews.compactMap({ $0 as? GroupHeader }).first(where: { $0.key == key }),
              header.window != nil else { return }
        header.beginRename()
    }

    func beginRenameTab(_ id: ObjectIdentifier) {
        for (i, row) in rows.enumerated() {
            if case let .tab(tabId, _, _, _, _) = row, tabId == id {
                (rowViews[i] as? TabRow)?.beginRename()
            }
        }
    }

    private var draggingKey: String?

    private func markDrop(at windowPoint: NSPoint) {
        let local = list.convert(windowPoint, from: nil)
        for (i, row) in rows.enumerated() {
            guard case .header = row else { continue }
            let on = rowViews[i].frame.contains(NSPoint(x: rowViews[i].frame.midX, y: local.y))
            rowViews[i].layer?.backgroundColor = on
                ? NSColor.labelColor.withAlphaComponent(0.16).cgColor
                : NSColor.clear.cgColor
        }
    }

    private func finishDrop(_ key: String, at windowPoint: NSPoint) {
        let index = headerIndex(at: windowPoint)
        rowViews.forEach { $0.layer?.backgroundColor = NSColor.clear.cgColor }
        draggingKey = nil
        onReorder?(key, index)
    }

    private func headerIndex(at windowPoint: NSPoint) -> Int {
        let y = list.convert(windowPoint, from: nil).y
        var seen = 0
        for (i, row) in rows.enumerated() {
            guard case .header = row else { continue }
            if y < rowViews[i].frame.midY { return seen }
            seen += 1
        }
        return seen
    }


    override func layout() {
        plate.frame = bounds
        super.layout()
        let top = Glass.titleInset(in: self) + 8
        collapse.frame = NSRect(x: 8, y: bounds.height - top - 18, width: 22, height: 22)
        header.frame = NSRect(x: 34, y: bounds.height - top - 16, width: 72, height: 16)
        add.frame = NSRect(x: bounds.width - 32, y: bounds.height - top - 18, width: 22, height: 22)
        addGroup.frame = NSRect(x: bounds.width - 56, y: bounds.height - top - 18, width: 22, height: 22)
        filter.frame = NSRect(x: bounds.width - 80, y: bounds.height - top - 18, width: 22, height: 22)
        list.frame = NSRect(x: 0, y: 8, width: bounds.width, height: max(0, bounds.height - top - 36))
        var y: CGFloat = 4
        for (i, row) in rows.enumerated() {
            let height: CGFloat
            switch row {
            case .header: height = 30
            case .tab: height = 32
            }
            rowViews[i].frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: height)
            y += height
        }
    }

    private func makeRow(index: Int, row: SideRow) -> NSView {
        switch row {
        case let .header(key, title, collapsed, count, named):
            let view = GroupHeader(key: key, title: title, collapsed: collapsed, count: count, named: named)
            view.onClick = { [weak self] in self?.onToggle?(key) }
            view.onRename = { [weak self] text in self?.onRenameGroup?(key, text) }
            view.onNew = { [weak self] in self?.onNewInGroup?(key) }
            view.onMenu = { [weak self] sender in self?.onGroupMenu?(key, sender) }
            view.onDrag = { [weak self] point in self?.draggingKey = key; self?.markDrop(at: point) }
            view.onDrop = { [weak self] point in self?.finishDrop(key, at: point) }
            return view
        case let .tab(id, title, index, active, pinned):
            let view = TabRow(title: title, index: index, active: active, pinned: pinned)
            view.onClick = { [weak self] in self?.onSelect?(id) }
            view.onClose = { [weak self] in self?.onClose?(id) }
            view.onMenu = { [weak self] sender in self?.onTabMenu?(id, sender) }
            view.onRename = { [weak self] text in self?.onRenameTab?(id, text) }
            return view
        }
    }

    private func configureIcon(_ button: NSButton, _ symbol: String, _ action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
    }

    @objc private func addClick() { onNew?() }
    @objc private func addGroupClick() { onNewGroup?() }
    @objc private func filterClick() { onFilter?(filter) }
    @objc private func collapseClick() { onCollapseSidebar?() }
}

private final class GroupHeader: NSView, NSTextFieldDelegate {
    let key: String
    var onClick: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onNew: (() -> Void)?
    var onMenu: ((NSView) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDrop: ((NSPoint) -> Void)?
    private var dragOrigin: NSPoint?
    private var dragging = false

    private let named: Bool
    private let collapsed: Bool
    private let mark = NSImageView()
    private let label: NSTextField
    private let countLabel = NSTextField(labelWithString: "")
    private let plus = NSButton()
    private let fold = NSButton()
    private var editor: NSTextField?
    private var shouldCommit = true
    private var hovering = false

    init(key: String, title: String, collapsed: Bool, count: Int, named: Bool) {
        self.key = key
        self.named = named
        self.collapsed = collapsed
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        mark.image = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: collapsed ? "展开" : "收起")
        mark.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        mark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        mark.toolTip = collapsed ? "展开" : "收起"
        mark.isHidden = true
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.drawsBackground = false
        label.isBordered = false
        addSubview(label)
        countLabel.stringValue = "\(count)"
        countLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right
        countLabel.drawsBackground = false
        countLabel.isBordered = false
        countLabel.isHidden = !collapsed
        addSubview(countLabel)
        fold.title = collapsed ? "▸" : "▾"
        fold.bezelStyle = .inline
        fold.isBordered = false
        fold.imagePosition = .noImage
        fold.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        fold.contentTintColor = .white
        fold.toolTip = collapsed ? "展开" : "收起"
        fold.target = self
        fold.action = #selector(foldClick)
        addSubview(fold)
        plus.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建终端")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        plus.isBordered = false
        plus.imagePosition = .imageOnly
        plus.contentTintColor = .white
        plus.target = self
        plus.action = #selector(plusClick)
        plus.alphaValue = 1
        plus.toolTip = "新建终端"
        addSubview(plus)
    }

    required init?(coder: NSCoder) { fatalError() }

    func beginRename() {
        guard editor == nil, window != nil else { return }
        let field = NSTextField(string: label.stringValue)
        field.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        field.textColor = .secondaryLabelColor
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.delegate = self
        editor = field
        shouldCommit = true
        label.isHidden = true
        plus.isHidden = true
        addSubview(field)
        place()
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        plus.alphaValue = editor == nil ? 1 : 0
        place()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        plus.alphaValue = 0.55
        place()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let editor, editor.frame.contains(point) { return editor }
        if fold.frame.contains(point) { return fold }
        if plus.frame.contains(point) { return plus }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            beginRename()
            return
        }
        dragOrigin = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let p = event.locationInWindow
        if hypot(p.x - origin.x, p.y - origin.y) > 4 {
            dragging = true
            onDrag?(p)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            onDrop?(event.locationInWindow)
        } else if event.clickCount != 2 {
            onClick?()
        }
        dragging = false
        dragOrigin = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onMenu?(self)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        place()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            shouldCommit = false
            window?.makeFirstResponder(nil)
            if editor != nil { applyEnd() }
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        applyEnd()
    }

    @objc private func plusClick() { onNew?() }
    @objc private func foldClick() { onClick?() }

    private func applyEnd() {
        guard let field = editor else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = shouldCommit && !text.isEmpty
        editor = nil
        plus.alphaValue = hovering ? 1 : 0.55
        field.removeFromSuperview()
        label.isHidden = false
        fold.frame = NSRect(x: 2, y: 4, width: 22, height: 22)
        mark.frame = fold.frame
        shouldCommit = true
        place()
        if commit { onRename?(text) }
    }

    private func place() {
        let width = bounds.width
        fold.frame = NSRect(x: 0, y: 3, width: 22, height: 22)
        mark.frame = NSRect(x: 4, y: 7, width: 14, height: 14)
        plus.frame = NSRect(x: max(20, width - 18), y: 6, width: 14, height: 14)
        let countWidth: CGFloat = collapsed ? 28 : 0
        let countX = plus.isHidden ? width - countWidth - 4 : plus.frame.minX - countWidth - 2
        countLabel.frame = NSRect(x: countX, y: 6, width: countWidth, height: 14)
        countLabel.isHidden = !collapsed
        let trailing = plus.isHidden
            ? (collapsed ? countLabel.frame.minX : width)
            : (collapsed ? countLabel.frame.minX : plus.frame.minX)
        let field = editor ?? label
        field.frame = NSRect(x: 20, y: 4, width: max(0, trailing - 24), height: 16)
        if editor != nil { label.frame = field.frame }
    }
}

private final class TabRow: NSView, NSTextFieldDelegate {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var onMenu: ((NSView) -> Void)?
    var onRename: ((String) -> Void)?
    private let active: Bool
    private let pinned: Bool
    private var hovering = false
    private let label: NSTextField
    private let pin = NSImageView()
    private let close = NSButton()
    private let badge = NSTextField(labelWithString: "")
    private var editor: NSTextField?
    private var shouldCommit = true

    init(title: String, index: Int, active: Bool, pinned: Bool) {
        self.active = active
        self.pinned = pinned
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
        pin.contentTintColor = .tertiaryLabelColor
        pin.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        pin.isHidden = !pinned
        addSubview(pin)
        label.font = NSFont.systemFont(ofSize: 13, weight: active ? .semibold : .regular)
        label.textColor = active ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.drawsBackground = false
        label.isBordered = false
        addSubview(label)
        badge.stringValue = "#\(index)"
        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = .tertiaryLabelColor
        badge.alignment = .right
        badge.drawsBackground = false
        badge.isBordered = false
        addSubview(badge)
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.contentTintColor = .tertiaryLabelColor
        close.target = self
        close.action = #selector(closeClick)
        close.isHidden = true
        addSubview(close)
        updateFill()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func closeClick() { onClose?() }

    override func layout() {
        super.layout()
        place()
    }

    private func place() {
        let width = bounds.width
        pin.frame = NSRect(x: 8, y: 9, width: 10, height: 12)
        let leading: CGFloat = pinned ? 22 : 10
        let trailing: CGFloat = close.isHidden ? 36 : 52
        label.frame = NSRect(x: leading, y: 7, width: max(0, width - leading - trailing), height: 18)
        if let field = editor { field.frame = label.frame }
        close.frame = NSRect(x: width - 48, y: 8, width: 14, height: 14)
        badge.frame = NSRect(x: width - 32, y: 8, width: 24, height: 14)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        close.isHidden = editor != nil
        updateFill()
        place()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        close.isHidden = true
        updateFill()
        place()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let editor, editor.frame.contains(point) { return editor }
        if close.isHidden == false, close.frame.contains(point) { return close }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            beginRename()
            return
        }
        if event.clickCount == 1 { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?(self) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            shouldCommit = false
            window?.makeFirstResponder(nil)
            if editor != nil { applyEnd() }
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        applyEnd()
    }

    func beginRename() {
        guard editor == nil, window != nil else { return }
        let field = NSTextField(string: label.stringValue)
        field.font = label.font
        field.textColor = label.textColor
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.frame = label.frame
        field.delegate = self
        editor = field
        shouldCommit = true
        label.isHidden = true
        addSubview(field)
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    private func applyEnd() {
        guard let field = editor else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = shouldCommit && !text.isEmpty
        editor = nil
        field.delegate = nil
        field.removeFromSuperview()
        label.isHidden = false
        shouldCommit = true
        if commit { onRename?(text) }
    }

    private func updateFill() {
        if active {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        } else if hovering {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
