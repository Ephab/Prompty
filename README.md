# Prompty

Prompty is a tiny macOS menu-bar app for storing and reusing prompts.

## Requirements

- macOS 26 or newer
- Swift 6.3 or newer (the Xcode Command Line Tools are enough)

## Build and test

```sh
swift build
./Scripts/check.sh
```

To assemble an ad-hoc signed app bundle:

```sh
./Scripts/package.sh
open dist/Prompty.app
```

The build script accepts `PROMPTY_BUILD_PATH` and `PROMPTY_DIST_PATH` when a
different local build or output directory is useful.

Prompty runs as a menu-bar-only application. Its default global shortcut is
Control–Option–Space. Prompt data is stored in
`~/Library/Application Support/Prompty/prompts.json`.
