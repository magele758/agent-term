import XCTest
import TermCore

final class FeatureTests: XCTestCase {
    private let outputTimeout: TimeInterval = 5
    private let killTimeout: TimeInterval = 2

    private func bytes(_ s: String) -> ArraySlice<UInt8> {
        ArraySlice(s.utf8)
    }

    /// Poll `predicate` until it holds or `timeout` elapses. Fulfills exactly once.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval,
        predicate: @escaping () -> Bool
    ) {
        let exp = expectation(description: description)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler {
            if predicate() {
                timer.cancel()
                exp.fulfill()
            }
        }
        timer.resume()
        wait(for: [exp], timeout: timeout)
        timer.cancel()
    }

    func testFeedHi() {
        let screen = Screen()
        screen.feed(bytes("hi\r\n"))
        XCTAssertTrue(screen.text.contains("hi"))
    }

    func testPromptMark() {
        let screen = Screen()
        var raw = Array("133;A".utf8)
        raw.insert(0x1b, at: 0)
        raw.insert(0x5d, at: 1)
        raw.append(0x07)
        screen.feed(ArraySlice(raw))
        XCTAssertTrue(screen.marks.contains { $0.kind == .prompt })
    }

    func testCwdFromOsc7() {
        let screen = Screen()
        screen.feed(bytes("\u{1b}]7;file://host/Users/penglei\u{07}"))
        XCTAssertEqual(screen.cwd, "/Users/penglei")

        let spaced = Screen()
        spaced.feed(bytes("\u{1b}]7;file://host/Users/a%20b\u{07}"))
        XCTAssertEqual(spaced.cwd, "/Users/a b")
    }

    func testScrollbackAfterThirtyLines() {
        let screen = Screen()
        screen.feed(bytes(String(repeating: "L\n", count: 30)))
        XCTAssertFalse(screen.scrollbackText.isEmpty)
    }

    func testOpenTabSpawnsAlivePane() {
        let workspace = Workspace()
        let tab = workspace.openTab()
        XCTAssertEqual(tab, 1)
        XCTAssertEqual(workspace.tabs, [1])
        let ids = workspace.panes(in: 1)
        XCTAssertEqual(ids.count, 1)
        let pane = workspace.pane(ids[0])
        waitUntil("pane alive", timeout: outputTimeout) { pane?.alive == true }
        XCTAssertEqual(pane?.alive, true)
        workspace.closeTab(tab)
    }

    func testSplitThenCloseTabKillsBoth() {
        let workspace = Workspace()
        let tab = workspace.openTab()
        let splitId = workspace.split(tab)
        XCTAssertNotNil(splitId)
        XCTAssertNotEqual(splitId, workspace.panes(in: tab).first)
        XCTAssertEqual(workspace.panes(in: tab).count, 2)
        let panes = workspace.panes(in: tab).compactMap { workspace.pane($0) }
        workspace.closeTab(tab)
        waitUntil("both dead", timeout: killTimeout) { panes.allSatisfy { !$0.alive } }
        XCTAssertTrue(panes.allSatisfy { !$0.alive })
    }

    func testSendPrintsWk() {
        let workspace = Workspace()
        let tab = workspace.openTab()
        let id = workspace.panes(in: tab)[0]
        let pane = workspace.pane(id)
        waitUntil("pane alive", timeout: outputTimeout) { pane?.alive == true }
        workspace.send(tab: tab, "printf 'wk\\n'")
        waitUntil("wk", timeout: outputTimeout) { pane?.text.contains("wk") == true }
        XCTAssertTrue(pane?.text.contains("wk") == true)
        workspace.closeTab(tab)
    }

    func testGateRules() {
        let gate = Gate(rules: [
            Rule(prefix: "git ", verdict: .allow),
            Rule(prefix: "rm ", verdict: .deny("denied by rule")),
        ])
        XCTAssertEqual(gate.check("git status"), .allow)
        XCTAssertEqual(gate.check("rm -rf /"), .deny("denied by rule"))
        XCTAssertEqual(gate.check("curl x"), .ask("curl x"))
        XCTAssertEqual(gate.check("  "), .deny("empty"))
    }

    func testGateAskResolve() {
        let gate = Gate(rules: [])
        gate.ask("curl x")
        XCTAssertEqual(gate.pending, ["curl x"])
        gate.ask("curl x")
        XCTAssertEqual(gate.pending, ["curl x"])
        XCTAssertEqual(gate.resolve("curl x", allow: false), .deny("denied by user"))
        XCTAssertEqual(gate.pending, [])
    }
}
