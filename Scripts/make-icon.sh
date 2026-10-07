#!/bin/zsh
# Regenerates Resources/AppIcon.icns from Scripts/make-icon.swift.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
export CLANG_MODULE_CACHE_PATH="$WORK_DIR/clang-cache"
export SWIFT_MODULECACHE_PATH="$WORK_DIR/swift-cache"

SDK_PATH="${PROMPTY_SDK:-$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)}"
SDK_FLAGS=()
if [[ -n "$SDK_PATH" ]]; then
	SDK_FLAGS=(-sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx26.0")
fi

swiftc "${SDK_FLAGS[@]}" "$ROOT_DIR/Scripts/make-icon.swift" -o "$WORK_DIR/make-icon"
"$WORK_DIR/make-icon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Resources/AppIcon.icns"
printf 'Wrote %s\n' "$ROOT_DIR/Resources/AppIcon.icns"
