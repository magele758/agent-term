import Foundation
import SwiftTerm

public struct Mark: Equatable {
    public enum Kind: Equatable { case prompt, commandStart, commandEnd }
    public let kind: Kind
    public let row: Int
}

public final class Screen {
    public static let cols = 80
    public static let rows = 24

    private let terminal: Terminal
    private let sink = ScreenSink()
    private var fedRows = 0
    private var history: [String] = []
    private var lastTop: String?
    private var recorded: [Mark] = []
    private var directory: String?

    public init() {
        let terminal = Terminal(delegate: sink, options: TerminalOptions(cols: Self.cols, rows: Self.rows))
        terminal.setup()
        self.terminal = terminal
    }

    public func feed(_ bytes: ArraySlice<UInt8>) {
        let lines = linesOf(bytes)
        if lines.count > 1 {
            let before = terminal.getLine(row: 0)?.translateToString(trimRight: true) ?? ""
            if !before.isEmpty, history.last != before { history.append(before) }
            history.append(contentsOf: lines.dropLast())
        }
        scan(bytes)
        terminal.feed(byteArray: Array(bytes))
        captureScrollback()
    }

    public var text: String {
        var lines: [String] = []
        for row in 0..<terminal.rows {
            lines.append(terminal.getLine(row: row)?.translateToString(trimRight: true) ?? "")
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    public func cell(col: Int, row: Int) -> (character: Character, foreground: Attribute.Color)? {
        guard let data = terminal.getCharData(col: col, row: row) else { return nil }
        return (data.getCharacter(), data.attribute.fg)
    }

    public var scrollbackText: String { history.joined(separator: "\n") }

    public var marks: [Mark] { recorded }

    public var cwd: String? { directory }

    public func resize(cols: Int, rows: Int) {
        terminal.resize(cols: max(cols, 2), rows: max(rows, 2))
    }

    // ponytail: fedRows counts 0x0a outside escapes, so cursor-addressing moves are miscounted; read the terminal cursor after feed.
    private func scan(_ bytes: ArraySlice<UInt8>) {
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let b = bytes[i]
            if b == 0x1b {
                let next = bytes.index(after: i)
                if next < bytes.endIndex && bytes[next] == 0x5d {
                    i = osc(bytes, from: bytes.index(after: next))
                    continue
                }
                i = skipEscape(bytes, from: next)
                continue
            }
            if b == 0x0a { fedRows += 1 }
            i = bytes.index(after: i)
        }
    }

    private func osc(_ bytes: ArraySlice<UInt8>, from start: ArraySlice<UInt8>.Index) -> ArraySlice<UInt8>.Index {
        var i = start
        var payload: [UInt8] = []
        while i < bytes.endIndex {
            let b = bytes[i]
            if b == 0x07 { i = bytes.index(after: i); break }
            if b == 0x1b {
                let next = bytes.index(after: i)
                if next < bytes.endIndex && bytes[next] == 0x5c {
                    i = bytes.index(after: next)
                    break
                }
            }
            payload.append(b)
            i = bytes.index(after: i)
        }
        apply(payload)
        return i
    }

    private func apply(_ payload: [UInt8]) {
        guard let text = String(bytes: payload, encoding: .utf8) else { return }
        if text.hasPrefix("133;") {
            let kind: Mark.Kind
            switch text.dropFirst(4).first {
            case "A": kind = .prompt
            case "C": kind = .commandStart
            case "D": kind = .commandEnd
            default: return
            }
            recorded.append(Mark(kind: kind, row: fedRows))
        } else if text.hasPrefix("7;") {
            directory = Self.path(from: String(text.dropFirst(2)))
        }
    }

    private static func path(from url: String) -> String {
        var rest = url
        if let scheme = rest.range(of: "file://") { rest.removeSubrange(..<scheme.upperBound) }
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[slash...]) }
        return rest.removingPercentEncoding ?? rest
    }

    private func skipEscape(_ bytes: ArraySlice<UInt8>, from start: ArraySlice<UInt8>.Index) -> ArraySlice<UInt8>.Index {
        guard start < bytes.endIndex else { return start }
        let kind = bytes[start]
        var i = bytes.index(after: start)
        if kind == 0x5b {
            while i < bytes.endIndex {
                let b = bytes[i]
                i = bytes.index(after: i)
                if b >= 0x40 && b <= 0x7e { break }
            }
            return i
        }
        if kind == 0x50 || kind == 0x58 || kind == 0x5e || kind == 0x5f {
            while i < bytes.endIndex {
                if bytes[i] == 0x1b {
                    let next = bytes.index(after: i)
                    if next < bytes.endIndex && bytes[next] == 0x5c { return bytes.index(after: next) }
                }
                if bytes[i] == 0x07 { return bytes.index(after: i) }
                i = bytes.index(after: i)
            }
        }
        return i
    }

    // ponytail: bulk lines are counted from raw 0x0a splits, so wrapped rows are over-counted; read buffer.yDisp and the lines above the viewport.
    private func linesOf(_ bytes: ArraySlice<UInt8>) -> [String] {
        var lines: [String] = []
        var current: [UInt8] = []
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let b = bytes[i]
            if b == 0x1b {
                i = bytes.index(after: i)
                if i < bytes.endIndex && bytes[i] == 0x5b {
                    while i < bytes.endIndex {
                        let n = bytes[i]
                        i = bytes.index(after: i)
                        if n >= 0x40 && n <= 0x7e { break }
                    }
                }
                continue
            }
            if b == 0x0a {
                lines.append(String(bytes: current, encoding: .utf8) ?? "")
                current.removeAll(keepingCapacity: true)
            } else if b != 0x0d {
                current.append(b)
            }
            i = bytes.index(after: i)
        }
        return lines
    }
    private func captureScrollback() {
        let top = terminal.getLine(row: 0)?.translateToString(trimRight: true) ?? ""
        if let lastTop, top != lastTop, !lastTop.isEmpty, history.last != lastTop {
            history.append(lastTop)
        }
        lastTop = top
    }
}

private final class ScreenSink: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
