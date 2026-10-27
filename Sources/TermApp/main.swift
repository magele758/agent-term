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
        case shell, login, optionAsMeta, env, modelBaseUrl, modelName
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
        if let legacy = obj?["modelApiKey"] as? String {
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
    static let service = "agent-term"
    static let account = "modelApiKey"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func save(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
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
    let term = LocalProcessTerminalView(frame: .zero)
    private let crt = CRTOverlay(frame: .zero)
    private let badge = NSTextField(labelWithString: "")
    private var started = false
    private(set) var directory = FileManager.default.currentDirectoryPath

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderColor = NSColor.systemBlue.cgColor
        term.autoresizingMask = [.width, .height]
        addSubview(term)
        addSubview(crt)
        badge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        badge.textColor = NSColor.systemOrange
        badge.drawsBackground = false
        badge.isBezeled = false
        badge.isEditable = false
        badge.isHidden = true
        addSubview(badge)
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
        if let style = CursorStyle(tagName: cfg.cursorStyle) {
            term.terminal.setCursorStyle(style)
        }
        crt.setEnabled(cfg.themeName == "辐射")
        layer?.borderColor = (cfg.themeName == "辐射"
            ? NSColor(srgbRed: 0.2, green: 0.45, blue: 0.22, alpha: 1)
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

    func markFocused(_ on: Bool) { layer?.borderWidth = on ? 1 : 0 }

    func setBadge(_ text: String?) {
        badge.stringValue = text ?? ""
        badge.isHidden = (text ?? "").isEmpty
        needsLayout = true
    }

    // Otty: one GPU layer per pane, dirty rows only. Call after the view is in a window.
    func enableGpu() {
        guard window != nil, term.isUsingMetalRenderer == false else { return }
        do {
            try term.setUseMetal(true)
            term.metalBufferingMode = .perRowPersistent
        } catch {
            FileHandle.standardError.write(Data("metal: \(error)\n".utf8))
        }
    }

    func screenText() -> String {
        let selected = term.selection.getSelectedText()
        if selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return selected }
        guard let grid = term.terminal, grid.cols > 0, grid.rows > 0 else { return "" }
        return grid.getText(start: Position(col: 0, row: 0),
                            end: Position(col: grid.cols - 1, row: grid.rows - 1))
    }

    override func layout() {
        super.layout()
        term.frame = bounds
        crt.frame = bounds
        badge.sizeToFit()
        let size = badge.frame.size
        badge.frame = NSRect(x: bounds.width - size.width - 8, y: bounds.height - size.height - 6,
                             width: size.width, height: size.height)
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
            let w = (bounds.width - gap) * r
            first.frame = NSRect(x: 0, y: 0, width: w, height: bounds.height)
            second.frame = NSRect(x: w + gap, y: 0, width: bounds.width - w - gap, height: bounds.height)
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
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false)
    private var monitor: Any?
    private var settings: Settings?
    private let palette = CommandPalette()
    private var shell: ShellView!
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
        window.isOpaque = cfg.opacity >= 1
        window.backgroundColor = cfg.opacity >= 1 ? .black : .clear
        window.title = "agent-term"
        window.delegate = self
        let shell = ShellView(frame: window.contentView!.bounds)
        shell.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(shell)
        self.shell = shell
        wireDock()
        let pane = TermPane(frame: shell.host.bounds)
        shell.host.setRoot(pane)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.layoutIfNeeded()
        pane.start(cfg)
        pane.enableGpu()
        pane.focus()
        refreshHint()
        buildMenu()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func windowWillClose(_ notification: Notification) {
        agentTask?.terminate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        NSApplication.shared.terminate(nil)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if let source = event.window, source !== window { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        guard flags.contains(.command) else { return event }
        if event.keyCode == 36 {
            if flags.contains(.option) { queueComposer(); return nil }
            if flags.contains(.control) { attachScreen(); return nil }
            submitComposer(forceQueue: false)
            return nil
        }
        if key == "d" { split(sideBySide: !flags.contains(.shift)); return nil }
        if key == "w" { closeFocused(); return nil }
        if key == "," { openSettings(); return nil }
        if key == "k" { focusAgent(); return nil }
        if key == "p" && flags.contains(.shift) { showPalette(); return nil }
        if key == "=" || key == "+" { zoom(by: 1); return nil }
        if key == "-" { zoom(by: -1); return nil }
        if key == "0" { zoom(by: 0); return nil }
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

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let win = NSMenu(title: "窗口")
        winItem.submenu = win
        win.addItem(item("左右分屏", #selector(splitSideBySide), "d"))
        let stack = item("上下分屏", #selector(splitStacked), "d")
        stack.keyEquivalentModifierMask = [.command, .shift]
        win.addItem(stack)
        win.addItem(item("关闭面板", #selector(closePane), "w"))
        win.addItem(arrowItem("焦点左", #selector(focusLeft), NSLeftArrowFunctionKey))
        win.addItem(arrowItem("焦点右", #selector(focusRight), NSRightArrowFunctionKey))
        win.addItem(arrowItem("焦点下", #selector(focusDown), NSDownArrowFunctionKey))
        win.addItem(arrowItem("焦点上", #selector(focusUp), NSUpArrowFunctionKey))
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
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
        shell.dock.onSend = { [weak self] in self?.submitComposer(forceQueue: false) }
        shell.dock.onQueue = { [weak self] in self?.queueComposer() }
        shell.dock.onAttach = { [weak self] in self?.attachScreen() }
        shell.dock.onHide = { [weak self] in
            self?.shell.setDockVisible(false)
            self?.refreshHint()
        }
        shell.dock.onApprove = { [weak self] id, allow in self?.finishApproval(id, allow: allow) }
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
        let theme = ThemeCatalog.find(cfg.themeName)
        let bg = color(theme?.background ?? cfg.background)
        window.isOpaque = cfg.opacity >= 1
        window.backgroundColor = cfg.opacity >= 1 ? bg : .clear
        shell.host.layer?.backgroundColor = bg.cgColor
        for pane in allPanes() { pane.apply(cfg) }
        refreshHint()
    }

    @objc private func showPalette() {
        var actions: [(String, () -> Void)] = [
            ("设置", { [weak self] in self?.openSettings() }),
            ("打开 Agent 对话", { [weak self] in self?.focusAgent() }),
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

    private func split(sideBySide: Bool) {
        guard let pane = focusedPane(), let parent = pane.superview else { return }
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
        pane.term.terminate()
        guard let split = pane.superview as? SplitView else { window.close(); return }
        let keep = split.first === pane ? split.second : split.first
        pane.removeFromSuperview()
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

    private func focusedPane() -> TermPane? {
        var view = window.firstResponder as? NSView
        while let cur = view {
            if let pane = cur as? TermPane, pane.term.isDescendant(of: pane) { return pane }
            view = cur.superview
        }
        return allPanes().first
    }

    private func allPanes() -> [TermPane] {
        var found: [TermPane] = []
        func walk(_ view: NSView) {
            if let pane = view as? TermPane { found.append(pane) }
            view.subviews.forEach(walk)
        }
        walk(window.contentView!)
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
