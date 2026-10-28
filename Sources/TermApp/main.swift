import AppKit
import Darwin
import Security
import SwiftTerm

struct Config: Codable {
    var fontName: String = "Menlo"
    var fontSize: Double = 13
    var foreground: String = "#d4d4d4"
    var background: String = "#1e1e1e"
    var cursor: String = "#d4d4d4"
    var selection: String = "#264f78"
    var opacity: Double = 1
    var shell: String = ""
    var login: Bool = true
    var optionAsMeta: Bool = true
    var env: [String] = []
    var modelBaseUrl: String = ""
    var modelName: String = ""
    var modelApiKey: String = ""
    var themeName: String = "默认"
    var cursorStyle: String = "blinkBlock"
    var lineSpacing: Double = 1.1

    enum CodingKeys: String, CodingKey {
        case fontName, fontSize, foreground, background, cursor, selection, opacity
        case shell, login, optionAsMeta, env, modelBaseUrl, modelName, modelApiKey
        case themeName, cursorStyle, lineSpacing
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? "Menlo"
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        foreground = try c.decodeIfPresent(String.self, forKey: .foreground) ?? "#d4d4d4"
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? "#1e1e1e"
        cursor = try c.decodeIfPresent(String.self, forKey: .cursor) ?? "#d4d4d4"
        selection = try c.decodeIfPresent(String.self, forKey: .selection) ?? "#264f78"
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        shell = try c.decodeIfPresent(String.self, forKey: .shell) ?? ""
        login = try c.decodeIfPresent(Bool.self, forKey: .login) ?? true
        optionAsMeta = try c.decodeIfPresent(Bool.self, forKey: .optionAsMeta) ?? true
        env = try c.decodeIfPresent([String].self, forKey: .env) ?? []
        modelBaseUrl = try c.decodeIfPresent(String.self, forKey: .modelBaseUrl) ?? ""
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        modelApiKey = try c.decodeIfPresent(String.self, forKey: .modelApiKey) ?? ""
        themeName = try c.decodeIfPresent(String.self, forKey: .themeName) ?? "默认"
        cursorStyle = try c.decodeIfPresent(String.self, forKey: .cursorStyle) ?? "blinkBlock"
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 1.1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fontName, forKey: .fontName)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(foreground, forKey: .foreground)
        try c.encode(background, forKey: .background)
        try c.encode(cursor, forKey: .cursor)
        try c.encode(selection, forKey: .selection)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(shell, forKey: .shell)
        try c.encode(login, forKey: .login)
        try c.encode(optionAsMeta, forKey: .optionAsMeta)
        try c.encode(env, forKey: .env)
        try c.encode(modelBaseUrl, forKey: .modelBaseUrl)
        try c.encode(modelName, forKey: .modelName)
        try c.encode(modelApiKey, forKey: .modelApiKey)
        try c.encode(themeName, forKey: .themeName)
        try c.encode(cursorStyle, forKey: .cursorStyle)
        try c.encode(lineSpacing, forKey: .lineSpacing)
    }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-term/config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else {
            var cfg = Config()
            cfg.modelApiKey = Keychain.load()
            return cfg
        }
        var cfg = (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if Keychain.enabled == false {
            cfg.modelApiKey = (obj?["modelApiKey"] as? String) ?? Keychain.load()
        } else if let legacy = obj?["modelApiKey"] as? String {
            Keychain.save(legacy)
            cfg.modelApiKey = legacy
            cfg.save()
        } else {
            cfg.modelApiKey = Keychain.load()
        }
        return cfg
    }

    func save() {
        let dir = Self.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url)
    }
}

enum Keychain {
    // Off while the app is an unsigned debug binary. Each rebuild is a new
    // app to the login keychain, so macOS asks for the login password again.
    // Turn this back on before the release commit.
    static let enabled = false
    static let service = "agent-term"
    static let account = "modelApiKey"

    static func load() -> String {
        if enabled == false { return envFallback() }
        if let key = readSilent(), key.isEmpty == false { return key }
        return envFallback()
    }

    static func save(_ value: String) {
        if enabled == false { return }
        let data = Data(value.utf8)
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        SecItemDelete(base as CFDictionary)
        base[kSecValueData as String] = data
        base[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if let access = anyAppAccess() {
            base[kSecAttrAccess as String] = access
        }
        SecItemAdd(base as CFDictionary, nil)
    }

    private static func readSilent() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    // A rebuilt unsigned binary is a new app to the login keychain. An empty
    // trusted-app list plus no prompt selector lets later builds read the item
    // without asking for the login password again.
    private static func anyAppAccess() -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate("agent-term" as CFString, nil, &access) == errSecSuccess,
              let access else { return nil }
        var list: CFArray?
        guard SecAccessCopyACLList(access, &list) == errSecSuccess,
              let acls = list as? [SecACL] else { return access }
        let prompt = SecKeychainPromptSelector(rawValue: 0)
        for acl in acls {
            SecACLSetContents(acl, nil, "agent-term" as CFString, prompt)
        }
        return access
    }

    private static func envFallback() -> String {
        if let key = ProcessInfo.processInfo.environment["AGENT_API_KEY"], key.isEmpty == false {
            return key
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
        let candidates = [
            exe.appendingPathComponent("../../ppeng-agent-core/.env"),
            exe.deletingLastPathComponent().appendingPathComponent("../ppeng-agent-core/.env"),
        ]
        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                let row = line.trimmingCharacters(in: .whitespaces)
                guard row.hasPrefix("RAW_AGENT_API_KEY=") else { continue }
                let key = String(row.dropFirst("RAW_AGENT_API_KEY=".count))
                if key.isEmpty == false { return key }
            }
        }
        return ""
    }
}

func color(_ hex: String) -> NSColor {
    var n: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&n)
    return NSColor(srgbRed: CGFloat((n >> 16) & 0xff) / 255,
                   green: CGFloat((n >> 8) & 0xff) / 255,
                   blue: CGFloat(n & 0xff) / 255, alpha: 1)
}

func paletteColor(_ hex: String) -> Color? {
    guard hex.count == 7, hex.hasPrefix("#") else { return nil }
    var n: UInt64 = 0
    guard Scanner(string: String(hex.dropFirst())).scanHexInt64(&n), n <= 0xffffff else { return nil }
    return Color(red8: UInt16((n >> 16) & 0xff), green8: UInt16((n >> 8) & 0xff), blue8: UInt16(n & 0xff))
}

struct ThemeFile: Decodable {
    var foreground: String?
    var background: String?
    var cursor: String?
    var selection: String?
    var palette: [String]?
}

func themeFile() -> ThemeFile? {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-term/theme.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(ThemeFile.self, from: data)
}

func vnodeCwd(_ pid: Int32) -> String? {
    guard pid > 0 else { return nil }
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    let raw = withUnsafePointer(to: info.pvi_cdir.vip_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
            String(cString: $0)
        }
    }
    return raw.isEmpty ? nil : raw
}

