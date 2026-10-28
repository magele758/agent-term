import AppKit
import SwiftTerm

final class AgentTermView: LocalProcessTerminalView {
    var directory: () -> String = { FileManager.default.currentDirectoryPath }

    override func mouseUp(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        super.mouseUp(with: event)
        if command || selection.active == false { return }
        if selection.getSelectedText().isEmpty == false { copy(self) }
    }

    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        openAgentLink(link, cwd: directory())
    }
}

func openAgentLink(_ link: String, cwd: String) {
    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
       ["http", "https", "file", "mailto"].contains(scheme) {
        NSWorkspace.shared.open(url)
        return
    }
    var path = trimmed
    if path.hasPrefix("~/") { path = NSString(string: path).expandingTildeInPath }
    if let colon = path.range(of: #":\d+$"#, options: .regularExpression) {
        path = String(path[..<colon.lowerBound])
    }
    if path.hasPrefix("/") == false {
        path = URL(fileURLWithPath: cwd).appendingPathComponent(path).path
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}

final class FindBar: NSView, NSSearchFieldDelegate {
    let field = NSSearchField()
    let status = NSTextField(labelWithString: "")
    var onFind: ((String, Bool) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let glass = Glass.effect(.hudWindow)
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        field.frame = NSRect(x: 8, y: 6, width: 220, height: 24)
        field.placeholderString = "在回滚里查找"
        field.target = self
        field.action = #selector(submit)
        field.delegate = self
        addSubview(field)
        status.frame = NSRect(x: 236, y: 8, width: 80, height: 18)
        status.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        addSubview(status)
        let close = NSButton(title: "关闭", target: self, action: #selector(closeBar))
        close.bezelStyle = .inline
        close.frame = NSRect(x: 320, y: 6, width: 44, height: 24)
        addSubview(close)
    }

    required init?(coder: NSCoder) { fatalError() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            closeBar()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onFind?(field.stringValue, NSApp.currentEvent?.modifierFlags.contains(.shift) != true)
            return true
        }
        return false
    }

    @objc private func submit() {
        onFind?(field.stringValue, true)
    }

    @objc private func closeBar() { onClose?() }
}
