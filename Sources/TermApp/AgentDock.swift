import AppKit

// Warp: the terminal stays a terminal; the agent is a conversation beside it.
// Otty: a multiline composer, a queue, and context pulled from the pane.
// The dock is a sibling of the terminal, so typing in the shell does not
// reflow this column, and this column does not redraw the GPU layer.

final class TerminalHost: NSView {
    private(set) var root: NSView?
    let hint = NSTextField(labelWithString: "⌘↩ 发给 Agent")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.drawsBackground = false
        hint.isBezeled = false
        hint.isEditable = false
        addSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var panes: [TermPane] = []
    private(set) var shown: TermPane?

    func setRoot(_ view: NSView) {
        if let pane = view as? TermPane {
            addPane(pane)
            return
        }
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = []
        if view.superview !== self {
            addSubview(view, positioned: .below, relativeTo: hint)
        }
        root = view
        func reveal(_ node: NSView) {
            node.isHidden = false
            node.subviews.forEach(reveal)
        }
        reveal(view)
        for pane in panes where pane.isDescendant(of: view) == false {
            pane.isHidden = true
        }
        needsLayout = true
    }

    func addPane(_ pane: TermPane) {
        if panes.contains(where: { $0 === pane }) == false {
            panes.append(pane)
        }
        pane.translatesAutoresizingMaskIntoConstraints = true
        pane.autoresizingMask = []
        if pane.superview !== self {
            addSubview(pane, positioned: .below, relativeTo: hint)
        }
        show(pane)
    }

    func show(_ pane: TermPane) {
        if panes.contains(where: { $0 === pane }) == false { panes.append(pane) }
        shown = pane
        root = pane
        for other in panes where other !== pane { other.isHidden = true }
        pane.isHidden = false
        needsLayout = true
        needsLayout = true
    }

    func showFirst() {
        if let first = panes.first { show(first) }
    }

    override func layout() {
        super.layout()
        let bar: CGFloat = 22
        hint.frame = NSRect(x: 10, y: 3, width: max(0, bounds.width - 20), height: 16)
        let frame = NSRect(x: 0, y: bar, width: bounds.width, height: max(0, bounds.height - bar))
        root?.frame = frame
        if root is SplitView {
            root?.layoutSubtreeIfNeeded()
        } else {
            for pane in panes where pane.superview === self {
                pane.frame = frame
            }
        }
    }
}

final class ShellView: NSView {
    let host = TerminalHost(frame: .zero)
    let dock = AgentDock(frame: .zero)
    let sidebar = TabSidebar(frame: .zero)
    let blocks = BlockPane(frame: .zero)
    var showBlocks = false
    var showDock = true
    var showSidebar = true
    private let revealSide = NSButton()
    private let modeBar = ModeBar()
    var onMode: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        addSubview(sidebar)
        revealSide.title = "标签"
        revealSide.bezelStyle = .inline
        revealSide.isBordered = false
        revealSide.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        revealSide.contentTintColor = .white
        revealSide.toolTip = "展开侧栏"
        revealSide.target = self
        revealSide.action = #selector(revealSidebar)
        addSubview(revealSide)
        addSubview(host)
        addSubview(dock)
        addSubview(blocks)
        modeBar.onPick = { [weak self] blocks in self?.onMode?(blocks) }
        addSubview(modeBar)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setDockVisible(_ on: Bool) {
        showDock = on
        needsLayout = true
    }

    func setSidebarVisible(_ on: Bool) {
        showSidebar = on
        needsLayout = true
    }

    func setBlocksVisible(_ on: Bool) {
        showBlocks = on
        modeBar.blocks = on
        needsLayout = true
    }

    func applyChrome(foreground: NSColor, background: NSColor, accent: NSColor) {
        modeBar.apply(foreground: foreground, background: background)
        blocks.apply(foreground: foreground, background: background, accent: accent)
    }
    @objc private func revealSidebar() { setSidebarVisible(true) }

    override func layout() {
        super.layout()
        let side: CGFloat = showSidebar ? 200 : 0
        sidebar.isHidden = !showSidebar
        sidebar.frame = NSRect(x: 0, y: 0, width: side, height: bounds.height)
        revealSide.isHidden = showSidebar
        revealSide.frame = NSRect(x: 4, y: bounds.height - 28, width: 36, height: 20)
        let dockWidth = showDock ? min(400, max(300, floor(bounds.width * 0.34))) : 0
        dock.isHidden = !showDock
        dock.frame = NSRect(x: bounds.width - dockWidth, y: 0, width: dockWidth, height: bounds.height)
        let top = Glass.titleInset(in: self)
        let modeH: CGFloat = 28
        let contentW = max(0, bounds.width - side - dockWidth)
        modeBar.frame = NSRect(x: side, y: bounds.height - top - modeH, width: contentW, height: modeH)
        let body = NSRect(x: side, y: 0, width: contentW, height: max(0, bounds.height - top - modeH))
        host.frame = body
        blocks.frame = body
        host.isHidden = showBlocks
        blocks.isHidden = !showBlocks
    }
}