final class TermPane: NSView {
    let term = AgentTermView(frame: .zero)
    private let badge = NSTextField(labelWithString: "")
    private let mark = PipBoyMark(frame: NSRect(x: 10, y: 10, width: PipBoyMark.side, height: PipBoyMark.side))
    private let crt = CRTOverlay(frame: .zero)
    private var started = false
    private(set) var directory = FileManager.default.currentDirectoryPath

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.systemBlue.cgColor
        term.autoresizingMask = [.width, .height]
        addSubview(term)
        addSubview(crt)
        crt.bind(term)
        term.directory = { [weak self] in self?.liveDirectory() ?? FileManager.default.currentDirectoryPath }
        badge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        badge.textColor = NSColor.systemOrange
        badge.drawsBackground = false
        badge.isBezeled = false
        addSubview(badge)
        addSubview(mark)
        badge.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ cfg: Config) {
        let theme = ThemeCatalog.find(cfg.themeName)
        let fg = theme?.foreground ?? cfg.foreground
        let bg = theme?.background ?? cfg.background
        let caret = theme?.cursor ?? cfg.cursor
        let selection = theme?.selection ?? cfg.selection
        if let font = FontCatalog.terminalFont(cfg.fontName, size: cfg.fontSize) { term.font = font }
        if let theme, ThemeCatalog.colors(theme).count == 16 {
            term.installColors(ThemeCatalog.colors(theme))
        } else if let file = themeFile(), let raw = file.palette, raw.count == 16 {
            let colors = raw.compactMap(paletteColor)
            if colors.count == 16 { term.installColors(colors) }
        }
        term.nativeForegroundColor = color(fg)
        term.nativeBackgroundColor = color(bg)
        term.backgroundOpacity = cfg.opacity
        term.caretColor = color(caret)
        term.selectedTextBackgroundColor = color(selection)
        term.selectedTextForegroundColor = color(fg)
        term.optionAsMetaKey = cfg.optionAsMeta
        term.lineSpacing = CGFloat(cfg.lineSpacing)
        let crtOn = ["辐射", "琥珀", "蓝"].contains(cfg.themeName)
        if crtOn {
            term.terminal.setCursorStyle(.steadyBlock)
        } else if let style = CursorStyle(tagName: cfg.cursorStyle) {
            term.terminal.setCursorStyle(style)
        }
        crt.setEnabled(crtOn)
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        if crtOn {
            crt.setBackground(color(bg))
            crt.setForeground(color(fg))
            try? term.setUseMetal(false)
            term.alphaValue = 1
            term.layer?.opacity = 0
            term.layer?.isOpaque = true
            term.backgroundOpacity = 1
            layer?.borderWidth = 0
        } else if window != nil {
            term.alphaValue = 1
            term.layer?.opacity = 1
            term.backgroundOpacity = min(cfg.opacity, 0.78)
            term.layer?.isOpaque = false
            enableGpu()
        }
        term.needsDisplay = true
        layer?.borderColor = (crtOn
            ? NSColor(srgbRed: 0.02, green: 0.05, blue: 0.02, alpha: 1)
            : NSColor.systemBlue).cgColor
    }

    func start(_ cfg: Config, directory: String? = nil) {
        guard !started, bounds.width > 0, bounds.height > 0 else { return }
        started = true
        self.directory = directory ?? FileManager.default.currentDirectoryPath
        term.frame = bounds
        apply(cfg)
        let shell = cfg.shell.isEmpty ? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") : cfg.shell
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TERM_PROGRAM=agent-term")
        env.append(contentsOf: cfg.env.filter { $0.contains("=") })
        let flag = cfg.login ? "-l" : nil
        term.startProcess(executable: shell, args: [flag].compactMap { $0 }, environment: env,
                          currentDirectory: self.directory)
    }

    func liveDirectory() -> String {
        if let pid = term.process?.shellPid, let path = vnodeCwd(pid) { return path }
        if directory.isEmpty == false { return directory }
        return FileManager.default.currentDirectoryPath
    }

    func focus() { window?.makeFirstResponder(term) }

    func markFocused(_ on: Bool) { layer?.borderWidth = (on && crt.isEnabled == false) ? 1 : 0 }

    func setBadge(_ text: String?) {
        badge.stringValue = text ?? ""
        badge.isHidden = (text ?? "").isEmpty
        needsLayout = true
    }

    // Otty: one GPU layer per pane, dirty rows only. Call after the view is in a window.
    func enableGpu() {
        guard window != nil, term.isUsingMetalRenderer == false, crt.isEnabled == false else { return }
        do {
            try term.setUseMetal(true)
            term.metalBufferingMode = .perRowPersistent
        } catch {
        }
        term.layer?.isOpaque = false
    }

    func screenText() -> String {
        let selected = term.selection.getSelectedText()
        if selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return selected }
        guard let grid = term.terminal, grid.cols > 0, grid.rows > 0 else { return "" }
        return grid.getText(start: Position(col: 0, row: 0),
                            end: Position(col: grid.cols - 1, row: grid.rows - 1))
    }

    private var findBar: FindBar?
    private var findForward = true

    func toggleFind() {
        if findBar == nil {
            let bar = FindBar(frame: NSRect(x: 8, y: bounds.height - 40, width: 372, height: 36))
            bar.onFind = { [weak self] text, forward in self?.runFind(text, forward: forward) }
            bar.onClose = { [weak self] in self?.hideFind() }
            addSubview(bar)
            findBar = bar
        }
        guard let findBar else { return }
        findBar.isHidden = false
        window?.makeFirstResponder(findBar.field)
    }

    func findAgain(forward: Bool) {
        guard let findBar, findBar.field.stringValue.isEmpty == false else {
            toggleFind()
            return
        }
        runFind(findBar.field.stringValue, forward: forward)
    }

    private func hideFind() {
        term.clearSearch()
        findBar?.isHidden = true
        focus()
    }

    private func runFind(_ text: String, forward: Bool) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return }
        let hit = forward ? term.findNext(query) : term.findPrevious(query)
        let summary = term.searchMatchSummary(query)
        findBar?.status.stringValue = hit ? "\(summary.index)/\(summary.total)" : "无"
        findForward = forward
    }

    override func layout() {
        super.layout()
        term.frame = bounds
        crt.frame = bounds
        mark.frame = NSRect(x: 12, y: 12, width: PipBoyMark.side, height: PipBoyMark.side)
        badge.sizeToFit()
        let size = badge.frame.size
        badge.frame = NSRect(x: bounds.width - size.width - 8, y: bounds.height - size.height - 6,
                             width: size.width, height: size.height)
        if let findBar, findBar.isHidden == false {
            findBar.frame = NSRect(x: 8, y: bounds.height - 44, width: min(372, bounds.width - 16), height: 36)
        }
    }
}

final class SplitView: NSView {
    var first: NSView
    var second: NSView
    let sideBySide: Bool
    var ratio: CGFloat = 0.5
    private var dragging = false

