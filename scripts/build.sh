#!/bin/zsh
# ponytail: swift build cannot link its own manifest on this machine
# (Command Line Tools libPackageDescription is older than the compiler).
# Compile with swiftc. Delete this when `swift test` works.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTTERM="${SWIFTTERM:-/tmp/stprobe/repo}"
SDK="$(xcrun --show-sdk-path)"
OUT="$ROOT/.build-direct"
HEAD="$OUT/headless"
UI="$OUT/ui"
mkdir -p "$OUT" "$HEAD" "$UI"

OVERLAY="$OUT/hide-bridging.yaml"
EMPTY="$OUT/empty.modulemap"
printf '// hidden\n' > "$EMPTY"
python3 - "$OVERLAY" "$EMPTY" << 'PY'
import json, sys
json.dump({
    "version": 0,
    "roots": [{
        "name": "/Library/Developer/CommandLineTools/usr/include/swift",
        "type": "directory",
        "contents": [{
            "name": "bridging.modulemap",
            "type": "file",
            "external-contents": sys.argv[2],
        }],
    }],
}, open(sys.argv[1], "w"))
PY

# ponytail: TTImage is declared in Apple/AppleTerminalView.swift, which pulls in
# AppKit. The headless core never draws, so a stub satisfies ImageCell.

# ponytail: TerminalViewSearch.swift is excluded; Mac find-bar still calls these.
printf '%s\n' \
    'extension TerminalView {' \
    '    @discardableResult' \
    '    public func findNext(_ term: String, options: SearchOptions = SearchOptions(), scrollToResult: Bool = true) -> Bool { false }' \
    '    @discardableResult' \
    '    public func findPrevious(_ term: String, options: SearchOptions = SearchOptions(), scrollToResult: Bool = true) -> Bool { false }' \
    '    public func clearSearch() {}' \
    '}' > "$OUT/SearchStub.swift"
ui=("$OUT/SearchStub.swift")
printf 'public class TTImage {}\n' > "$OUT/TTImage.swift"
st=("$OUT/TTImage.swift")
while IFS= read -r f; do st+=("$f"); done < <(find "$SWIFTTERM/Sources/SwiftTerm" -name '*.swift' \
    -not -path '*/Mac/*' -not -path '*/iOS/*' -not -path '*/Apple/*' \
    -not -name 'TerminalViewSearch.swift')
while IFS= read -r f; do ui+=("$f"); done < <(find "$SWIFTTERM/Sources/SwiftTerm" -name '*.swift' \
    -not -path '*/iOS/*' -not -name 'TerminalViewSearch.swift')

HEAD_COMMON=(-sdk "$SDK" -target arm64-apple-macosx15.0 -vfsoverlay "$OVERLAY")
UI_COMMON=(-sdk "$SDK" -target arm64-apple-macosx14.0 -vfsoverlay "$OVERLAY")

echo "compiling SwiftTerm headless (${#st[@]} files)"
xcrun swiftc "${HEAD_COMMON[@]}" -emit-module -emit-library \
    -module-name SwiftTerm -emit-module-path "$HEAD/SwiftTerm.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libSwiftTerm.dylib \
    -o "$HEAD/libSwiftTerm.dylib" "${st[@]}"

echo "compiling SwiftTerm UI (${#ui[@]} files)"
xcrun swiftc "${UI_COMMON[@]}" -emit-module -emit-library \
    -module-name SwiftTerm -emit-module-path "$UI/SwiftTerm.swiftmodule" \
    -o "$UI/libSwiftTermUI.dylib" "${ui[@]}"
cp -f "$UI/SwiftTerm.swiftmodule" "$OUT/SwiftTerm.swiftmodule"
cp -f "$UI/libSwiftTermUI.dylib" "$OUT/libSwiftTermUI.dylib"

echo "compiling TermCore"
xcrun swiftc "${HEAD_COMMON[@]}" -I "$HEAD" -L "$HEAD" -lSwiftTerm \
    -emit-module -emit-library \
    -module-name TermCore -emit-module-path "$HEAD/TermCore.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libTermCore.dylib \
    -o "$HEAD/libTermCore.dylib" \
    "$ROOT/Sources/TermCore/Session.swift" \
    "$ROOT/Sources/TermCore/Screen.swift" \
    "$ROOT/Sources/TermCore/Pane.swift" \
    "$ROOT/Sources/TermCore/Workspace.swift" \
    "$ROOT/Sources/TermCore/Gate.swift"

echo "compiling tests"
xcrun swiftc "${HEAD_COMMON[@]}" -I "$HEAD" -L "$HEAD" -lTermCore -lSwiftTerm \
    -emit-executable \
    -o "$HEAD/TermCoreTests" \
    "$ROOT/Tests/TermCoreTests/Runner.swift"

echo "compiling feature tests"
xcrun swiftc "${HEAD_COMMON[@]}" -I "$HEAD" -L "$HEAD" -lTermCore -lSwiftTerm \
    -emit-executable \
    -o "$HEAD/FeatureTests" \
    "$ROOT/Tests/TermCoreTests/FeatureRunner.swift"

echo "compiling gate"
xcrun swiftc "${HEAD_COMMON[@]}" -I "$HEAD" -L "$HEAD" -lTermCore -lSwiftTerm \
    -Xlinker -rpath -Xlinker @executable_path \
    -emit-executable \
    -o "$HEAD/gate" \
    "$ROOT/Sources/GateCLI/main.swift"

echo "running"
DYLD_LIBRARY_PATH="$HEAD" "$HEAD/TermCoreTests"
DYLD_LIBRARY_PATH="$HEAD" "$HEAD/FeatureTests"

echo "compiling TermApp"
APP="$OUT/TermApp.app/Contents/MacOS"
RES="$OUT/TermApp.app/Contents/Resources"
mkdir -p "$APP" "$RES"
xcrun swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
    -vfsoverlay "$OVERLAY" \
    -I "$OUT" -L "$OUT" -lSwiftTermUI \
    -emit-executable -o "$APP/TermApp" "$ROOT"/Sources/TermApp/*.swift
cp -f "$APP/TermApp" "$OUT/TermApp"
cat > "$OUT/TermApp.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TermApp</string>
<key>CFBundleIdentifier</key><string>dev.agent-term</string>
<key>CFBundleName</key><string>agent-term</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if xcrun -sdk macosx metal -c "$SWIFTTERM/Sources/SwiftTerm/Apple/Metal/Shaders.metal" -o "$OUT/Shaders.air" \
    && xcrun -sdk macosx metallib "$OUT/Shaders.air" -o "$RES/default.metallib"; then
  echo "metal library ready"
else
  cp -f "$SWIFTTERM/Sources/SwiftTerm/Apple/Metal/Shaders.metal" "$RES/Shaders.metal"
  echo "metal compiler unavailable; bundled shader source"
fi
