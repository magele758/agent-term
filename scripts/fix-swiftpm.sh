#!/bin/zsh
# Command Line Tools swiftc emits Package.__allocating_init(..., swiftLanguageVersions: [SwiftVersion]).
# The installed libPackageDescription only exports SwiftLanguageMode. This shim aliases the old
# symbols onto the new ones, and hides the duplicate SwiftBridging modulemap.
set -euo pipefail
root="${0:A:h}/.."
tc="$HOME/Library/Developer/Toolchains/pd-fix.xctoolchain"
lib="$tc/usr/lib/pdshim"
real_src=/Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI/libPackageDescription.dylib
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
mkdir -p "$lib" "$tc/usr/bin" "$HOME/.local/bin"

cp "$real_src" "$lib/libPackageDescriptionReal.dylib"
install_name_tool -id '@rpath/libPackageDescriptionReal.dylib' "$lib/libPackageDescriptionReal.dylib"
codesign -s - --force "$lib/libPackageDescriptionReal.dylib"

python3 - "$lib/libPackageDescriptionReal.dylib" /tmp/agent-term-pd-aliases.txt << 'PY'
import subprocess, sys
nm = subprocess.check_output(["nm", "-arch", "arm64", "-gU", sys.argv[1]], text=True)
have = {line.split()[-1] for line in nm.splitlines() if line.split()}
pairs = []
for sym in sorted(have):
    if "17SwiftLanguageMode" in sym:
        pairs.append((sym, sym.replace("17SwiftLanguageMode", "12SwiftVersion")))
    if "05SwiftN4Mode" in sym:
        pairs.append((sym, sym.replace("05SwiftN4Mode", "12SwiftVersion")))
open(sys.argv[2], "w").write("".join(f"{a} {b}\n" for a, b in pairs))
print(f"aliases {len(pairs)}")
PY
alias_args=()
while read -r have want; do
  alias_args+=(-alias "$have" "$want")
done < /tmp/agent-term-pd-aliases.txt
xcrun ld -dylib -arch arm64 -platform_version macos 14.0.0 14.0.0 \
  -syslibroot "$sdk" \
  -install_name '@rpath/libPackageDescription.dylib' \
  -reexport_library "$lib/libPackageDescriptionReal.dylib" \
  "${alias_args[@]}" \
  -o "$lib/libPackageDescription.dylib"
codesign -s - --force "$lib/libPackageDescription.dylib"

printf '// hidden\n' > "$lib/empty.modulemap"
python3 - "$lib/hide-bridging.yaml" "$lib/empty.modulemap" << 'PY'
import json, sys
json.dump({
  "version": 0,
  "roots": [{
    "name": "/Library/Developer/CommandLineTools/usr/include/swift",
    "type": "directory",
    "contents": [{"name": "bridging.modulemap", "type": "file", "external-contents": sys.argv[2]}],
  }],
}, open(sys.argv[1], "w"))
PY

cat > "$tc/usr/bin/swiftc" << 'EOF'
#!/bin/zsh
real=/Library/Developer/CommandLineTools/usr/bin/swiftc
root="${0:A:h}/../lib/pdshim"
args=("$@")
for arg in "$@"; do
  if [[ "$arg" == "-lPackageDescription" ]]; then
    args=(-L "$root" -Xlinker -rpath -Xlinker "$root" "$@")
    break
  fi
done
exec "$real" "${args[@]}" -vfsoverlay "$root/hide-bridging.yaml"
EOF
chmod +x "$tc/usr/bin/swiftc"

cat > "$HOME/.local/bin/swift" << EOF
#!/bin/zsh
export SWIFT_EXEC="$tc/usr/bin/swiftc"
export SWIFT_EXEC_MANIFEST="\$SWIFT_EXEC"
exec /usr/bin/swift "\$@"
EOF
chmod +x "$HOME/.local/bin/swift"
echo "installed $HOME/.local/bin/swift"
echo "use: swift build --target TermApp"