    init(first: NSView, second: NSView, sideBySide: Bool) {
        self.first = first
        self.second = second
        self.sideBySide = sideBySide
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        for v in [first, second] {
            v.translatesAutoresizingMaskIntoConstraints = true
            v.autoresizingMask = []
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func divide(_ pane: NSView, with neu: NSView, sideBySide: Bool) {
        let nested = SplitView(first: pane, second: neu, sideBySide: sideBySide)
        if first === pane { first = nested } else { second = nested }
        addSubview(nested)
        needsLayout = true
    }

    func collapse(_ split: SplitView, keep: NSView) {
        if first === split { first = keep } else { second = keep }
        addSubview(keep)
        split.removeFromSuperview()
        needsLayout = true
    }

    private var clampedRatio: CGFloat { min(0.85, max(0.15, ratio)) }

    private func dividerFrame() -> NSRect {
        let gap: CGFloat = 2
        let hit: CGFloat = 6
        let r = clampedRatio
        if sideBySide {
            let w = (bounds.width - gap) * r
            return NSRect(x: w + gap / 2 - hit / 2, y: 0, width: hit, height: bounds.height)
        }
        let top = (bounds.height - gap) * r
        return NSRect(x: 0, y: bounds.height - top - gap / 2 - hit / 2, width: bounds.width, height: hit)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if dividerFrame().contains(local) { return self }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        addCursorRect(dividerFrame(), cursor: sideBySide ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard dividerFrame().contains(p) else { super.mouseDown(with: event); return }
        dragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { super.mouseDragged(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if sideBySide {
            let span = max(bounds.width, 1)
            ratio = min(0.85, max(0.15, p.x / span))
        } else {
            let span = max(bounds.height, 1)
            ratio = min(0.85, max(0.15, (bounds.height - p.y) / span))
        }
        needsLayout = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        super.mouseUp(with: event)
    }

    override func layout() {
        super.layout()
        let gap: CGFloat = 2
        let r = clampedRatio
        if sideBySide {
            if first.isHidden {
                second.frame = bounds
            } else if second.isHidden {
                first.frame = bounds
            } else {
                let w = (bounds.width - gap) * r
                first.frame = NSRect(x: 0, y: 0, width: w, height: bounds.height)
                second.frame = NSRect(x: w + gap, y: 0, width: bounds.width - w - gap, height: bounds.height)
            }
        } else if first.isHidden {
            second.frame = bounds
        } else if second.isHidden {
            first.frame = bounds
        } else {
            let top = (bounds.height - gap) * r
            first.frame = NSRect(x: 0, y: bounds.height - top, width: bounds.width, height: top)
            second.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - top - gap)
        }
    }
}

final class Settings: NSWindowController {
    let cfg: Config
    let onSave: (Config) -> Void
    private let font = NSTextField(string: "")
    private let size = NSTextField(string: "")
    private let fg = NSTextField(string: "")
    private let bg = NSTextField(string: "")
    private let cursor = NSTextField(string: "")
    private let opacity = NSTextField(string: "")
    private let shell = NSTextField(string: "")
    private let env = NSTextField(string: "")
    private let baseUrl = NSTextField(string: "")
    private let modelName = NSTextField(string: "")
    private let apiKey = NSSecureTextField(string: "")
    private let themePopup = NSPopUpButton()
    private let fontPopup = NSPopUpButton()
    private let spacingPopup = NSPopUpButton()
    private let cursorPopup = NSPopUpButton()
    private let login = NSButton(checkboxWithTitle: "登录 shell（读取 .zshrc / .bashrc）", target: nil, action: nil)
    private let meta = NSButton(checkboxWithTitle: "Option 作为 Meta", target: nil, action: nil)

    init(cfg: Config, onSave: @escaping (Config) -> Void) {
        self.cfg = cfg
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 460),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "设置"
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let content = window!.contentView!
        let save = NSButton(title: "保存", target: self, action: #selector(commit))
        save.frame = NSRect(x: 330, y: 12, width: 74, height: 28)
        save.bezelStyle = .rounded
        save.autoresizingMask = [.minXMargin]
        content.addSubview(save)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 48, width: 440, height: 412))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false

        let picks: [(String, NSPopUpButton)] = [
            ("主题", themePopup),
            ("字体", fontPopup),
            ("行高", spacingPopup),
            ("光标", cursorPopup),
        ]
        let rows: [(String, NSTextField, String)] = [
            ("字号", size, String(cfg.fontSize)),
            ("前景色", fg, cfg.foreground),
            ("背景色", bg, cfg.background),
            ("光标色", cursor, cfg.cursor),
            ("透明度", opacity, String(cfg.opacity)),
            ("Shell", shell, cfg.shell),
            ("环境变量", env, cfg.env.joined(separator: " ")),
            ("模型地址", baseUrl, cfg.modelBaseUrl),
            ("模型名", modelName, cfg.modelName),
            ("API Key", apiKey, cfg.modelApiKey),
        ]
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: 440, height: CGFloat(picks.count + rows.count) * 30 + 120))
        var y: CGFloat = 12
        fillPickers()
        for (label, popup) in picks {
            let l = NSTextField(labelWithString: label)
            l.frame = NSRect(x: 16, y: y, width: 70, height: 22)
            popup.frame = NSRect(x: 92, y: y - 2, width: 308, height: 26)
            doc.addSubview(l)
            doc.addSubview(popup)
            y += 30
        }
        let fonts = NSButton(title: "打开字体文件夹", target: self, action: #selector(openFonts))
        fonts.frame = NSRect(x: 92, y: y, width: 140, height: 24)
        fonts.bezelStyle = .rounded
        doc.addSubview(fonts)
        y += 32
        for (label, field, value) in rows {
            let l = NSTextField(labelWithString: label)
            l.frame = NSRect(x: 16, y: y, width: 70, height: 22)
            field.stringValue = value
            field.frame = NSRect(x: 92, y: y, width: 308, height: 22)
            doc.addSubview(l)
            doc.addSubview(field)
            y += 30
        }
        login.state = cfg.login ? .on : .off
        meta.state = cfg.optionAsMeta ? .on : .off
        login.frame = NSRect(x: 92, y: y, width: 308, height: 22)
        meta.frame = NSRect(x: 92, y: y + 26, width: 308, height: 22)
        doc.addSubview(login)
        doc.addSubview(meta)
        scroll.documentView = doc
        content.addSubview(scroll)
    }

    private func fillPickers() {
        themePopup.removeAllItems()
        themePopup.addItem(withTitle: ThemeCatalog.custom)
        ThemeCatalog.all().forEach { themePopup.addItem(withTitle: $0.name) }
        themePopup.selectItem(withTitle: cfg.themeName)
        themePopup.target = self
        themePopup.action = #selector(themePicked)
        fontPopup.removeAllItems()
        let families = FontCatalog.monospacedFamilies()
        fontPopup.addItems(withTitles: families.isEmpty ? [cfg.fontName] : families)
        if fontPopup.itemTitles.contains(cfg.fontName) == false { fontPopup.addItem(withTitle: cfg.fontName) }
        fontPopup.selectItem(withTitle: cfg.fontName)
        spacingPopup.removeAllItems()
        spacingPopup.addItems(withTitles: ["紧凑 1.0", "默认 1.1", "宽松 1.2"])
        spacingPopup.selectItem(at: cfg.lineSpacing < 1.05 ? 0 : (cfg.lineSpacing > 1.15 ? 2 : 1))
        cursorPopup.removeAllItems()
        for style in CursorStyle.allCases { cursorPopup.addItem(withTitle: style.displayName) }
        cursorPopup.selectItem(withTitle: CursorStyle(tagName: cfg.cursorStyle)?.displayName ?? CursorStyle.blinkBlock.displayName)
    }

    @objc private func themePicked() {
        guard let name = themePopup.titleOfSelectedItem, let theme = ThemeCatalog.find(name) else { return }
        fg.stringValue = theme.foreground
        bg.stringValue = theme.background
        cursor.stringValue = theme.cursor
    }

    @objc private func openFonts() {
        FontCatalog.registerDroppedFonts()
        NSWorkspace.shared.open(FontCatalog.folder)
    }

    @objc private func commit() {
        var next = cfg
        next.themeName = themePopup.titleOfSelectedItem ?? cfg.themeName
        next.fontName = fontPopup.titleOfSelectedItem ?? cfg.fontName
        next.fontSize = Double(size.stringValue) ?? cfg.fontSize
        next.lineSpacing = spacingPopup.indexOfSelectedItem == 0 ? 1.0 : (spacingPopup.indexOfSelectedItem == 2 ? 1.2 : 1.1)
        if let title = cursorPopup.titleOfSelectedItem,
           let style = CursorStyle.allCases.first(where: { $0.displayName == title }) {
            next.cursorStyle = style.tagName
        }
        next.foreground = fg.stringValue
        next.background = bg.stringValue
        next.cursor = cursor.stringValue
        if let theme = ThemeCatalog.find(next.themeName) { next.selection = theme.selection }
        next.opacity = min(1, max(0.2, Double(opacity.stringValue) ?? cfg.opacity))
        next.shell = shell.stringValue
        next.env = env.stringValue.split(separator: " ").map(String.init)
        next.modelBaseUrl = baseUrl.stringValue
        next.modelName = modelName.stringValue
        next.modelApiKey = apiKey.stringValue
        next.login = login.state == .on
        next.optionAsMeta = meta.state == .on
        Keychain.save(next.modelApiKey)
        next.save()
        onSave(next)
        window?.close()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var cfg = Config.load()
    var window: NSWindow!
    private var monitor: Any?
    private var settings: Settings?
    private let palette = CommandPalette()
    private var shell: ShellView!
    private var closedPanes: [TermPane] = []
    private var closedDirs: [String] = []
    private var zoomHidden: [NSView] = []
    private var quick: NSPanel?
    private var commandBlocks: [CommandBlock] = []
    private var blockTimer: Timer?
    private var blockTargets: [UUID: TermPane] = [:]
    private var blockScreens: [UUID: String] = [:]
    private var blockQuiet: [UUID: Int] = [:]
    private enum GroupMode { case none, project, date }
    private enum OrderMode { case created, updated }
    private var groupMode: GroupMode = .project
    private var orderMode: OrderMode = .created
    private var collapsedGroups = Set<String>()
    private var groupOrder: [String] = []
    private var groupAliases: [String: String] = [:]
    private struct ShelfPane {
        let id: ObjectIdentifier
        weak var pane: TermPane?
        weak var win: NSWindow?
        var groupKey: String
        var title: String
    }
    private var shelf: [ShelfPane] = []
    private var createdAt: [ObjectIdentifier: Date] = [:]
    private var updatedAt: [ObjectIdentifier: Date] = [:]
    private let tabGroups = TabGroupStore()
    private var sessionToken: [ObjectIdentifier: UUID] = [:]
    private var customTitles: [ObjectIdentifier: String] = [:]
    private var pinnedSessions = Set<ObjectIdentifier>()
    private var pinnedGroups = Set<UUID>()
    private var turns: [(String, String)] = []
    private var promptQueue: [String] = []
    private var attachment: String?
    private var running = false
    private var agentTask: Process?
    private var activityBuf = ""
    private var activityQueued = false
    private let activityLock = NSLock()
    private var askFiles: [String: (URL, String)] = [:]
    private var badgeText: String?
    private static let askLock = NSLock()
    private static var asking = Set<String>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = openTerminal(directory: nil, tabbed: false)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()
        applyLook()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        if win.identifier?.rawValue == "quick-terminal" { return }
        if win.identifier?.rawValue != "agent-term" { return }
        forgetSession(win)
        if let dir = focusedPane(in: win)?.liveDirectory() { closedDirs.append(dir) }
        let others = NSApp.windows.filter { $0 !== win && $0.identifier?.rawValue == "agent-term" }
        if others.isEmpty {
            agentTask?.terminate()
            closedPanes.forEach { $0.term.terminate() }
            if let monitor { NSEvent.removeMonitor(monitor) }
            NSApplication.shared.terminate(nil)
            return
        }
        if win === window { adopt(others[0]) }
        reloadSidebars()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        if win.identifier?.rawValue == "agent-term" || win.identifier?.rawValue == "quick-terminal" {
            adopt(win)
            if win.identifier?.rawValue == "agent-term" {
                noteSession(win)
                reloadSidebars()
            }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if let source = event.window {
            let id = source.identifier?.rawValue
            if id == "agent-term" || id == "quick-terminal" { adopt(source) }
            else if source !== window { return event }
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        guard flags.contains(.command) else { return event }
        if event.keyCode == 36 {
            if flags.contains(.option) { queueComposer(); return nil }
            if flags.contains(.control) { attachScreen(); return nil }
            submitComposer(forceQueue: false)
            return nil
        }
        if key == "d" || key == "w" || key == "," || key == "k" { return event }
        if flags == .command, let n = Int(key), (1...9).contains(n), window.firstResponder is NSTextView == false {
            jumpSession(n)
            return nil
        }
        if key == "p" && flags.contains(.shift) { return event }
        if key == "=" || key == "+" || key == "-" || key == "0" { return event }
        if flags.contains(.option) {
            switch event.keyCode {
            case 123: focus(dx: -1, dy: 0); return nil
            case 124: focus(dx: 1, dy: 0); return nil
            case 125: focus(dx: 0, dy: -1); return nil
            case 126: focus(dx: 0, dy: 1); return nil
            default: break
            }
        }
        return event
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(item("设置…", #selector(showSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出", #selector(NSApplication.terminate(_:)), "q"))

        let agentItem = NSMenuItem()
        main.addItem(agentItem)
        let agentMenu = NSMenu(title: "Agent")
        agentItem.submenu = agentMenu
        agentMenu.addItem(item("打开对话", #selector(focusAgent), "k"))
        let send = item("发给 Agent", #selector(sendToAgent), "\r")
        agentMenu.addItem(send)
        let queued = item("排队", #selector(queueToAgent), "\r")
        queued.keyEquivalentModifierMask = [.command, .option]
        agentMenu.addItem(queued)
        let attach = item("附上当前屏幕", #selector(attachScreenMenu), "\r")
        attach.keyEquivalentModifierMask = [.command, .control]
        agentMenu.addItem(attach)

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: "视图")
        viewItem.submenu = view
        let paletteItem = item("命令面板…", #selector(showPalette), "p")
        paletteItem.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(paletteItem)
        view.addItem(item("放大字号", #selector(zoomIn), "="))
        view.addItem(item("缩小字号", #selector(zoomOut), "-"))
        view.addItem(item("重置字号", #selector(zoomReset), "0"))
        let themes = NSMenu(title: "主题")
        let themeItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        for theme in ThemeCatalog.all() {
            let it = NSMenuItem(title: theme.name, action: #selector(pickTheme(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = theme.name
            themes.addItem(it)
        }
        view.addItem(themeItem)
        view.addItem(.separator())
        view.addItem(item("查找", #selector(showFind), "f"))
        view.addItem(item("查找下一个", #selector(findNextItem), "g"))
        let prev = item("查找上一个", #selector(findPreviousItem), "g")
        prev.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(prev)
        let full = item("进入全屏", #selector(toggleFullScreen), "f")
        full.keyEquivalentModifierMask = [.command, .control]
        view.addItem(full)

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        editItem.submenu = edit
        edit.addItem(responderItem("拷贝", #selector(NSText.copy(_:)), "c"))
        edit.addItem(responderItem("粘贴", #selector(NSText.paste(_:)), "v"))
        edit.addItem(responderItem("全选", #selector(NSText.selectAll(_:)), "a"))

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let win = NSMenu(title: "窗口")
        winItem.submenu = win
        win.addItem(item("新建窗口", #selector(newWindow), "n"))
        win.addItem(item("新建标签", #selector(newTab), "t"))
        win.addItem(item("新建分组", #selector(newNamedGroup), ""))
        let side = item("标签侧栏", #selector(toggleSidebar), "l")
        side.keyEquivalentModifierMask = [.command, .shift]
        win.addItem(side)
        let blocksItem = item("块状界面", #selector(toggleBlocks), "b")
        blocksItem.keyEquivalentModifierMask = [.command, .shift]
        win.addItem(blocksItem)
        let reopen = item("重新打开", #selector(reopenClosed), "t")
        reopen.keyEquivalentModifierMask = [.command, .shift]
        win.addItem(reopen)
        let closeWin = item("关闭窗口", #selector(closeWindow), "w")
        closeWin.keyEquivalentModifierMask = [.command, .shift]
        win.addItem(closeWin)
        win.addItem(.separator())
        win.addItem(item("左右分屏", #selector(splitSideBySide), "d"))
        let stack = item("上下分屏", #selector(splitStacked), "d")
        stack.keyEquivalentModifierMask = [.command, .shift]
        win.addItem(stack)
        win.addItem(item("关闭面板", #selector(closePane), "w"))
        let zoomPane = item("缩放面板", #selector(togglePaneZoom), "\r")
        zoomPane.keyEquivalentModifierMask = [.command, .shift]
        win.addItem(zoomPane)
        let equal = item("均分面板", #selector(equalizeSplits), "=")
        equal.keyEquivalentModifierMask = [.command, .control]
        win.addItem(equal)
        win.addItem(item("下一个面板", #selector(focusNextPane), "]"))
        win.addItem(item("上一个面板", #selector(focusPrevPane), "["))
        win.addItem(arrowItem("焦点左", #selector(focusLeft), NSLeftArrowFunctionKey))
        win.addItem(arrowItem("焦点右", #selector(focusRight), NSRightArrowFunctionKey))
        win.addItem(arrowItem("焦点下", #selector(focusDown), NSDownArrowFunctionKey))
        win.addItem(arrowItem("焦点上", #selector(focusUp), NSUpArrowFunctionKey))
        let quickItem = item("快速终端", #selector(toggleQuick), "`")
        quickItem.keyEquivalentModifierMask = [.command, .control]
        win.addItem(quickItem)
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    private func responderItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = nil
        return it
    }

    private func arrowItem(_ title: String, _ action: Selector, _ key: Int) -> NSMenuItem {
        let it = item(title, action, String(UnicodeScalar(key)!))
        it.keyEquivalentModifierMask = [.command, .option]
        return it
    }

    @objc private func showSettings() { openSettings() }

    @objc private func runAgent() { focusAgent() }
    @objc private func focusAgent() { showDockAndFocus() }
    @objc private func sendToAgent() { submitComposer(forceQueue: false) }
    @objc private func queueToAgent() { queueComposer() }
    @objc private func attachScreenMenu() { attachScreen() }

    @objc func splitSideBySide() { split(sideBySide: true) }

    @objc func splitStacked() { split(sideBySide: false) }

    @objc func closePane() { closeFocused() }

    @objc func focusLeft() { focus(dx: -1, dy: 0) }

    @objc func focusRight() { focus(dx: 1, dy: 0) }

    @objc func focusDown() { focus(dx: 0, dy: -1) }

    @objc func focusUp() { focus(dx: 0, dy: 1) }

    private func wireDock() {
        shell.dock.setModel(cfg.modelName.isEmpty ? "未配置模型" : cfg.modelName)
        shell.dock.setModelFields(url: cfg.modelBaseUrl, name: cfg.modelName, key: cfg.modelApiKey)
        shell.dock.onSaveModel = { [weak self] url, name, key in
            guard let self else { return }
            self.cfg.modelBaseUrl = url
            self.cfg.modelName = name
            self.cfg.modelApiKey = key
            self.cfg.save()
            self.shell.dock.setModel(name.isEmpty ? "未配置模型" : name)
        }
        shell.dock.onSend = { [weak self] in self?.submitComposer(forceQueue: false) }
        shell.dock.onQueue = { [weak self] in self?.queueComposer() }
        shell.dock.onAttach = { [weak self] in self?.attachScreen() }
        shell.dock.onHide = { [weak self] in
            self?.shell.setDockVisible(false)
            self?.refreshHint()
        }
        shell.dock.onApprove = { [weak self] id, allow in self?.finishApproval(id, allow: allow) }
        shell.blocks.onSubmit = { [weak self] text in self?.submitBlock(text) }
        shell.blocks.onRerun = { [weak self] text in self?.submitBlock(text) }
    }

    private func showDockAndFocus() {
        shell.setDockVisible(true)
        window.layoutIfNeeded()
        shell.dock.focusComposer()
        refreshHint()
    }

    private func queueComposer() {
        showDockAndFocus()
        submitComposer(forceQueue: true)
    }

    private func submitComposer(forceQueue: Bool) {
        let text = shell.dock.composerText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { showDockAndFocus(); return }
        guard cfg.modelBaseUrl.isEmpty == false, cfg.modelName.isEmpty == false else {
            showDockAndFocus()
            openSettings()
            return
        }
        showDockAndFocus()
        if forceQueue || running {
            promptQueue.append(text)
            shell.dock.clearComposer()
            shell.dock.setQueue(promptQueue.count)
            shell.dock.append("排队", text)
            return
        }
        shell.dock.clearComposer()
        startRun(text)
    }

    private func startRun(_ text: String) {
        running = true
        turns.append(("你", text))
        shell.dock.append("你", text)
        if attachment != nil { shell.dock.append("上下文", "附上了当前终端内容") }
        shell.dock.setState("运行中", color: .systemBlue)
        setBadges("运行中")
        refreshHint()
        let prompt = assembled(text)
        attachment = nil
        shell.dock.setAttachment(nil)
        let cfg = self.cfg
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let reply = self?.run(prompt, cfg: cfg) ?? "agent 已取消"
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = false
                self.agentTask = nil
                self.turns.append(("Agent", reply))
                self.shell.dock.append("Agent", reply)
                self.shell.dock.setState("空闲", color: NSColor.white.withAlphaComponent(0.7))
                self.setBadges(nil)
                self.refreshHint()
                if self.window.isKeyWindow == false { NSApp.requestUserAttention(.informationalRequest) }
                self.drainQueue()
            }
        }
    }

    private func drainQueue() {
        guard running == false, promptQueue.isEmpty == false else { return }
        let next = promptQueue.removeFirst()
        shell.dock.setQueue(promptQueue.count)
        startRun(next)
    }

    private func assembled(_ ask: String) -> String {
        var parts: [String] = []
        if let cwd = focusedPane()?.liveDirectory() { parts.append("当前面板目录: \(cwd)") }
        if let attachment, attachment.isEmpty == false {
            parts.append("附上的终端内容:\n\(attachment.prefix(4000))")
        }
        if turns.count > 1 {
            let prior = turns.dropLast().suffix(6).map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            parts.append("之前的对话:\n\(prior)")
        }
        parts.append("这次要做的事:\n\(ask)")
        return parts.joined(separator: "\n\n")
    }

    private func attachScreen() {
        guard let pane = focusedPane() else { return }
        let text = pane.screenText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        attachment = String(text.prefix(4000))
        let lines = attachment?.split(separator: "\n").count ?? 0
        shell.setDockVisible(true)
        shell.dock.setAttachment("屏幕 · \(lines) 行")
        shell.dock.focusComposer()
        refreshHint()
    }

    func presentApproval(id: String, line: String, dir: URL) {
        askFiles[id] = (dir, line)
        shell.setDockVisible(true)
        shell.dock.showApproval(id: id, command: line)
        shell.dock.setState("等你批", color: .systemOrange)
        setBadges("等你批")
        refreshHint()
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func finishApproval(_ id: String, allow: Bool) {
        guard let (dir, line) = askFiles.removeValue(forKey: id) else { return }
        let body = allow ? "allow" : "deny"
        let tmp = dir.appendingPathComponent(id + ".res.tmp")
        let res = dir.appendingPathComponent(id + ".res")
        try? body.write(to: tmp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: res.path) {
            _ = try? FileManager.default.replaceItemAt(res, withItemAt: tmp)
        }
        if FileManager.default.fileExists(atPath: tmp.path) {
            try? FileManager.default.moveItem(at: tmp, to: res)
        }
        shell.dock.clearApproval()
        shell.dock.append(allow ? "已允许" : "已拒绝", line)
        shell.dock.setState("运行中", color: .systemBlue)
        setBadges("运行中")
        refreshHint()
    }

    private func noteActivity(_ chunk: String) {
        let useful = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            line.hasPrefix("KEYS ") == false && line.hasPrefix("MSG ") == false && line.hasPrefix("preset ") == false
        }.joined(separator: "\n")
        guard useful.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        activityLock.lock()
        activityBuf += useful
        let schedule = activityQueued == false
        activityQueued = true
        activityLock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activityLock.lock()
            let text = self.activityBuf
            self.activityBuf = ""
            self.activityQueued = false
            self.activityLock.unlock()
            if text.isEmpty == false { self.shell.dock.append("过程", text) }
        }
    }

    private func run(_ prompt: String, cfg: Config) -> String {
        let root = repoRoot()
        let script = root + "/agent/run.mjs"
        let core = root + "/../ppeng-agent-core"
        let askDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-term/ask")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: askDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: askDir) }

        let task = Process()
        agentTask = task
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["node", script, cfg.modelBaseUrl, cfg.modelName, prompt, root]
        var env = ProcessInfo.processInfo.environment
        env["AGENT_API_KEY"] = cfg.modelApiKey
        env["AGENT_CORE"] = core + "/packages/agent-loop/dist/"
        env["AGENT_ASK_DIR"] = askDir.path
        let gate = root + "/.build-direct/headless/gate"
        if FileManager.default.fileExists(atPath: gate) { env["AGENT_GATE"] = gate }
        task.environment = env
        task.currentDirectoryURL = URL(fileURLWithPath: core)
        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do { try task.run() } catch { return "agent 启动失败：\(error)" }

        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            lock.lock(); outData.append(chunk); lock.unlock()
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            lock.lock(); errData.append(chunk); lock.unlock()
            if let text = String(data: chunk, encoding: .utf8) { self?.noteActivity(text) }
        }
        let poll = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        poll.schedule(deadline: .now(), repeating: .milliseconds(100))
        poll.setEventHandler { pollAsks(askDir) }
        poll.resume()
        task.waitUntilExit()
        poll.cancel()
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        outData.append(out.fileHandleForReading.readDataToEndOfFile())
        errData.append(err.fileHandleForReading.readDataToEndOfFile())
        lock.unlock()
        let text = String(data: outData, encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            let why = String(data: errData, encoding: .utf8) ?? ""
            return "agent 失败：\(why.isEmpty ? text : why)"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshHint() {
        let gpu = focusedPane()?.term.isUsingMetalRenderer == true ? "GPU" : "CPU"
        let face = focusedPane()?.term.font.familyName ?? cfg.fontName
        let look = "\(cfg.themeName) · \(face) \(Int(cfg.fontSize))"
        if running {
            shell.host.hint.stringValue = "\(gpu) · \(look) · Agent 运行中"
        } else if shell.showDock {
            shell.host.hint.stringValue = "\(gpu) · \(look) · ⌘↩ 发送 · ⌘⇧P 命令"
        } else {
            shell.host.hint.stringValue = "\(gpu) · \(look) · ⌘K 打开 Agent"
        }
    }

    private func setBadges(_ text: String?) {
        badgeText = text
        let cur = focusedPane()
        for pane in allPanes() { pane.setBadge(pane === cur ? text : nil) }
    }

    private func repoRoot() -> String {
        let exe = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        var dir = (exe as NSString).deletingLastPathComponent
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir + "/agent/run.mjs") { return dir }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        let cwd = FileManager.default.currentDirectoryPath
        if FileManager.default.fileExists(atPath: cwd + "/agent/run.mjs") { return cwd }
        return cwd
    }

    private func applyLook() {
        Glass.install(window)
        shell.host.layer?.backgroundColor = NSColor.clear.cgColor
        for pane in allPanes() { pane.apply(cfg) }
        let theme = ThemeCatalog.find(cfg.themeName)
        shell.applyChrome(
            foreground: color(theme?.foreground ?? cfg.foreground),
            background: color(theme?.background ?? cfg.background),
            accent: color(theme?.cursor ?? cfg.cursor)
        )
        refreshHint()
    }

    @objc private func showPalette() {
        var actions: [(String, () -> Void)] = [
            ("设置", { [weak self] in self?.openSettings() }),
            ("打开 Agent 对话", { [weak self] in self?.focusAgent() }),
            ("块状模式", { [weak self] in self?.setBlockMode(true) }),
            ("终端模式", { [weak self] in self?.setBlockMode(false) }),
            ("左右分屏", { [weak self] in self?.split(sideBySide: true) }),
            ("上下分屏", { [weak self] in self?.split(sideBySide: false) }),
            ("放大字号", { [weak self] in self?.zoom(by: 1) }),
            ("缩小字号", { [weak self] in self?.zoom(by: -1) }),
            ("重置字号", { [weak self] in self?.zoom(by: 0) }),
            ("附上当前屏幕", { [weak self] in self?.attachScreen() }),
        ]
        for theme in ThemeCatalog.all() {
            actions.append(("主题 \(theme.name)", { [weak self] in self?.useTheme(theme.name) }))
        }
        palette.present(actions)
    }

    @objc private func zoomIn() { zoom(by: 1) }
    @objc private func zoomOut() { zoom(by: -1) }
    @objc private func zoomReset() { zoom(by: 0) }

    private func zoom(by delta: Double) {
        cfg.fontSize = delta == 0 ? 13 : min(28, max(9, cfg.fontSize + delta))
        cfg.save()
        applyLook()
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        useTheme(name)
    }

    private func useTheme(_ name: String) {
        guard let theme = ThemeCatalog.find(name) else { return }
        cfg.themeName = theme.name
        cfg.foreground = theme.foreground
        cfg.background = theme.background
        cfg.cursor = theme.cursor
        cfg.selection = theme.selection
        cfg.save()
        applyLook()
    }

    private func openSettings() {
        let panel = Settings(cfg: cfg) { [weak self] next in
            guard let self else { return }
            self.cfg = next
            self.applyLook()
        }
        settings = panel
        panel.showWindow(nil)
    }

    private var splitting = false
    private var lastSplitAt: TimeInterval = 0

    private func split(sideBySide: Bool) {
        if shell.showBlocks { setBlockMode(false) }
        let now = ProcessInfo.processInfo.systemUptime
        guard splitting == false, now - lastSplitAt > 0.05 else { return }
        splitting = true
        lastSplitAt = now
        defer { splitting = false }
        guard let pane = focusedPane() ?? shell.host.shown ?? firstPane(in: shell.host), let parent = pane.superview else { return }
        let neu = TermPane(frame: pane.frame)
        if let parent = parent as? SplitView {
            parent.divide(pane, with: neu, sideBySide: sideBySide)
        } else if let host = parent as? TerminalHost {
            let split = SplitView(first: pane, second: neu, sideBySide: sideBySide)
            host.setRoot(split)
        } else {
            let split = SplitView(first: pane, second: neu, sideBySide: sideBySide)
            split.frame = pane.frame
            split.autoresizingMask = [.width, .height]
            parent.addSubview(split)
        }
        window.contentView!.layoutSubtreeIfNeeded()
        neu.start(cfg, directory: pane.liveDirectory())
        neu.enableGpu()
        neu.focus()
        markFocus()
    }

    private func closeFocused() {
        guard let pane = focusedPane() else { return }
        closedDirs.append(pane.liveDirectory())
        guard let split = pane.superview as? SplitView else {
            pane.removeFromSuperview()
            stash(pane)
            window.close()
            return
        }
        let keep = split.first === pane ? split.second : split.first
        pane.removeFromSuperview()
        stash(pane)
        if let parent = split.superview as? SplitView {
            parent.collapse(split, keep: keep)
        } else if let host = split.superview as? TerminalHost {
            host.setRoot(keep)
        } else {
            split.removeFromSuperview()
            keep.frame = window.contentView!.bounds
            keep.autoresizingMask = [.width, .height]
            window.contentView!.addSubview(keep)
        }
        window.contentView!.layoutSubtreeIfNeeded()
        firstPane(in: keep)?.focus()
        markFocus()
    }

    private func stash(_ pane: TermPane) {
        closedPanes.append(pane)
        if closedPanes.count > 6 {
            closedPanes.removeFirst().term.terminate()
        }
    }

    private func focus(dx: CGFloat, dy: CGFloat) {
        guard let cur = focusedPane() else { return }
        let c = center(cur)
        let pick = allPanes().filter { $0 !== cur }.filter { p in
            let o = center(p)
            if dx != 0 { return dx > 0 ? o.x > c.x + 8 : o.x < c.x - 8 }
            return dy > 0 ? o.y > c.y + 8 : o.y < c.y - 8
        }.min { a, b in
            hypot(center(a).x - c.x, center(a).y - c.y) < hypot(center(b).x - c.x, center(b).y - c.y)
        }
        pick?.focus()
        markFocus()
    }

    private func focusedPane() -> TermPane? { focusedPane(in: window) }

    private func focusedPane(in win: NSWindow) -> TermPane? {
        var view = win.firstResponder as? NSView
        while let cur = view {
            if let pane = cur as? TermPane { return pane }
            view = cur.superview
        }
        return panes(in: win).first
    }

    private func allPanes() -> [TermPane] { panes(in: window) }

    private func panes(in win: NSWindow) -> [TermPane] {
        guard let root = win.contentView else { return [] }
        var found: [TermPane] = []
        func walk(_ view: NSView) {
            if let pane = view as? TermPane { found.append(pane) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    private func firstPane(in view: NSView) -> TermPane? {
        if let pane = view as? TermPane { return pane }
        for sub in view.subviews { if let pane = firstPane(in: sub) { return pane } }
        return nil
    }

    private func center(_ pane: TermPane) -> NSPoint {
        let r = pane.convert(pane.bounds, to: nil)
        return NSPoint(x: r.midX, y: r.midY)
    }

    private func markFocus() {
        let cur = focusedPane()
        for pane in allPanes() {
            pane.markFocused(pane === cur)
            pane.setBadge(pane === cur ? badgeText : nil)
        }
        if let dir = cur?.liveDirectory() {
            window.representedURL = URL(fileURLWithPath: dir)
            window.title = URL(fileURLWithPath: dir).lastPathComponent
        }
        reloadSidebars()
    }

    private func adopt(_ win: NSWindow) {
        guard let host = win.contentView?.subviews.compactMap({ $0 as? ShellView }).first else { return }
        window = win
        shell = host
        host.onMode = { [weak self] on in self?.setBlockMode(on) }
    }

    @discardableResult
    private func openTerminal(directory: String?, tabbed: Bool) -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "agent-term"
        win.identifier = NSUserInterfaceItemIdentifier("agent-term")
        win.tabbingMode = .disallowed
        win.delegate = self
        Glass.install(win)
        let host = ShellView(frame: win.contentView!.bounds)
        host.autoresizingMask = [.width, .height]
        host.showSidebar = true
        win.contentView!.addSubview(host)
        if tabbed, let current = NSApp.keyWindow, current.identifier?.rawValue == "agent-term" {
            win.setFrame(current.frame, display: false)
        }
        adopt(win)
        wireDock()
        wireSidebar(host)
        let pane = TermPane(frame: host.host.bounds)
        host.host.setRoot(pane)
        win.makeKeyAndOrderFront(nil)
        adopt(win)
        win.layoutIfNeeded()
        pane.start(cfg, directory: directory ?? focusedPane(in: win)?.liveDirectory())
        pane.enableGpu()
        pane.focus()
        refreshHint()
        noteSession(win)
        reloadSidebars()
        return win
    }

    @objc func newWindow() { _ = openTerminal(directory: focusedPane()?.liveDirectory(), tabbed: false) }
    @objc func newTab() { _ = openTerminal(directory: focusedPane()?.liveDirectory(), tabbed: true) }
    @objc func closeWindow() { window.close() }
    @objc func showFind() { focusedPane()?.toggleFind() }
    @objc func findNextItem() { focusedPane()?.findAgain(forward: true) }
    @objc func findPreviousItem() { focusedPane()?.findAgain(forward: false) }
    @objc func toggleFullScreen() { window.toggleFullScreen(nil) }

    @objc func focusNextPane() { cyclePane(forward: true) }
    @objc func focusPrevPane() { cyclePane(forward: false) }

    private func cyclePane(forward: Bool) {
        let panes = allPanes()
        guard panes.isEmpty == false else { return }
        let index = panes.firstIndex { $0 === focusedPane() } ?? 0
        let next = (index + (forward ? 1 : panes.count - 1)) % panes.count
        panes[next].focus()
        markFocus()
    }

    @objc func equalizeSplits() {
        func walk(_ view: NSView) {
            if let split = view as? SplitView {
                split.ratio = 0.5
                split.needsLayout = true
            }
            view.subviews.forEach(walk)
        }
        if let root = window.contentView { walk(root) }
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @objc func togglePaneZoom() {
        if zoomHidden.isEmpty == false {
            zoomHidden.forEach { $0.isHidden = false }
            zoomHidden.removeAll()
            window.contentView?.layoutSubtreeIfNeeded()
            return
        }
        guard let pane = focusedPane() else { return }
        var node: NSView = pane
        while let parent = node.superview as? SplitView {
            let inFirst = parent.first === node || node.isDescendant(of: parent.first)
            let sib = inFirst ? parent.second : parent.first
            if sib.isHidden == false {
                sib.isHidden = true
                zoomHidden.append(sib)
            }
            node = parent
        }
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @objc func reopenClosed() {
        if let pane = closedPanes.popLast() {
            if let cur = focusedPane(), let parent = cur.superview as? SplitView {
                parent.divide(cur, with: pane, sideBySide: true)
            } else if let cur = focusedPane(), let host = cur.superview as? TerminalHost {
                host.setRoot(SplitView(first: cur, second: pane, sideBySide: true))
            } else {
                shell.host.setRoot(pane)
            }
            window.contentView?.layoutSubtreeIfNeeded()
            pane.focus()
            markFocus()
            return
        }
        guard let dir = closedDirs.popLast() else { return }
        _ = openTerminal(directory: dir, tabbed: true)
    }

    @objc func toggleQuick() {
        if let quick, quick.isVisible {
            quick.orderOut(nil)
            NSApp.windows.last { $0.identifier?.rawValue == "agent-term" }?.makeKeyAndOrderFront(nil)
            return
        }
        if quick == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 420),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.title = "快速终端"
            panel.identifier = NSUserInterfaceItemIdentifier("quick-terminal")
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            Glass.install(panel)
            let host = ShellView(frame: panel.contentView!.bounds)
            host.autoresizingMask = [.width, .height]
            host.showSidebar = false
            panel.contentView!.addSubview(host)
            adopt(panel)
            wireDock()
            let pane = TermPane(frame: host.host.bounds)
            host.host.setRoot(pane)
            if let screen = NSScreen.main?.visibleFrame {
                panel.setFrame(NSRect(x: screen.midX - 450, y: screen.maxY - 440, width: 900, height: 420), display: false)
            }
            panel.layoutIfNeeded()
            pane.start(cfg, directory: focusedPane()?.liveDirectory())
            pane.enableGpu()
            quick = panel
        }
        quick?.makeKeyAndOrderFront(nil)
        if let quick { adopt(quick) }
        panes(in: quick!).first?.focus()
    }

    private func wireSidebar(_ host: ShellView) {
        host.sidebar.onNew = { [weak self] in self?.newTab() }
        host.sidebar.onNewGroup = { [weak self] in self?.newNamedGroup() }
        host.sidebar.onSelect = { [weak self] id in self?.selectSession(id) }
        host.sidebar.onClose = { [weak self] id in self?.closeSession(id) }
        host.sidebar.onFilter = { [weak self] view in self?.popSidebarMenu(view) }
        host.sidebar.onToggle = { [weak self] key in
            guard let self else { return }
            if self.collapsedGroups.contains(key) { self.collapsedGroups.remove(key) }
            else { self.collapsedGroups.insert(key) }
            self.reloadSidebars()
        }
        host.sidebar.onRenameGroup = { [weak self] key, name in self?.renameGroup(key, to: name) }
        host.sidebar.onNewInGroup = { [weak self] key in self?.newInGroup(key) }
        host.sidebar.onGroupMenu = { [weak self] key, view in self?.popGroupMenu(key, view) }
        host.sidebar.onTabMenu = { [weak self] id, view in self?.popTabMenu(id, view) }
        host.sidebar.onRenameTab = { [weak self] id, name in self?.renameTab(id, to: name) }
        host.sidebar.onReorder = { [weak self] key, index in self?.moveGroup(key, to: index) }
        host.sidebar.onCollapseSidebar = { [weak host] in host?.setSidebarVisible(false) }
    }

    @objc func toggleSidebar() {
        shell.setSidebarVisible(shell.showSidebar == false)
    }

    @objc func toggleBlocks() {
        setBlockMode(shell.showBlocks == false)
    }

    private func setBlockMode(_ on: Bool) {
        shell.setBlocksVisible(on)
        if on { shell.blocks.setBlocks(commandBlocks) }
        window.layoutIfNeeded()
        if on {
            shell.blocks.focusInput()
        } else {
            (shell.host.shown ?? focusedPane())?.focus()
        }
    }

    private func submitBlock(_ command: String) {
        let wrapped = BlockFeed.wrapped(command)
        guard wrapped.isEmpty == false else { return }
        guard let pane = shell.host.shown ?? focusedPane() else { return }
        pane.term.send(txt: wrapped)
        let block = CommandBlock(
            id: UUID(),
            command: command,
            output: "",
            exitCode: nil,
            cwd: pane.liveDirectory(),
            running: true
        )
        commandBlocks.append(block)
        blockTargets[block.id] = pane
        shell.blocks.setBlocks(commandBlocks)
        guard blockTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            self?.pollBlocks(timer)
        }
        blockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pollBlocks(_ timer: Timer) {
        var running = false
        var changed = false
        for index in commandBlocks.indices where commandBlocks[index].running {
            let id = commandBlocks[index].id
            guard let pane = blockTargets[id] ?? shell.host.shown ?? focusedPane() else { continue }
            let screen = pane.screenText()
            let result = BlockFeed.output(from: screen, command: commandBlocks[index].command)
            if screen == blockScreens[id] { blockQuiet[id, default: 0] += 1 } else { blockQuiet[id] = 0 }
            blockScreens[id] = screen
            let stalled = (blockQuiet[id] ?? 0) >= 8 && result.done == false
            let nextRunning = result.done == false && stalled == false
            if result.text != commandBlocks[index].output || result.exit != commandBlocks[index].exitCode || nextRunning != commandBlocks[index].running {
                changed = true
            }
            commandBlocks[index].output = result.text
            commandBlocks[index].exitCode = result.exit
            commandBlocks[index].running = nextRunning
            if nextRunning {
                running = true
            } else {
                blockTargets[id] = nil
                blockScreens[id] = nil
                blockQuiet[id] = nil
            }
        }
        if changed, shell.showBlocks { shell.blocks.setBlocks(commandBlocks) }
        if running == false {
            timer.invalidate()
            blockTimer = nil
        }
    }

    private func noteSession(_ win: NSWindow) {
        let id = ObjectIdentifier(win)
        if createdAt[id] == nil { createdAt[id] = Date() }
        updatedAt[id] = Date()
        if sessionToken[id] == nil { sessionToken[id] = UUID() }
    }

    private func forgetSession(_ win: NSWindow) {
        let id = ObjectIdentifier(win)
        if let token = sessionToken.removeValue(forKey: id) {
            tabGroups.remove(token)
        }
        customTitles.removeValue(forKey: id)
        pinnedSessions.remove(id)
    }

    private func sessions() -> [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue == "agent-term" }
    }

    private func selectSession(_ id: ObjectIdentifier) {
        if let item = shelf.first(where: { $0.id == id }), let pane = item.pane, let win = item.win {
            collapsedGroups.remove(item.groupKey)
            win.makeKeyAndOrderFront(nil)
            adopt(win)
            host(of: win)?.show(pane)
            pane.focus()
            reloadSidebars()
            return
        }
        guard let win = sessions().first(where: { ObjectIdentifier($0) == id }) else { return }
        if let token = sessionToken[id], let gid = tabGroups.groupID(of: token) {
            collapsedGroups.remove("group:\(gid)")
        }
        win.makeKeyAndOrderFront(nil)
        adopt(win)
        host(of: win)?.showFirst()
        focusedPane()?.focus()
        reloadSidebars()
    }

    private func closeSession(_ id: ObjectIdentifier) {
        if let i = shelf.firstIndex(where: { $0.id == id }) {
            shelf[i].pane?.removeFromSuperview()
            if let win = shelf[i].win { host(of: win)?.showFirst() }
            shelf.remove(at: i)
            reloadSidebars()
            return
        }
        sessions().first { ObjectIdentifier($0) == id }?.close()
    }

    private func host(of win: NSWindow) -> TerminalHost? {
        win.contentView?.subviews.compactMap { $0 as? ShellView }.first?.host
    }

    private func appendShelf(in win: NSWindow, key: String, rows: inout [SideRow], index: inout Int) {
        for item in shelf where item.win === win && item.groupKey == key && item.pane != nil {
            let title = customTitles[item.id] ?? item.title
            let active = item.pane != nil && host(of: win)?.shown === item.pane
            rows.append(.tab(id: item.id, title: title, index: index, active: active, pinned: false))
            index += 1
        }
    }

    private func jumpSession(_ n: Int) {
        let ids = sidebarRows().compactMap { row -> ObjectIdentifier? in
            if case let .tab(id, _, _, _, _) = row { return id }
            return nil
        }
        let index = n == 9 ? ids.count - 1 : n - 1
        guard ids.indices.contains(index) else { return }
        selectSession(ids[index])
    }

    private func popSidebarMenu(_ anchor: NSView) {
        let menu = NSMenu()
        menu.addItem(section("分组"))
        menu.addItem(check("不分组", groupMode == .none, #selector(groupNone)))
        menu.addItem(check("按项目", groupMode == .project, #selector(groupProject)))
        menu.addItem(check("按日期", groupMode == .date, #selector(groupDate)))
        menu.addItem(.separator())
        menu.addItem(section("排序"))
        menu.addItem(check("创建时间", orderMode == .created, #selector(orderCreated)))
        menu.addItem(check("最近使用", orderMode == .updated, #selector(orderUpdated)))
        menu.addItem(.separator())
        menu.addItem(item("新建分组", #selector(newNamedGroup), ""))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: anchor)
    }

    private func section(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    private func check(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let it = item(title, action, "")
        it.state = on ? .on : .off
        return it
    }

    @objc private func groupNone() { groupMode = .none; reloadSidebars() }
    @objc private func groupProject() { groupMode = .project; reloadSidebars() }
    @objc private func groupDate() { groupMode = .date; reloadSidebars() }
    @objc private func orderCreated() { orderMode = .created; reloadSidebars() }
    @objc private func orderUpdated() { orderMode = .updated; reloadSidebars() }

    @objc private func newNamedGroup() {
        groupMode = .none
        let id = tabGroups.create(name: tabGroups.uniqueName("分组"), member: nil)
        let key = "group:\(id)"
        reloadSidebars()
        visibleSidebars().forEach { $0.beginRename(key) }
    }

    private func renameGroup(_ key: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        if let id = groupUUID(key) {
            _ = tabGroups.rename(id, to: trimmed)
        } else {
            groupAliases[key] = trimmed
        }
        reloadSidebars()
    }

    private func moveGroup(_ key: String, to index: Int) {
        if let id = groupUUID(key) {
            tabGroups.move(id, to: index)
        } else {
            var keys = orderedKeys(currentGroupKeys())
            keys.removeAll { $0 == key }
            keys.insert(key, at: min(max(0, index), keys.count))
            groupOrder = keys
        }
        reloadSidebars()
    }

    private func orderedKeys(_ keys: [String]) -> [String] {
        let known = groupOrder.filter { keys.contains($0) }
        let rest = keys.filter { groupOrder.contains($0) == false }.sorted()
        return known + rest
    }

    private func groupTitle(_ key: String) -> String {
        groupAliases[key] ?? key
    }

    private func currentGroupKeys() -> [String] {
        var keys: [String] = []
        for win in sessions() {
            let key = groupKey(win)
            if keys.contains(key) == false { keys.append(key) }
        }
        return keys
    }

    private func newInGroup(_ key: String) {
        let dir: String?
        if let id = groupUUID(key) {
            dir = directory(of: liveMembers(id).first) ?? focusedPane()?.liveDirectory()
        } else if groupMode == .project {
            dir = directory(of: sessions().first { groupKey($0) == key })
        } else {
            dir = focusedPane()?.liveDirectory()
        }
        shell.host.layoutSubtreeIfNeeded()
        let pane = TermPane(frame: shell.host.bounds)
        shell.host.addPane(pane)
        pane.start(cfg, directory: dir)
        pane.enableGpu()
        pane.focus()
        let name = dir.flatMap { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? "终端"
        shelf.append(ShelfPane(id: ObjectIdentifier(pane), pane: pane, win: window, groupKey: key, title: name))
        collapsedGroups.remove(key)
        reloadSidebars()
    }

    private func popGroupMenu(_ key: String, _ anchor: NSView) {
        guard let id = groupUUID(key) else { return }
        let menu = NSMenu()
        menu.addItem(actionItem("重命名分组") { [weak self] in
            self?.visibleSidebars().forEach { $0.beginRename(key) }
        })
        menu.addItem(actionItem("在此分组新建标签") { [weak self] in self?.newInGroup(key) })
        menu.addItem(actionItem("删除分组") { [weak self] in
            self?.tabGroups.delete(id)
            self?.pinnedGroups.remove(id)
            self?.reloadSidebars()
        })
        menu.addItem(actionItem(pinnedGroups.contains(id) ? "取消固定" : "固定分组") { [weak self] in
            guard let self else { return }
            if self.pinnedGroups.contains(id) { self.pinnedGroups.remove(id) }
            else { self.pinnedGroups.insert(id) }
            self.reloadSidebars()
        })
        menu.addItem(actionItem("关闭分组") { [weak self] in
            self?.liveMembers(id).forEach { $0.close() }
        })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: anchor)
        menuActions.removeAll()
    }

    private func popTabMenu(_ id: ObjectIdentifier, _ anchor: NSView) {
        guard let win = sessions().first(where: { ObjectIdentifier($0) == id }) else { return }
        noteSession(win)
        guard let token = sessionToken[id] else { return }
        let menu = NSMenu()
        menu.addItem(actionItem("重命名") { [weak self] in
            self?.visibleSidebars().forEach { $0.beginRenameTab(id) }
        })
        menu.addItem(actionItem("新建分组并加入") { [weak self] in
            guard let self else { return }
            self.groupMode = .none
            let gid = self.tabGroups.create(name: self.tabGroups.uniqueName("分组"), member: token)
            self.reloadSidebars()
            self.visibleSidebars().forEach { $0.beginRename("group:\(gid)") }
        })
        let move = NSMenuItem(title: "移到分组", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for group in tabGroups.groups {
            let gid = group.id
            let item = actionItem(group.name) { [weak self] in
                self?.tabGroups.add(token, to: gid)
                self?.reloadSidebars()
            }
            item.state = tabGroups.groupID(of: token) == gid ? .on : .off
            sub.addItem(item)
        }
        if sub.items.isEmpty {
            let empty = NSMenuItem(title: "无分组", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        }
        move.submenu = sub
        menu.addItem(move)
        if tabGroups.groupID(of: token) != nil {
            menu.addItem(actionItem("移出分组") { [weak self] in
                self?.tabGroups.remove(token)
                self?.reloadSidebars()
            })
        }
        let pinned = pinnedSessions.contains(id)
        menu.addItem(actionItem(pinned ? "取消固定" : "固定标签") { [weak self] in
            self?.setSessionPinned(id, pinned == false)
        })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: anchor)
        menuActions.removeAll()
    }
    private func renameTab(_ id: ObjectIdentifier, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { customTitles.removeValue(forKey: id) }
        else { customTitles[id] = trimmed }
        reloadSidebars()
    }

    private func setSessionPinned(_ id: ObjectIdentifier, _ on: Bool) {
        if on {
            pinnedSessions.insert(id)
            if let token = sessionToken[id] { tabGroups.remove(token) }
        } else {
            pinnedSessions.remove(id)
        }
        reloadSidebars()
    }

    private var menuActions: [ObjectIdentifier: () -> Void] = [:]

    private func actionItem(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
        it.target = self
        menuActions[ObjectIdentifier(it)] = run
        return it
    }

    @objc private func runMenuAction(_ sender: NSMenuItem) {
        menuActions[ObjectIdentifier(sender)]?()
    }

    private func currentToken() -> UUID? {
        guard let win = window, win.identifier?.rawValue == "agent-term" else { return nil }
        noteSession(win)
        return sessionToken[ObjectIdentifier(win)]
    }

    private func groupUUID(_ key: String) -> UUID? {
        guard key.hasPrefix("group:") else { return nil }
        return UUID(uuidString: String(key.dropFirst("group:".count)))
    }

    private func liveMembers(_ id: UUID) -> [NSWindow] {
        guard let group = tabGroups.groups.first(where: { $0.id == id }) else { return [] }
        return group.members.compactMap { token in
            sessions().first { sessionToken[ObjectIdentifier($0)] == token }
        }
    }

    private func directory(of win: NSWindow?) -> String? {
        guard let win else { return nil }
        return (focusedPane(in: win) ?? panes(in: win).first)?.liveDirectory()
    }

    private func visibleSidebars() -> [TabSidebar] {
        sessions().compactMap { win in
            guard let host = win.contentView?.subviews.compactMap({ $0 as? ShellView }).first, host.showSidebar else { return nil }
            return host.sidebar
        }
    }

    private func reloadSidebars() {
        let rows = sidebarRows()
        for win in sessions() {
            win.contentView?.subviews.compactMap { $0 as? ShellView }.first?.sidebar.render(rows)
        }
    }

    private func sidebarRows() -> [SideRow] {
        let wins = sessions().sorted { lhs, rhs in
            let left = orderMode == .created ? createdAt[ObjectIdentifier(lhs)] : updatedAt[ObjectIdentifier(lhs)]
            let right = orderMode == .created ? createdAt[ObjectIdentifier(rhs)] : updatedAt[ObjectIdentifier(rhs)]
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
        if groupMode == .none {
            return namedRows(wins)
        }
        var buckets: [String: [NSWindow]] = [:]
        for win in wins {
            buckets[groupKey(win), default: []].append(win)
        }
        var rows: [SideRow] = []
        var index = 1
        for key in orderedKeys(Array(buckets.keys)) {
            let collapsed = collapsedGroups.contains(key)
            let members = buckets[key] ?? []
            let extras = members.reduce(0) { count, win in count + shelf.filter { $0.win === win && $0.groupKey == key && $0.pane != nil }.count }
            rows.append(.header(key: key, title: groupTitle(key), collapsed: collapsed, count: members.count + extras, named: true))
            if collapsed { continue }
            for win in members {
                rows.append(tabRow(win, index: index))
                index += 1
                appendShelf(in: win, key: key, rows: &rows, index: &index)
            }
        }
        return rows
    }

    private func namedRows(_ wins: [NSWindow]) -> [SideRow] {
        let grouped = Set(tabGroups.groups.flatMap(\.members))
        var rows: [SideRow] = []
        var index = 1
        func append(_ list: [NSWindow], key: String?) {
            for win in list {
                rows.append(tabRow(win, index: index))
                index += 1
                if let key { appendShelf(in: win, key: key, rows: &rows, index: &index) }
            }
        }
        func ungrouped(_ pinned: Bool) -> [NSWindow] {
            wins.filter { win in
                let id = ObjectIdentifier(win)
                if let token = sessionToken[id], grouped.contains(token) { return false }
                return pinnedSessions.contains(id) == pinned
            }
        }
        func appendGroups(_ pinned: Bool) {
            for group in tabGroups.groups where pinnedGroups.contains(group.id) == pinned {
                let key = "group:\(group.id)"
                let members = liveMembers(group.id)
                let extras = members.reduce(0) { count, win in count + shelf.filter { $0.win === win && $0.groupKey == key && $0.pane != nil }.count }
                rows.append(.header(key: key, title: group.name, collapsed: collapsedGroups.contains(key), count: members.count + extras, named: true))
                if collapsedGroups.contains(key) { continue }
                append(members, key: key)
            }
        }
        appendGroups(true)
        append(ungrouped(true), key: nil)
        appendGroups(false)
        append(ungrouped(false), key: nil)
        return rows
    }

    private func tabRow(_ win: NSWindow, index: Int) -> SideRow {
        let title = sessionTitle(win)
        let id = ObjectIdentifier(win)
        return .tab(id: id, title: title, index: index, active: win === window, pinned: pinnedSessions.contains(id))
    }

    private func sessionTitle(_ win: NSWindow) -> String {
        if let custom = customTitles[ObjectIdentifier(win)], custom.isEmpty == false { return custom }
        if let pane = focusedPane(in: win) ?? panes(in: win).first {
            let name = URL(fileURLWithPath: pane.liveDirectory()).lastPathComponent
            if name.isEmpty == false { return name }
        }
        return win.title.isEmpty ? "终端" : win.title
    }

    private func groupKey(_ win: NSWindow) -> String {
        switch groupMode {
        case .project:
            let path = (focusedPane(in: win) ?? panes(in: win).first)?.liveDirectory() ?? ""
            return projectName(path)
        case .date:
            let date = orderMode == .updated
                ? (updatedAt[ObjectIdentifier(win)] ?? Date())
                : (createdAt[ObjectIdentifier(win)] ?? Date())
            if Calendar.current.isDateInToday(date) { return "今天" }
            if Calendar.current.isDateInYesterday(date) { return "昨天" }
            return "更早"
        case .none:
            return ""
        }
    }

    private func projectName(_ path: String) -> String {
        guard path.isEmpty == false else { return "其他" }
        var url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        while url.path != "/" {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.lastPathComponent
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

private func pollAsks(_ dir: URL) {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    for name in names where name.hasSuffix(".req") {
        let id = String(name.dropLast(4))
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(id + ".res").path) { continue }
        guard App.claimAsk(id) else { continue }
        let line = (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
        DispatchQueue.main.async {
            (NSApp.delegate as? App)?.presentApproval(id: id, line: line, dir: dir)
        }
    }
}

extension App {
    fileprivate static func claimAsk(_ id: String) -> Bool {
        askLock.lock()
        defer { askLock.unlock() }
        return asking.insert(id).inserted
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
