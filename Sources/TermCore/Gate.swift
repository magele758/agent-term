import Foundation

public enum Verdict: Equatable {
    case allow
    case deny(String)
    case ask(String)
}

public struct Rule: Equatable {
    public let prefix: String
    public let verdict: Verdict
    public init(prefix: String, verdict: Verdict) {
        self.prefix = prefix
        self.verdict = verdict
    }
}

public final class Gate {
    private let rules: [Rule]
    private var waiting: [String] = []

    public init(rules: [Rule]) {
        self.rules = rules
    }

    // ponytail: first line only — ceiling is line-based matching, upgrade is a real shell parser.
    public func check(_ command: String) -> Verdict {
        let line = commandKey(command)
        if line.isEmpty { return .deny("empty") }
        for rule in rules where line.hasPrefix(rule.prefix) {
            return rule.verdict
        }
        return .ask(line)
    }

    public var pending: [String] { waiting }

    public func ask(_ command: String) {
        guard case .ask(let line) = check(command), !waiting.contains(line) else { return }
        waiting.append(line)
    }

    public func resolve(_ command: String, allow: Bool) -> Verdict {
        let line = commandKey(command)
        if let i = waiting.firstIndex(of: line) { waiting.remove(at: i) }
        return allow ? .allow : .deny("denied by user")
    }

    private func commandKey(_ command: String) -> String {
        let first = command.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        return String((first ?? "").drop { $0.isWhitespace })
    }
}
