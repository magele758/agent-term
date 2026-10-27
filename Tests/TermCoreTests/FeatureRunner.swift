import Foundation
import TermCore
import Darwin

// ponytail: XCTest needs the full Xcode, which this machine does not have.
// Same nine checks as FeatureTests. Delete when `swift test` works.

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

func bytes(_ s: String) -> ArraySlice<UInt8> { ArraySlice(s.utf8) }

do {
    let screen = Screen()
    screen.feed(bytes("hi\r\n"))
    check("hi", screen.text.contains("hi"), screen.text.debugDescription)
}

do {
    let screen = Screen()
    var raw = Array("133;A".utf8)
    raw.insert(0x1b, at: 0)
    raw.insert(0x5d, at: 1)
    raw.append(0x07)
    screen.feed(ArraySlice(raw))
    check("prompt", screen.marks.contains { $0.kind == .prompt }, String(describing: screen.marks))
}

do {
    let screen = Screen()
    screen.feed(bytes("\u{1b}]7;file://host/Users/penglei\u{07}"))
    check("cwd", screen.cwd == "/Users/penglei", String(describing: screen.cwd))
    let spaced = Screen()
    spaced.feed(bytes("\u{1b}]7;file://host/Users/a%20b\u{07}"))
    check("cwd space", spaced.cwd == "/Users/a b", String(describing: spaced.cwd))
}

do {
    let screen = Screen()
    screen.feed(bytes(String(repeating: "L\n", count: 30)))
    check("scrollback", !screen.scrollbackText.isEmpty, screen.scrollbackText.debugDescription)
}

do {
    let workspace = Workspace()
    let tab = workspace.openTab()
    let ids = workspace.panes(in: 1)
    let pane = ids.first.flatMap { workspace.pane($0) }
    check("open tab", tab == 1 && workspace.tabs == [1] && ids.count == 1, "tab=\(tab) tabs=\(workspace.tabs) panes=\(ids)")
    check("pane alive", waitUntil(5) { pane?.alive == true }, "alive=\(String(describing: pane?.alive))")
    workspace.closeTab(tab)
}

do {
    let workspace = Workspace()
    let tab = workspace.openTab()
    let first = workspace.panes(in: tab).first
    let splitId = workspace.split(tab)
    let ids = workspace.panes(in: tab)
    let panes = ids.compactMap { workspace.pane($0) }
    check("split", splitId != nil && splitId != first && ids.count == 2, "split=\(String(describing: splitId)) panes=\(ids)")
    workspace.closeTab(tab)
    check("close kills", waitUntil(2) { panes.allSatisfy { !$0.alive } }, "alive=\(panes.map(\.alive))")
}

do {
    let workspace = Workspace()
    let tab = workspace.openTab()
    let pane = workspace.panes(in: tab).first.flatMap { workspace.pane($0) }
    _ = waitUntil(5) { pane?.alive == true }
    workspace.send(tab: tab, "printf 'wk\\n'")
    let ok = waitUntil(5) { pane?.text.contains("wk") == true }
    check("wk", ok, pane?.text.debugDescription ?? "nil pane")
    workspace.closeTab(tab)
}

do {
    let gate = Gate(rules: [
        Rule(prefix: "git ", verdict: .allow),
        Rule(prefix: "rm ", verdict: .deny("denied by rule")),
    ])
    check("git allow", gate.check("git status") == .allow, String(describing: gate.check("git status")))
    check("rm deny", gate.check("rm -rf /") == .deny("denied by rule"), String(describing: gate.check("rm -rf /")))
    check("curl ask", gate.check("curl x") == .ask("curl x"), String(describing: gate.check("curl x")))
    check("empty deny", gate.check("  ") == .deny("empty"), String(describing: gate.check("  ")))
}

do {
    let gate = Gate(rules: [])
    gate.ask("curl x")
    check("pending", gate.pending == ["curl x"], String(describing: gate.pending))
    gate.ask("curl x")
    check("no dup", gate.pending == ["curl x"], String(describing: gate.pending))
    check("resolve", gate.resolve("curl x", allow: false) == .deny("denied by user"))
    check("pending empty", gate.pending.isEmpty, String(describing: gate.pending))
}

exit(failed == 0 ? 0 : 1)
