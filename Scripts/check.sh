#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT

export CLANG_MODULE_CACHE_PATH="$CHECK_DIR/clang-cache"
export SWIFT_MODULECACHE_PATH="$CHECK_DIR/swift-cache"

# The macOS 27 SDK in the Command Line Tools expands SwiftUI's @State as a
# macro whose plugin ships only with Xcode, so build against a macOS 26 SDK
# when one is installed. Override with PROMPTY_SDK.
SDK_PATH="${PROMPTY_SDK:-$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)}"
SDK_FLAGS=()
if [[ -n "$SDK_PATH" ]]; then
	SDK_FLAGS=(-sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx26.0")
fi

swiftc "${SDK_FLAGS[@]}" -parse-as-library \
    "$ROOT_DIR/Sources/Prompty/Prompt.swift" \
    "$ROOT_DIR/Sources/Prompty/PromptStore.swift" \
    "$ROOT_DIR/Checks/PromptStoreChecks.swift" \
    -o "$CHECK_DIR/PromptyChecks"

"$CHECK_DIR/PromptyChecks"