private final class ModeBar: NSView {
    var onPick: ((Bool) -> Void)?
    var blocks = false { didSet { paint() } }
    private let terminal = NSButton()
    private let block = NSButton()
    private var foreground = BlockChrome.fallout.foreground
    private var background = BlockChrome.fallout.background

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = background.cgColor
        configure(terminal, "终端", #selector(pickTerminal))
        configure(block, "块状", #selector(pickBlocks))
        addSubview(terminal)
        addSubview(block)
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(foreground: NSColor, background: NSColor) {
        self.foreground = foreground
        self.background = background
        layer?.backgroundColor = background.cgColor
        paint()
    }

    override func layout() {
        super.layout()
        terminal.frame = NSRect(x: 8, y: 2, width: 52, height: 24)
        block.frame = NSRect(x: 64, y: 2, width: 52, height: 24)
    }

    private func configure(_ button: NSButton, _ title: String, _ action: Selector) {
        button.title = title
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.wantsLayer = true
        button.target = self
        button.action = action
    }

    private func paint() {
        layer?.backgroundColor = background.cgColor
        style(terminal, on: blocks == false)
        style(block, on: blocks)
    }

    private func style(_ button: NSButton, on: Bool) {
        let color = on ? foreground : foreground.withAlphaComponent(0.45)
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: on ? .semibold : .regular),
            .foregroundColor: color
        ])
        button.layer?.backgroundColor = (on ? foreground.withAlphaComponent(0.16) : NSColor.clear).cgColor
        button.layer?.cornerRadius = 4
    }

    @objc private func pickTerminal() { onPick?(false) }
    @objc private func pickBlocks() { onPick?(true) }
}

final class AgentDock: NSView, NSTextViewDelegate {
    var onSend: (() -> Void)?
    var onQueue: (() -> Void)?
    var onAttach: (() -> Void)?
    var onHide: (() -> Void)?
    var onApprove: ((String, Bool) -> Void)?
    var onSaveModel: ((String, String, String) -> Void)?
    private let state = NSTextField(labelWithString: "空闲")
    private let model = NSTextField(labelWithString: "")
    private let transcript = NSTextView()
    private let transcriptScroll = NSScrollView()
    private let approval = NSView()
    private let approvalText = NSTextField(wrappingLabelWithString: "")
    private var approvalId: String?
    private let chip = NSTextField(labelWithString: "")
    private let queueLabel = NSTextField(labelWithString: "")
    private let composer = ComposerBox()
    private let composerScroll = NSScrollView()
    private let placeholder = ClickThroughLabel(labelWithString: "描述要做的事\n⌘↩ 发送 · ↩ 换行 · ⌥⌘↩ 排队")
    private let plate = NSVisualEffectView()
    private let modelPanel = NSView()
    private let presetPopup = NSPopUpButton()
    private let urlField = NSTextField(string: "")
    private let nameField = NSTextField(string: "")
    private let keyField = NSSecureTextField(string: "")
    private let urlLabel = NSTextField(labelWithString: "服务地址")
    private let nameLabel = NSTextField(labelWithString: "模型名")
    private let keyLabel = NSTextField(labelWithString: "API Key")
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
        addSubview(plate)

        styleLabel(state, size: 11, weight: .semibold, color: .labelColor)
        styleLabel(model, size: 11, weight: .regular, color: .secondaryLabelColor)
        styleLabel(chip, size: 11, weight: .medium, color: .systemTeal)
        styleLabel(queueLabel, size: 11, weight: .medium, color: .systemOrange)
        chip.isHidden = true
        queueLabel.isHidden = true

        transcript.isEditable = false
        transcript.isSelectable = true
        transcript.isRichText = false
        transcript.drawsBackground = false
        transcript.textColor = .labelColor
        transcript.font = NSFont.systemFont(ofSize: 13)
        transcript.textContainerInset = NSSize(width: 8, height: 8)
        transcript.isVerticallyResizable = true
        transcript.isHorizontallyResizable = false
        transcript.textContainer?.widthTracksTextView = true
        transcriptScroll.documentView = transcript
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.drawsBackground = false
        transcriptScroll.borderType = .noBorder

