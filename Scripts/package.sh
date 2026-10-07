#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROMPTY_BUILD_PATH:-$ROOT_DIR/.build}"
DIST_DIR="${PROMPTY_DIST_PATH:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/Prompty.app"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"

# Keep compiler caches inside the project so packaging also works in managed
# environments where the user-level Swift and Clang caches are unavailable.
mkdir -p "$MODULE_CACHE_DIR/clang" "$MODULE_CACHE_DIR/swift"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# The macOS 27 SDK in the Command Line Tools expands SwiftUI's @State as a
# macro whose plugin ships only with Xcode, so build against a macOS 26 SDK
# when one is installed. Override with PROMPTY_SDK.
SDK_PATH="${PROMPTY_SDK:-$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)}"
SDK_FLAGS=()
if [[ -n "$SDK_PATH" ]]; then
	SDK_FLAGS=(-sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx26.0")
fi

swiftc "${SDK_FLAGS[@]}" -O -parse-as-library \
	"$ROOT_DIR"/Sources/Prompty/*.swift \
	-o "$APP_DIR/Contents/MacOS/Prompty"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
chmod 755 "$APP_DIR/Contents/MacOS/Prompty"

plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

rm -f "$DIST_DIR/Prompty.zip"
ditto -c -k --keepParent "$APP_DIR" "$DIST_DIR/Prompty.zip"

printf 'Built %s and %s\n' "$APP_DIR" "$DIST_DIR/Prompty.zip"
