import Foundation
import TermCore
import Darwin

// ponytail: XCTest needs the full Xcode, which this machine does not have.
// Same five checks as SessionTests. Delete when `swift test` works.

var failed = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { print("PASS \(name)") }
    else { failed += 1; print("FAIL \(name) \(detail)") }
}

func waitUntil(_ timeout: Double, _ pred: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if pred() { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return pred()
}

func startReady() -> Session {
    let s = Session()
    var ready = false
    s.onReady = { ready = true }
    s.start()
    precondition(waitUntil(5) { ready }, "shell never became ready")
    return s
}

do {
    let s = Session()
    var ready = false
    var code: Int32?
    s.onReady = { ready = true }
    s.onExit = { code = $0 }
    s.start()
    check("ready", waitUntil(5) { ready })
    s.send(Array("printf 'hi\\n'; exit\n".utf8))
    check("exit", waitUntil(5) { code != nil }, "code=\(String(describing: code)) text=\(s.text.debugDescription)")
    check("hi", s.text.contains("hi"), s.text.debugDescription)
    check("exit code", code != nil)
}

do {
    let s = startReady()
    s.send(Array("printf 'BEFORE\\n\\033[2J\\033[HB\\n'\n".utf8))
    let ok = waitUntil(5) { s.text.contains("B") && !s.text.contains("BEFORE") }
    check("clear", ok, s.text.debugDescription)
}

do {
    let s = startReady()
    s.send(Array("printf '\\033[31mred\\033[0m\\n'\n".utf8))
    check("red text", waitUntil(5) { s.text.contains("red") }, s.text.debugDescription)
    var fg: Attribute.Color?
    scan: for row in 0..<24 {
        for col in 0..<80 {
            guard let cell = s.cell(col: col, row: row), cell.character == "r" else { continue }
            // The typed command is echoed in the prompt, so match the whole word.
            let tail = s.cell(col: col + 3, row: row)?.character
            // A cleared cell is U+0000, not a space. The prompt echo continues with "\".
            if s.cell(col: col + 1, row: row)?.character == "e",
               s.cell(col: col + 2, row: row)?.character == "d",
               tail == nil || tail == " " || tail == "\0" {
                fg = cell.foreground
                break scan
            }
        }
    }
    check("red attr", fg == .ansi256(code: 1), String(describing: fg))
}

do {
    let s = startReady()
    var code: Int32?
    s.onExit = { code = $0 }
    s.send(Array("sleep 30\n".utf8))
    Thread.sleep(forTimeInterval: 0.2)
    s.terminate()
    check("terminate", waitUntil(2) { code != nil }, "code=\(String(describing: code))")
}

do {
    let s = startReady()
    var exits = 0
    var readyCount = 1
    s.onReady = { readyCount += 1 }
    s.onExit = { _ in exits += 1 }
    s.send(Array("printf 'hi\\n'; exit\n".utf8))
    check("first exit", waitUntil(5) { exits == 1 })
    s.send(Array("printf 'again\\n'\n".utf8))
    Thread.sleep(forTimeInterval: 0.5)
    check("no restart", readyCount == 1 && exits == 1, "ready=\(readyCount) exits=\(exits)")
}

exit(failed == 0 ? 0 : 1)
