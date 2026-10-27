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
        layer?.backgroundColor = NSColor.black.cgColor
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = NSColor.white.withAlphaComponent(0.55)
        hint.drawsBackground = false
        hint.isBezeled = false
        hint.isEditable = false
        addSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setRoot(_ view: NSView) {
        if root !== view { root?.removeFromSuperview() }
        root = view
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = []
        addSubview(view, positioned: .below, relativeTo: hint)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let bar: CGFloat = 22
        hint.frame = NSRect(x: 10, y: 3, width: max(0, bounds.width - 20), height: 16)
        root?.frame = NSRect(x: 0, y: bar, width: bounds.width, height: max(0, bounds.height - bar))
    }
}

final class ShellView: NSView {
    let host = TerminalHost(frame: .zero)
    let dock = AgentDock(frame: .zero)
    var showDock = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(host)
        addSubview(dock)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setDockVisible(_ on: Bool) {
        showDock = on
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = showDock ? min(400, max(300, floor(bounds.width * 0.34))) : 0
        dock.isHidden = !showDock
        dock.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
        host.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - width), height: bounds.height)
    }
}

final class AgentDock: NSView, NSTextViewDelegate {
    var onSend: (() -> Void)?
    var onQueue: (() -> Void)?
    var onAttach: (() -> Void)?
    var onHide: (() -> Void)?
    var onApprove: ((String, Bool) -> Void)?

    private let state = NSTextField(labelWithString: "空闲")
    private let model = NSTextField(labelWithString: "")
    private let transcript = NSTextView()
    private let transcriptScroll = NSScrollView()
    private let approval = NSView()
    private let approvalText = NSTextField(wrappingLabelWithString: "")
    private var approvalId: String?
    private let chip = NSTextField(labelWithString: "")
    private let queueLabel = NSTextField(labelWithString: "")
    private let composer = NSTextView()
    private let composerScroll = NSScrollView()
    private let placeholder = NSTextField(labelWithString: "描述要做的事\n⌘↩ 发送 · ↩ 换行 · ⌥⌘↩ 排队")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1).cgColor

        styleLabel(state, size: 11, weight: .semibold, color: NSColor.white.withAlphaComponent(0.7))
        styleLabel(model, size: 11, weight: .regular, color: NSColor.white.withAlphaComponent(0.4))
        styleLabel(chip, size: 11, weight: .medium, color: NSColor.systemTeal)
        styleLabel(queueLabel, size: 11, weight: .medium, color: NSColor.systemOrange)
        chip.isHidden = true
        queueLabel.isHidden = true

        transcript.isEditable = false
        transcript.isSelectable = true
        transcript.isRichText = false
        transcript.drawsBackground = false
        transcript.textColor = NSColor.white.withAlphaComponent(0.92)
        transcript.font = NSFont.systemFont(ofSize: 13)
        transcript.textContainerInset = NSSize(width: 8, height: 8)
        transcript.isVerticallyResizable = true
        transcript.isHorizontallyResizable = false
        transcript.textContainer?.widthTracksTextView = true
        transcriptScroll.documentView = transcript
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.drawsBackground = false
        transcriptScroll.borderType = .noBorder

        approval.wantsLayer = true
        approval.layer?.backgroundColor = NSColor(srgbRed: 0.16, green: 0.12, blue: 0.05, alpha: 1).cgColor
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
        composer.font = NSFont.systemFont(ofSize: 13)
        composer.textColor = .white
        composer.insertionPointColor = .white
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

        placeholder.font = NSFont.systemFont(ofSize: 12)
        placeholder.textColor = NSColor.white.withAlphaComponent(0.35)
        placeholder.maximumNumberOfLines = 3

        let hide = button("收起", #selector(hideDock))
        let attach = button("附上屏幕", #selector(attachScreen))
        let queue = button("排队", #selector(queueDraft))
        let send = button("发送", #selector(sendDraft))
        hide.tag = 2
        attach.tag = 3
        queue.tag = 4
        send.tag = 5

        for view in [state, model, hide, transcriptScroll, approval, chip, queueLabel, composerScroll, placeholder, attach, queue, send] {
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

    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = composer.string.isEmpty == false
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        let width = bounds.width
        state.frame = NSRect(x: pad, y: bounds.height - 28, width: 80, height: 16)
        model.frame = NSRect(x: 96, y: bounds.height - 28, width: max(0, width - 168), height: 16)
        viewWithTag(2)?.frame = NSRect(x: width - 64, y: bounds.height - 32, width: 52, height: 22)
        let footer: CGFloat = 36
        let composerH: CGFloat = 88
        var y = footer + 8
        composerScroll.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: composerH)
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
        let top: CGFloat = 40
        let transcriptH = max(40, bounds.height - top - y)
        transcriptScroll.frame = NSRect(x: 4, y: y, width: width - 8, height: transcriptH)
        viewWithTag(3)?.frame = NSRect(x: pad, y: 8, width: 78, height: 24)
        viewWithTag(4)?.frame = NSRect(x: width - 148, y: 8, width: 58, height: 24)
        viewWithTag(5)?.frame = NSRect(x: width - 84, y: 8, width: 72, height: 24)
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
