import Foundation
import TermCore

if CommandLine.arguments.count != 2 || CommandLine.arguments[1] != "check" {
    fputs("usage: gate check\n", stderr)
    exit(2)
}

let data = FileHandle.standardInput.readDataToEndOfFile()
let command = String(data: data, encoding: .utf8) ?? ""
let gate = Gate(rules: [])
switch gate.check(command) {
case .allow:
    print("allow")
case .deny(let reason):
    print("deny\t\(reason)")
case .ask(let line):
    print("ask\t\(line)")
}
exit(0)
