import AppKit

final class BlockPane: NSView, NSTextViewDelegate {
    var onSubmit: ((String) -> Void)?
    var onRerun: ((String) -> Void)?

    private let plate = NSVisualEffectView()
    private let scroll = NSScrollView()
    private let list = FlippedView(frame: .zero)
    private let inputBar = NSView()
    private let inputScroll = NSScrollView()
    private let input = BlockInput()
    private let placeholder = NSTextField(labelWithString: "输入命令，回车执行。")
    private var cards: [BlockCard] = []
    private var selectedID: UUID?
    private var outputBytes = 0
    private var rendered: [CommandBlock] = []
    private var chrome = BlockChrome.fallout

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = true
        layer?.backgroundColor = chrome.background.cgColor
        appearance = NSAppearance(named: .darkAqua)

        plate.material = .hudWindow
        plate.blendingMode = .behindWindow
        plate.state = .active
        plate.alphaValue = 0.9
        plate.frame = bounds
        plate.isHidden = true
        addSubview(plate, positioned: .below, relativeTo: nil)

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        addSubview(scroll)

        inputBar.wantsLayer = true
        inputBar.layer?.backgroundColor = chrome.background.cgColor
        addSubview(inputBar)

        input.isRichText = false
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.drawsBackground = false
        input.textColor = chrome.foreground
        input.insertionPointColor = chrome.accent
        input.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        input.textContainerInset = NSSize(width: 6, height: 6)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.textContainer?.widthTracksTextView = true
        input.delegate = self
        input.onSubmit = { [weak self] text in self?.submit(text) }
        inputScroll.documentView = input
        inputScroll.drawsBackground = false
        inputScroll.borderType = .noBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.wantsLayer = true
        inputScroll.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        inputScroll.layer?.cornerRadius = 6
        inputBar.addSubview(inputScroll)

        placeholder.textColor = .tertiaryLabelColor
        placeholder.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        placeholder.isBezeled = false
        placeholder.drawsBackground = false
        placeholder.isEditable = false
        placeholder.isSelectable = false
        inputBar.addSubview(placeholder)
        addSubview(inputBar)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBlocks(_ blocks: [CommandBlock]) {
        if blocks == rendered { return }
        rendered = blocks
        let grown = blocks.reduce(0) { $0 + $1.output.count } > outputBytes || blocks.count > cards.count
        outputBytes = blocks.reduce(0) { $0 + $1.output.count }
        if let selectedID, blocks.contains(where: { $0.id == selectedID }) == false {
            self.selectedID = nil
        }
        cards.forEach { $0.removeFromSuperview() }
        cards = blocks.map { block in
            let card = BlockCard(block: block, chrome: chrome)
            card.selected = block.id == selectedID
            card.onSelect = { [weak self] in self?.select(block.id) }
            card.onRerun = { [weak self] in self?.onRerun?(block.command) }
            return card
        }
        cards.forEach { list.addSubview($0) }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if grown { pinNewest() }
    }
    func apply(foreground: NSColor, background: NSColor, accent: NSColor) {
        chrome = BlockChrome(foreground: foreground, background: background, accent: accent)
        layer?.backgroundColor = background.cgColor
        inputBar.layer?.backgroundColor = background.shadow(withLevel: 0.25)?.cgColor ?? background.cgColor
        input.textColor = foreground
        input.insertionPointColor = accent
        placeholder.textColor = foreground.withAlphaComponent(0.4)
        inputScroll.layer?.backgroundColor = foreground.withAlphaComponent(0.08).cgColor
        cards.forEach { $0.apply(chrome) }
    }

