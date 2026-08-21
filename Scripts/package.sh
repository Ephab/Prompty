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

swift build \
	--package-path "$ROOT_DIR" \
	--configuration release \
	--product Prompty \
	--build-path "$BUILD_DIR"

BIN_DIR="$(swift build \
	--package-path "$ROOT_DIR" \
	--configuration release \
	--product Prompty \
	--build-path "$BUILD_DIR" \
	--show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/Prompty" "$APP_DIR/Contents/MacOS/Prompty"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod 755 "$APP_DIR/Contents/MacOS/Prompty"

plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

printf 'Built %s\n' "$APP_DIR"
