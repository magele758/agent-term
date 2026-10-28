import Foundation

struct CommandBlock: Equatable {
    let id: UUID
    var command: String
    var output: String
    var exitCode: Int?
    var cwd: String
    var running: Bool
}

enum BlockFeed {
    /// Wraps a user command so the same zsh keeps cwd, then prints a marker.
    /// Empty input returns "". Multiline input is wrapped in braces.
    static func wrapped(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return "{ \(trimmed); }; printf '\\n__AGENT_TERM_EXIT:%s\\n' $?\n"
    }

    /// From a terminal screen snapshot, return the output that belongs to `command`.
    /// If the snapshot contains a line `__AGENT_TERM_EXIT:N`, set exit and done.
    /// Strip that marker line from the returned text.
    static func output(from screen: String, command: String) -> (text: String, exit: Int?, done: Bool) {
        var candidate = slice(screen, afterLast: command)
        if candidate.hasPrefix("; };") || candidate.hasPrefix(";}") {
            if let nl = candidate.firstIndex(of: "\n") {
                candidate = String(candidate[candidate.index(after: nl)...])
            } else {
                candidate = ""
            }
        }
        if let printf = candidate.range(of: "printf"),
           let nl = candidate[printf.lowerBound...].firstIndex(of: "\n"),
           candidate[printf.lowerBound..<nl].contains("__AGENT_TERM_EXIT") {
            candidate = String(candidate[candidate.index(after: nl)...])
        }
        var lines = candidate.components(separatedBy: "\n")
        var exit: Int?
        var done = false
        if let index = lines.lastIndex(where: { markerExit($0) != nil }) {
            exit = markerExit(lines[index])
            done = true
            lines.remove(at: index)
            let blankBefore = index - 1
            if lines.indices.contains(blankBefore), lines[blankBefore].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.remove(at: blankBefore)
            }
        }
        return (trimTrailing(lines.joined(separator: "\n")), exit, done)
    }

    private static func slice(_ screen: String, afterLast command: String) -> String {
        guard command.isEmpty == false, let range = screen.range(of: command, options: .backwards) else {
            return screen
        }
        return String(screen[range.upperBound...])
    }

    private static func markerExit(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = "__AGENT_TERM_EXIT:"
        guard trimmed.hasPrefix(prefix) else { return nil }
        return Int(trimmed.dropFirst(prefix.count))
    }

    private static func trimTrailing(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text[previous].isWhitespace else { break }
            end = previous
        }
        return String(text[..<end])
    }
}