    func focusInput() {
        window?.makeFirstResponder(input)
    }

    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = input.string.isEmpty == false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isHidden == false, alphaValue > 0.01 else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let hit = super.hitTest(point) {
            if hit === placeholder || hit === plate || hit === inputBar { return input }
            return hit
        }
        return self
    }

    override func layout() {
        super.layout()
        plate.frame = bounds
        let barH: CGFloat = 76
        inputBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barH)
        scroll.frame = NSRect(x: 0, y: barH, width: bounds.width, height: max(0, bounds.height - barH))
        let inset: CGFloat = 10
        inputScroll.frame = NSRect(x: inset, y: 12, width: max(0, inputBar.bounds.width - inset * 2), height: 52)
        let box = inputScroll.contentSize
        input.minSize = NSSize(width: 0, height: box.height)
        input.frame = NSRect(x: 0, y: 0, width: box.width, height: max(box.height, input.frame.height))
        placeholder.frame = NSRect(x: inset + 10, y: 28, width: max(0, inputBar.bounds.width - inset * 2 - 16), height: 20)
        layoutCards()
    }

    private func layoutCards() {
        let width = max(scroll.contentSize.width, bounds.width)
        var y: CGFloat = 8
        for card in cards {
            let h = card.preferredHeight(for: max(40, width - 16))
            card.frame = NSRect(x: 8, y: y, width: max(40, width - 16), height: h)
            y += h + 8
        }
        let height = max(y, scroll.contentView.bounds.height)
        list.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func pinNewest() {
        layoutSubtreeIfNeeded()
        let doc = list.frame.height
        let visible = scroll.contentView.bounds.height
        let y = max(0, doc - visible)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func select(_ id: UUID) {
        selectedID = id
        for card in cards {
            card.selected = card.block.id == id
        }
    }

    private func submit(_ text: String) {
        input.string = ""
        placeholder.isHidden = false
        onSubmit?(text)
    }
}

private final class BlockInput: NSTextView {
    var onSubmit: ((String) -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let newline = event.keyCode == 36 || event.charactersIgnoringModifiers == "\r"
        if newline, flags.contains(.shift) {
            insertNewlineIgnoringFieldEditor(nil)
            return
        }
        if newline, flags.isDisjoint(with: [.command, .option, .control]) {
            onSubmit?(string)
            return
        }
        super.keyDown(with: event)
    }
}

private final class BlockCard: NSView {
    let block: CommandBlock
    var onSelect: (() -> Void)?
    var onRerun: (() -> Void)?
    var selected = false { didSet { paint() } }

    private let rail = NSView()
    private let command = NSTextField(wrappingLabelWithString: "")
    private let output = NSTextField(wrappingLabelWithString: "")
    private let more = NSTextField(labelWithString: "")
    private let copyCommand = NSButton(title: "复制命令", target: nil, action: nil)
    private let copyOutput = NSButton(title: "复制输出", target: nil, action: nil)
    private let rerun = NSButton(title: "再跑", target: nil, action: nil)
    private let shown: String
    private let extra: Int
    private var chrome: BlockChrome

    init(block: CommandBlock, chrome: BlockChrome) {
        self.block = block
        self.chrome = chrome
        let lines = block.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count > 40 {
            shown = lines.prefix(40).joined(separator: "\n")
            extra = lines.count - 40
        } else {
            shown = block.output
            extra = 0
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        rail.wantsLayer = true
        rail.layer?.backgroundColor = railColor().cgColor
        addSubview(rail)

        command.stringValue = block.command
        command.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        command.textColor = chrome.foreground
        command.maximumNumberOfLines = 0
        command.lineBreakMode = .byWordWrapping
        addSubview(command)

        output.stringValue = shown
        output.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        output.textColor = chrome.foreground.withAlphaComponent(0.72)
        output.maximumNumberOfLines = 0
        output.lineBreakMode = .byWordWrapping
        addSubview(output)

        more.stringValue = extra > 0 ? "还有 \(extra) 行" : ""
        more.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        more.textColor = chrome.foreground.withAlphaComponent(0.45)
        more.isHidden = extra == 0
        addSubview(more)

        wire(copyCommand, #selector(copyCommandClick))
        wire(copyOutput, #selector(copyOutputClick))
        wire(rerun, #selector(rerunClick))
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        let textW = max(20, width - 24)
        let cmdH = Self.height(command.stringValue, font: command.font!, width: textW)
        let outH = shown.isEmpty ? 0 : Self.height(shown, font: output.font!, width: textW)
        let note: CGFloat = extra > 0 ? 18 : 0
        let gap: CGFloat = shown.isEmpty ? 0 : 6
        return 10 + cmdH + gap + outH + note + 8 + 22 + 10
    }

    override func layout() {
        super.layout()
        rail.frame = NSRect(x: 0, y: 8, width: 3, height: max(0, bounds.height - 16))
        let textX: CGFloat = 12
        let textW = max(20, bounds.width - 24)
        var y = bounds.height - 10
        let cmdH = Self.height(command.stringValue, font: command.font!, width: textW)
        y -= cmdH
        command.frame = NSRect(x: textX, y: y, width: textW, height: cmdH)
        if shown.isEmpty == false {
            y -= 6
            let outH = Self.height(shown, font: output.font!, width: textW)
            y -= outH
            output.frame = NSRect(x: textX, y: y, width: textW, height: outH)
        } else {
            output.frame = .zero
        }
        if extra > 0 {
            y -= 18
            more.frame = NSRect(x: textX, y: y, width: textW, height: 16)
        }
        let buttonY: CGFloat = 8
        copyCommand.frame = NSRect(x: textX, y: buttonY, width: 72, height: 22)
        copyOutput.frame = NSRect(x: textX + 76, y: buttonY, width: 72, height: 22)
        rerun.frame = NSRect(x: textX + 152, y: buttonY, width: 48, height: 22)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        super.mouseDown(with: event)
    }

    private func wire(_ button: NSButton, _ action: Selector) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.wantsLayer = true
        button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = chrome.foreground
        addSubview(button)
    }

    func apply(_ chrome: BlockChrome) {
        self.chrome = chrome
        command.textColor = chrome.foreground
        output.textColor = chrome.foreground.withAlphaComponent(0.72)
        more.textColor = chrome.foreground.withAlphaComponent(0.45)
        for button in [copyCommand, copyOutput, rerun] {
            button.contentTintColor = chrome.foreground
        }
        rail.layer?.backgroundColor = railColor().cgColor
        paint()
    }

    private func paint() {
        layer?.borderColor = chrome.foreground.withAlphaComponent(selected ? 0.7 : 0.18).cgColor
        layer?.backgroundColor = chrome.foreground.withAlphaComponent(selected ? 0.1 : 0.05).cgColor
    }


    @objc private func copyCommandClick() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.command, forType: .string)
    }

    @objc private func copyOutputClick() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.output, forType: .string)
    }

    @objc private func rerunClick() {
        onRerun?()
    }

    private func railColor() -> NSColor {
        if block.running { return chrome.accent }
        if block.exitCode == 0 { return chrome.foreground }
        return NSColor(srgbRed: 0.86, green: 0.42, blue: 0.32, alpha: 1)
    }

    private static func height(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let box = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(16, ceil(box.height))
    }
}

struct BlockChrome {
    var foreground: NSColor
    var background: NSColor
    var accent: NSColor

    static let fallout = BlockChrome(
        foreground: NSColor(srgbRed: 0.635, green: 0.831, blue: 0.404, alpha: 1),
        background: NSColor(srgbRed: 0.122, green: 0.157, blue: 0.090, alpha: 1),
        accent: NSColor(srgbRed: 0.847, green: 0.973, blue: 0.596, alpha: 1)
    )
}
