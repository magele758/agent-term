import Foundation
import SwiftTerm

public typealias Attribute = SwiftTerm.Attribute

public final class Session {
    private let cols = 80
    private let rows = 24
    private let process: LocalProcess
    private let terminal: Terminal
    private let sink: TerminalSink
    private var ready = false
    private var alive = false

    public var onReady: (() -> Void)?
    public var onExit: ((Int32?) -> Void)?

    public init() {
        // Terminal.init demands a delegate before self exists. Replies go through Session.send.
        let sink = TerminalSink()
        let terminal = Terminal(delegate: sink, options: TerminalOptions(cols: cols, rows: rows))
        terminal.setup()
        self.terminal = terminal
        self.sink = sink
        process = LocalProcess(delegate: sink, dispatchQueue: DispatchQueue(label: "session"))
        sink.owner = self
    }

    public func start() {
        alive = true
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.removeAll { $0.hasPrefix("TERM=") }
        env.append("TERM=xterm-256color")
        process.startProcess(
            executable: "/bin/zsh",
            args: ["-f"],
            environment: env,
            currentDirectory: FileManager.default.currentDirectoryPath
        )
    }

    public func send(_ bytes: [UInt8]) {
        guard alive, process.running else { return }
        process.send(data: bytes[...])
    }

    public func terminate() {
        let pid = process.shellPid
        guard pid != 0 else { return }
        kill(pid, SIGKILL)
        // ponytail: SwiftTerm's exit monitor reaps the child and then drops the
        // event, so poll; reap it ourselves if the monitor never reports it.
        DispatchQueue.global().async { [weak self] in
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 0.05)
                guard let self else { return }
                if !self.alive { return }
                var status: Int32 = 0
                if waitpid(pid, &status, WNOHANG) > 0 {
                    self.processTerminated(self.process, exitCode: status)
                    return
                }
            }
        }
    }

    public var text: String {
        var lines: [String] = []
        for row in 0..<rows {
            lines.append(terminal.getLine(row: row)?.translateToString(trimRight: true) ?? "")
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    public func cell(col: Int, row: Int) -> (character: Character, foreground: Attribute.Color)? {
        guard let data = terminal.getCharData(col: col, row: row) else { return nil }
        return (data.getCharacter(), data.attribute.fg)
    }

    func getWindowSize() -> winsize {
        winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        terminal.feed(byteArray: Array(slice))
        guard !ready else { return }
        ready = true
        onReady?()
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        alive = false
        // ponytail: WIFEXITED/WEXITSTATUS are function macros, which Swift cannot import.
        let code = exitCode.map { ($0 & 0x7f) == 0 ? ($0 >> 8) & 0xff : $0 }
        onExit?(code)
    }

    public func send(source: Terminal, data: ArraySlice<UInt8>) {
        send(Array(data))
    }
}

private final class TerminalSink: TerminalDelegate, LocalProcessDelegate {
    weak var owner: Session?
    func send(source: Terminal, data: ArraySlice<UInt8>) {
        owner?.send(Array(data))
    }
    func dataReceived(slice: ArraySlice<UInt8>) { owner?.dataReceived(slice: slice) }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        owner?.processTerminated(source, exitCode: exitCode)
    }
    func getWindowSize() -> winsize { owner?.getWindowSize() ?? winsize() }
}
