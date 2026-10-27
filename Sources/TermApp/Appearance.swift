import AppKit
import CoreText
import SwiftTerm

struct Theme: Equatable {
    var name: String
    var foreground: String
    var background: String
    var cursor: String
    var selection: String
    var palette: [String]
}

enum ThemeCatalog {
    static let custom = "自定义"

    static let builtIn: [Theme] = [
        theme("默认", "#d4d4d4", "#1e1e1e", "#d4d4d4", "#264f78", [
            "#1e1e1e", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
            "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#e5e5e5",
        ]),
        theme("Nord", "#d8dee9", "#2e3440", "#d8dee9", "#434c5e", [
            "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
            "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4",
        ]),
        theme("Dracula", "#f8f8f2", "#282a36", "#f8f8f2", "#44475a", [
            "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
            "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff",
        ]),
        theme("Tokyo Night", "#c0caf5", "#1a1b26", "#c0caf5", "#283457", [
            "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
            "#414868", "#ff899d", "#9fe044", "#faba4a", "#8db0ff", "#c7a9ff", "#a4daff", "#c0caf5",
        ]),
        theme("Catppuccin", "#cdd6f4", "#1e1e2e", "#f5e0dc", "#45475a", [
            "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
            "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
        ]),
        theme("Solarized", "#839496", "#002b36", "#839496", "#073642", [
            "#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
            "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
        ]),
        theme("Paper", "#3c3836", "#fbf1c7", "#3c3836", "#ebdbb2", [
            "#fbf1c7", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#7c6f64",
            "#928374", "#9d0006", "#79740e", "#b57614", "#076678", "#8f3f71", "#427b58", "#3c3836",
        ]),
        theme("辐射", "#a2d467", "#1f2817", "#d8f898", "#4a6230", [
            "#243018", "#4a6230", "#6a8444", "#8aaa58", "#a2c468", "#c6f06a", "#d8f898", "#e8ffb0",
            "#1a2410", "#3a4a28", "#5a7040", "#7a9450", "#9ab860", "#b6e060", "#d0f080", "#f4ffd8",
        ]),
        theme("琥珀", "#de8520", "#4b2f11", "#ffd27a", "#6a4018", [
            "#211407", "#4a3014", "#6a481c", "#8a6024", "#b07828", "#de8520", "#ff9a2e", "#ffd27a",
            "#140c04", "#3a2410", "#5a3814", "#7a5018", "#a06820", "#d08028", "#ffb050", "#ffe0a8",
        ]),
        theme("蓝", "#6ccdfb", "#3c90c7", "#e8f6ff", "#7ec8f0", [
            "#1a5070", "#2a70a0", "#3c90c7", "#5aa8dc", "#7ec8f0", "#a8e0ff", "#d4f4ff", "#ffffff",
            "#123848", "#206080", "#3c90c7", "#58b0e4", "#8ad4f8", "#b8e8ff", "#e8f6ff", "#ffffff",
        ]),
    ]

    static func all() -> [Theme] {
        builtIn + droppedIn()
    }

    static func find(_ name: String) -> Theme? {
        all().first { $0.name == name }
    }

    static func colors(_ theme: Theme) -> [Color] {
        theme.palette.compactMap(paletteColor)
    }

    private static func theme(_ name: String, _ fg: String, _ bg: String, _ cursor: String, _ selection: String, _ palette: [String]) -> Theme {
        Theme(name: name, foreground: fg, background: bg, cursor: cursor, selection: selection, palette: palette)
    }

    private static func droppedIn() -> [Theme] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-term/themes")
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(ThemeFile.self, from: data),
                  let fg = file.foreground, let bg = file.background, let palette = file.palette, palette.count == 16
            else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            return Theme(name: name, foreground: fg, background: bg, cursor: file.cursor ?? fg,
                         selection: file.selection ?? "#264f78", palette: palette)
        }
    }
}

enum FontCatalog {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-term/fonts")
    }

    static func registerDroppedFonts() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in urls where ["ttf", "otf", "ttc", "otc"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func monospacedFamilies() -> [String] {
        registerDroppedFonts()
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard let font = manager.font(withFamily: family, traits: [], weight: 5, size: 12) else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }.sorted()
    }

    static func font(_ family: String, size: CGFloat) -> NSFont? {
        if let named = NSFont(name: family, size: size) { return named }
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
    }

    // Menlo has no Nerd Font private-use icons. Powerlevel10k draws those as
    // boxes unless the grid font, or its cascade, is MesloLGS NF.
    static func terminalFont(_ family: String, size: CGFloat) -> NSFont? {
        registerDroppedFonts()
        let requested = font(family, size: size)
        let symbol = font("MesloLGS NF", size: size)
        let base = (requested.flatMap { coversIcons($0) ? $0 : nil }) ?? symbol ?? requested
        guard let base else { return nil }
        var cascade: [NSFontDescriptor] = []
        for extra in [symbol, font("Apple Symbols", size: size), font("Apple Color Emoji", size: size)] {
            guard let extra, extra.fontName != base.fontName else { continue }
            cascade.append(extra.fontDescriptor)
        }
        guard cascade.isEmpty == false else { return base }
        let described = base.fontDescriptor.addingAttributes([.cascadeList: cascade])
        return NSFont(descriptor: described, size: size) ?? base
    }

    private static func coversIcons(_ font: NSFont) -> Bool {
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        var chars = [UniChar(0xF07B)]
        return CTFontGetGlyphsForCharacters(font as CTFont, &chars, &glyphs, 1)
    }
}

final class CommandPalette: NSWindowController, NSTextFieldDelegate {
    private let field = NSTextField(string: "")
    private let stack = NSStackView()
    private var actions: [(String, () -> Void)] = []
    private var shown: [(String, () -> Void)] = []

    func present(_ actions: [(String, () -> Void)]) {
        self.actions = actions
        if window == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                                 styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                 backing: .buffered, defer: false)
            window.title = "命令"
            let box = NSView(frame: window.contentView!.bounds)
            field.frame = NSRect(x: 12, y: 320, width: 496, height: 28)
            field.placeholderString = "主题、字号、分屏、Agent…"
            field.delegate = self
            field.autoresizingMask = [.width, .minYMargin]
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 308))
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            scroll.documentView = stack
            box.addSubview(field)
            box.addSubview(scroll)
            window.contentView = box
            self.window = window
        }
        window?.center()
        field.stringValue = ""
        refill("")
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(field)
    }

    func controlTextDidChange(_ obj: Notification) { refill(field.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            shown.first?.1()
            window?.close()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            window?.close()
            return true
        }
        return false
    }

    private func refill(_ query: String) {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        shown = needle.isEmpty ? actions : actions.filter { $0.0.lowercased().contains(needle) }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, action) in shown.enumerated() {
            let button = NSButton(title: action.0, target: self, action: #selector(run(_:)))
            button.tag = index
            button.bezelStyle = .recessed
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 13)
            button.setButtonType(.momentaryPushIn)
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 480).isActive = true
        }
        stack.frame = NSRect(x: 0, y: 0, width: 500, height: CGFloat(max(shown.count, 1)) * 28 + 16)
    }

    @objc private func run(_ sender: NSButton) {
        guard shown.indices.contains(sender.tag) else { return }
        shown[sender.tag].1()
        window?.close()
    }
}
