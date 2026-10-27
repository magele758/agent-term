import XCTest
import TermCore

final class SessionTests: XCTestCase {
    private let outputTimeout: TimeInterval = 5
    private let killTimeout: TimeInterval = 2

    private func bytes(_ s: String) -> [UInt8] {
        Array(s.utf8)
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

    func testPrintHiAndExit() {
        let session = Session()
        let ready = expectation(description: "ready")
        let exited = expectation(description: "exit")
        var code: Int32?
        session.onReady = { ready.fulfill() }
        session.onExit = { status in
            code = status
            exited.fulfill()
        }
        session.start()
        wait(for: [ready], timeout: outputTimeout)
        session.send(bytes("printf 'hi\\n'; exit\n"))
        wait(for: [exited], timeout: outputTimeout)
        XCTAssertTrue(session.text.contains("hi"))
        XCTAssertNotNil(code)
    }

    func testClearScreenDropsMarker() {
        let session = Session()
        let ready = expectation(description: "ready")
        session.onReady = { ready.fulfill() }
        session.start()
        wait(for: [ready], timeout: outputTimeout)
        session.send(bytes("printf 'BEFORE\\n\\033[2J\\033[HB\\n'\n"))
        waitUntil("cleared", timeout: outputTimeout) {
            session.text.contains("B") && !session.text.contains("BEFORE")
        }
        XCTAssertTrue(session.text.contains("B"))
        XCTAssertFalse(session.text.contains("BEFORE"))
    }

    func testRedForeground() {
        let session = Session()
        let ready = expectation(description: "ready")
        session.onReady = { ready.fulfill() }
        session.start()
        wait(for: [ready], timeout: outputTimeout)
        session.send(bytes("printf '\\033[31mred\\033[0m\\n'\n"))
        waitUntil("red", timeout: outputTimeout) { session.text.contains("red") }
        XCTAssertTrue(session.text.contains("red"))

        var found: (character: Character, foreground: Attribute.Color)?
        scan: for row in 0..<24 {
            for col in 0..<80 {
                guard let cell = session.cell(col: col, row: row), cell.character == "r" else { continue }
                let next = session.cell(col: col + 1, row: row)
                let after = session.cell(col: col + 2, row: row)
                let tail = session.cell(col: col + 3, row: row)?.character
                if next?.character == "e", after?.character == "d",
                   tail == nil || tail == " " || tail == "\0" {
                    found = cell
                    break scan
                }
            }
        }
        XCTAssertEqual(found?.foreground, .ansi256(code: 1))
    }

    func testTerminateSleepWithinTwoSeconds() {
        let session = Session()
        let ready = expectation(description: "ready")
        let exited = expectation(description: "exit")
        var code: Int32?
        session.onReady = { ready.fulfill() }
        session.onExit = { status in
            code = status
            exited.fulfill()
        }
        session.start()
        wait(for: [ready], timeout: outputTimeout)
        session.send(bytes("sleep 30\n"))
        session.terminate()
        wait(for: [exited], timeout: killTimeout)
        XCTAssertNotNil(code)
    }

    func testSendAfterExitDoesNotRestart() {
        let session = Session()
        let ready = expectation(description: "ready")
        let exited = expectation(description: "exit")
        let readyAgain = expectation(description: "ready again")
        readyAgain.isInverted = true
        var readyCount = 0
        session.onReady = {
            readyCount += 1
            if readyCount == 1 {
                ready.fulfill()
            } else {
                readyAgain.fulfill()
            }
        }
        session.onExit = { _ in exited.fulfill() }
        session.start()
        wait(for: [ready], timeout: outputTimeout)
        session.send(bytes("printf 'hi\\n'; exit\n"))
        wait(for: [exited], timeout: outputTimeout)
        session.send(bytes("printf 'again\\n'\n"))
        wait(for: [readyAgain], timeout: 0.5)
        XCTAssertEqual(readyCount, 1)
    }
}
