# Pium

A small, fast, native macOS launcher. A global shortcut opens a compact floating
bar above whatever you are doing; typing once searches applications,
Spotlight-indexed files, and file-based commands in a single ranked list.

Commands are plugins, and a plugin is one readable JSON file. Adding or changing
one never recompiles Pium.

**Status:** in development. Nothing is released yet.

## Building

Requires macOS 26 and Xcode 26.

The Xcode project is generated from `project.yml` and is not checked in, so
generate it before opening anything:

```bash
brew install xcodegen   # once
xcodegen generate
open Pium.xcodeproj
```

Rerun `xcodegen generate` after editing `project.yml`. Changes made to the
generated project are discarded on the next run.

From the command line:

```bash
xcodebuild test -project Pium.xcodeproj -scheme Pium -destination 'platform=macOS'
```

## License

MIT. See [LICENSE](LICENSE).
