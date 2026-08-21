#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT

export CLANG_MODULE_CACHE_PATH="$CHECK_DIR/clang-cache"
export SWIFT_MODULECACHE_PATH="$CHECK_DIR/swift-cache"

swiftc -parse-as-library \
    "$ROOT_DIR/Sources/Prompty/Prompt.swift" \
    "$ROOT_DIR/Sources/Prompty/PromptStore.swift" \
    "$ROOT_DIR/Checks/PromptStoreChecks.swift" \
    -o "$CHECK_DIR/PromptyChecks"

"$CHECK_DIR/PromptyChecks"
