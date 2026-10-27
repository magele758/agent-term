import Foundation
import SwiftTerm

public final class Pane {
    public let id: Int
    private let session = Session()
    private var callerExit: ((Int32?) -> Void)?
    private(set) public var alive = false

    public var onExit: ((Int32?) -> Void)? {
        get { callerExit }
        set { callerExit = newValue }
    }

    public init(id: Int) {
        self.id = id
        session.onExit = { [weak self] code in
            self?.alive = false
            self?.callerExit?(code)
        }
    }

    public func start() {
        alive = true
        session.start()
    }

    public func send(_ text: String) {
        var line = text
        if !line.hasSuffix("\n") { line += "\n" }
        session.send(Array(line.utf8))
    }

    public func terminate() {
        session.terminate()
    }

    public var text: String { session.text }
}
