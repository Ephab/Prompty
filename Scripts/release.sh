#!/bin/zsh
# Builds Prompty and publishes dist/Prompty.zip as a GitHub release for the
# version in Resources/Info.plist. Needs the GitHub CLI (`gh auth login`).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
TAG="v$VERSION"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
	print -u2 "Commit your changes before releasing."
	exit 1
fi

"$ROOT_DIR/Scripts/package.sh"
git -C "$ROOT_DIR" push origin HEAD
gh release create "$TAG" "$ROOT_DIR/dist/Prompty.zip" \
	--repo Ephab/Prompty \
	--target "$(git -C "$ROOT_DIR" rev-parse HEAD)" \
	--title "Prompty $VERSION" \
	--generate-notes