        approval.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.18).cgColor
        approval.layer?.cornerRadius = 6
        approval.isHidden = true
        approvalText.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        approvalText.textColor = NSColor.white.withAlphaComponent(0.9)
        approvalText.maximumNumberOfLines = 4
        approval.addSubview(approvalText)
        let allow = button("允许", #selector(allowAsk))
        let deny = button("拒绝", #selector(denyAsk))
        allow.tag = 11
        deny.tag = 10
        approval.addSubview(allow)
        approval.addSubview(deny)

        composer.isRichText = false
        composer.textColor = .labelColor
        composer.insertionPointColor = .labelColor
        composer.drawsBackground = false
        composer.isVerticallyResizable = true
        composer.isHorizontallyResizable = false
        composer.textContainer?.widthTracksTextView = true
        composer.textContainerInset = NSSize(width: 6, height: 6)
        composer.delegate = self
        composerScroll.documentView = composer
        composerScroll.hasVerticalScroller = true
        composerScroll.drawsBackground = false
        composerScroll.borderType = .noBorder
        composerScroll.wantsLayer = true
        composerScroll.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        composerScroll.layer?.cornerRadius = 6

        placeholder.textColor = .tertiaryLabelColor
        placeholder.maximumNumberOfLines = 3

        let hide = button("收起", #selector(hideDock))
        let attach = button("附上屏幕", #selector(attachScreen))
        let queue = button("排队", #selector(queueDraft))
        let send = button("发送", #selector(sendDraft))
        hide.tag = 2
        attach.tag = 3
        queue.tag = 4
        send.tag = 5
        let configure = button("配置", #selector(toggleModelPanel))
        configure.tag = 6
        configure.toolTip = "配置模型"
        buildModelPanel()
        for view in [state, model, hide, configure, transcriptScroll, approval, chip, queueLabel, composerScroll, placeholder, attach, queue, send, modelPanel] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setState(_ text: String, color: NSColor) {
        state.stringValue = text
        state.textColor = color
    }

    func setModel(_ text: String) {
        model.stringValue = text
    }

    func setModelFields(url: String, name: String, key: String) {
        urlField.stringValue = url
        nameField.stringValue = name
        keyField.stringValue = key
        selectPreset(matching: url)
    }

    func append(_ title: String, _ body: String) {
        let block = "\(title)\n\(body.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        transcript.textStorage?.append(NSAttributedString(string: block, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]))
        transcript.scrollToEndOfDocument(nil)
    }

    func setAttachment(_ summary: String?) {
        if let summary, summary.isEmpty == false {
            chip.stringValue = summary
            chip.isHidden = false
        } else {
            chip.stringValue = ""
            chip.isHidden = true
        }
        needsLayout = true
    }

    func setQueue(_ count: Int) {
        queueLabel.isHidden = count == 0
        queueLabel.stringValue = count == 0 ? "" : "排队 \(count)"
        needsLayout = true
    }

    func showApproval(id: String, command: String) {
        approvalId = id
        approvalText.stringValue = command
        approval.isHidden = false
        needsLayout = true
    }

    func clearApproval() {
        approvalId = nil
        approval.isHidden = true
        needsLayout = true
    }

    func composerText() -> String { composer.string }

    func clearComposer() {
        composer.string = ""
        placeholder.isHidden = false
    }

    func focusComposer() {
        window?.makeFirstResponder(composer)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if modelPanel.isHidden == false, modelPanel.frame.contains(point) {
            return super.hitTest(point)
        }
        if composerScroll.frame.contains(point) {
            return composer
        }
        let hit = super.hitTest(point)
        if hit === placeholder || hit === plate { return composer }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if modelPanel.isHidden == false, modelPanel.frame.contains(point) {
            super.mouseDown(with: event)
            return
        }
        if composerScroll.frame.contains(point) {
            window?.makeFirstResponder(composer)
        }
        super.mouseDown(with: event)
    }
    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = composer.string.isEmpty == false
    }

    override func layout() {
        super.layout()
        plate.frame = bounds
        let pad: CGFloat = 12
        let width = bounds.width
        let top = Glass.titleInset(in: self) + 8
        state.frame = NSRect(x: pad, y: bounds.height - top - 16, width: 80, height: 16)
        model.frame = NSRect(x: 96, y: bounds.height - top - 16, width: max(0, width - 224), height: 16)
        viewWithTag(6)?.frame = NSRect(x: width - 120, y: bounds.height - top - 20, width: 52, height: 22)
        viewWithTag(2)?.frame = NSRect(x: width - 64, y: bounds.height - top - 20, width: 52, height: 22)
        let footer: CGFloat = 36
        let composerH: CGFloat = 88
        var y = footer + 8
        composerScroll.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: composerH)
        let box = composerScroll.contentSize
        composer.minSize = NSSize(width: 0, height: box.height)
        composer.frame = NSRect(x: 0, y: 0, width: box.width, height: max(box.height, composer.frame.height))
        placeholder.frame = NSRect(x: pad + 10, y: y + composerH - 46, width: width - pad * 2 - 16, height: 40)
        y += composerH + 6
        if queueLabel.isHidden == false {
            queueLabel.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 16)
            y += 20
        }
        if chip.isHidden == false {
            chip.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 16)
            y += 20
        }
        if approval.isHidden == false {
            let h: CGFloat = 78
            approval.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: h)
            approvalText.frame = NSRect(x: 8, y: 30, width: approval.bounds.width - 16, height: 42)
            approval.viewWithTag(11)?.frame = NSRect(x: approval.bounds.width - 132, y: 6, width: 58, height: 22)
            approval.viewWithTag(10)?.frame = NSRect(x: approval.bounds.width - 68, y: 6, width: 58, height: 22)
            y += h + 8
        }
        let transcriptH = max(40, bounds.height - top - 28 - y)
        transcriptScroll.frame = NSRect(x: 4, y: y, width: width - 8, height: transcriptH)
        viewWithTag(3)?.frame = NSRect(x: pad, y: 8, width: 78, height: 24)
        viewWithTag(4)?.frame = NSRect(x: width - 148, y: 8, width: 58, height: 24)
        viewWithTag(5)?.frame = NSRect(x: width - 84, y: 8, width: 72, height: 24)
        if modelPanel.isHidden == false {
            let panelH: CGFloat = 168
            modelPanel.frame = NSRect(x: pad, y: bounds.height - top - 28 - panelH, width: width - pad * 2, height: panelH)
            layoutModelPanel()
        }
    }

    @objc private func allowAsk() { resolve(true) }
    @objc private func denyAsk() { resolve(false) }

    private func resolve(_ allow: Bool) {
        guard let approvalId else { return }
        onApprove?(approvalId, allow)
    }

    @objc private func hideDock() { onHide?() }
    @objc private func attachScreen() { onAttach?() }
    @objc private func queueDraft() { onQueue?() }
    @objc private func sendDraft() { onSend?() }

    @objc private func toggleModelPanel() {
        modelPanel.isHidden.toggle()
        needsLayout = true
    }

    @objc private func presetPicked() {
        guard let url = Self.presetURLs[presetPopup.titleOfSelectedItem ?? ""] else { return }
        urlField.stringValue = url
    }

    @objc private func saveModelFields() {
        onSaveModel?(
            urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            keyField.stringValue
        )
        modelPanel.isHidden = true
        needsLayout = true
    }

    private static let presetURLs = [
        "OpenAI": "https://api.openai.com/v1",
        "DeepSeek": "https://api.deepseek.com/v1",
        "通义千问": "https://dashscope.aliyuncs.com/compatible-mode/v1",
    ]

    private func buildModelPanel() {
        modelPanel.wantsLayer = true
        modelPanel.isHidden = true
        modelPanel.layer?.cornerRadius = 8
        modelPanel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        modelPanel.layer?.borderWidth = 1
        modelPanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        presetPopup.addItems(withTitles: ["OpenAI", "DeepSeek", "通义千问", "自定义"])
        presetPopup.selectItem(withTitle: "自定义")
        presetPopup.target = self
        presetPopup.action = #selector(presetPicked)
        presetPopup.font = NSFont.systemFont(ofSize: 12)
        for field in [urlField, nameField, keyField] {
            field.font = NSFont.systemFont(ofSize: 12)
            field.bezelStyle = .roundedBezel
        }
        for label in [urlLabel, nameLabel, keyLabel] {
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        let save = button("保存", #selector(saveModelFields))
        save.tag = 7
        for view in [presetPopup, urlLabel, urlField, nameLabel, nameField, keyLabel, keyField, save] as [NSView] {
            modelPanel.addSubview(view)
        }
    }

    private func selectPreset(matching url: String) {
        let title = Self.presetURLs.first { $0.value == url }?.key ?? "自定义"
        presetPopup.selectItem(withTitle: title)
    }

    private func layoutModelPanel() {
        let b = modelPanel.bounds
        let inset: CGFloat = 8
        let labelW: CGFloat = 62
        let rowH: CGFloat = 22
        presetPopup.frame = NSRect(x: inset, y: b.height - 32, width: b.width - inset * 2, height: 24)
        var y = b.height - 58
        for (label, field) in [(urlLabel, urlField), (nameLabel, nameField), (keyLabel, keyField)] {
            label.frame = NSRect(x: inset, y: y, width: labelW, height: rowH)
            field.frame = NSRect(x: inset + labelW, y: y, width: b.width - inset * 2 - labelW, height: rowH)
            y -= 28
        }
        modelPanel.viewWithTag(7)?.frame = NSRect(x: b.width - inset - 64, y: 8, width: 64, height: 22)
    }

    private func styleLabel(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.lineBreakMode = .byTruncatingTail
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 12)
        return button
    }
}

private final class ClickThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ComposerBox: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
