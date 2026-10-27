# v1 — one window, one local PTY

Spike only. Prove a real shell runs inside an embeddable terminal on this machine.
Not a product. No tabs, no sidecar, no approval queue, no Metal, no agent hooks.

## Machine (measured)

- Apple Silicon, macOS, Swift 6.1.2, SwiftPM 6.1.0
- Active developer dir is Command Line Tools. `xcodebuild` is absent.
- Therefore: no `.xcodeproj`, no asset catalogs, no Interface Builder.
- AppKit imports compile under `swift build`. A previous one-off `swiftc -typecheck` failed on a CLT modulemap bug. Do not use bare `swiftc` for this.

## Dependency

SwiftTerm **v1.18.0** exactly (tag, not branch, not `from:`).

- v1.18.0 is `swift-tools-version:5.9`. v1.19.0 is 6.0. v1.99.x and current main are 6.2, which this Swift cannot load.
- MIT. Local PTY is `LocalProcess` (no AppKit). The view is `LocalProcessTerminalView` (AppKit).
- Do not bump the tag to make a compile error go away.

```swift
.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.18.0")
```

## Layout

```
Package.swift              tools 6.1, platform macOS 14
Sources/TermCore/          headless: spawn shell, feed bytes, read grid
Sources/TermApp/           AppKit shell around LocalProcessTerminalView
Tests/TermCoreTests/       XCTest, no AppKit
```

Two targets so tests never link AppKit.

## TermCore

`Session`:

- Owns a `LocalProcess`.
- `start()` runs `/bin/zsh -f` (no user rc) with `TERM=xterm-256color`, cwd = the process cwd.
- `send(_ bytes: [UInt8])` writes to the PTY.
- `terminate()` sends the process kill `LocalProcess` already exposes (`terminate()`).
- `onReady` fires once the child is running. `onExit` fires with the `Int32?` from `processTerminated`.
- Exposes `text` as the live screen joined by newlines, trailing empty rows stripped. One function, used by tests.
- Exposes `cell(col:row:)` returning the character and `Attribute.Color` foreground, or nil if out of range.

`LocalProcess` delivers bytes on its queue. `Terminal.feed(byteArray:)` consumes them. `getWindowSize` returns 80 columns by 24 rows, and that same pair is passed to `TerminalOptions` so the PTY size and the grid size match. Resize is out of scope. The app sets the view's real frame and lets SwiftTerm send `SIGWINCH`.

`TerminalOptions`, `getCharacter(col:row:)`, and `getCharData(col:row:) -> CharData?` exist on v1.18.0. `CharData.attribute.fg` is `Attribute.Color`. Red from `\033[31m` is `.ansi256(code: 1)`.

`startProcess` returning is not proof the child is running. Wait for the first `dataReceived` or for `processTerminated` before sending input. A failed exec terminates with status 127 and never produces output.

## TermApp

- `NSApplication` manual lifecycle. No `@main` AppKit storyboard.
- One window, one `LocalProcessTerminalView`, frame filled, autoresize width+height.
- `startProcess` only after the view has a non-zero frame. Executable `/bin/zsh`, args `["-f"]`.
- Activation policy `.regular`. Window title `agent-term`.
- Quit when the window closes.
- No preferences, no menus beyond the system ones AppKit creates.

## Tests (the definition of done)

All in `TermCoreTests`, `swift test`, no display required.

1. `start` + send `printf 'hi\\n'; exit\n` → screen text contains `hi`, process exits, exit code is observed.
2. `printf '\\033[2J\\033[H'` → live screen is cleared (row 0 is empty after the cursor homes).
3. `printf '\\033[31mred\\033[0m\\n'` → the cell for `r` has foreground `.ansi256(code: 1)`. Assert the attribute, not a pixel.
4. `terminate()` on a `sleep 30` returns within 2 seconds and the exit is observed.
5. Sending more bytes after exit does not crash and does not start a new process.

No snapshot tests. No SwiftTerm parser tests (upstream owns those).

## Acceptance

- `swift test` exits 0 on this machine.
- `swift run TermApp` opens a window whose shell accepts typing. Verified once by a human or a later pass. Agents do not need a passing GUI test in CI because there is no display harness.

## Out of scope (do not build)

tabs, splits, scrollback UI, Metal, ligatures toggle, sidecar, socket protocol, approval, sandbox, OSC 133, kitty keyboard extras, SSH, settings file, app bundle / code signing, icon.

## Build ownership

`TermCore` agent writes `Package.swift` and `Sources/TermCore/` only.
`TermApp` agent writes `Sources/TermApp/` only and does not edit `Package.swift`.
`Tests` agent writes `Tests/TermCoreTests/` only.
Nobody edits `PLAN.md`. Nobody adds a file outside their directory.

## Failure rule

If v1.18.0 does not compile, stop and report the error. Do not fork SwiftTerm. Do not upgrade the toolchain. Do not weaken a test to make it pass.
