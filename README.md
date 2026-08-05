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

Signing uses your own team, which is not checked in. Create `Local.xcconfig`
in the repository root:

```
DEVELOPMENT_TEAM = YOURTEAMID
```

The ID is in Xcode → Settings → Accounts. Without it the unit tests still run
(`-only-testing:PiumTests CODE_SIGNING_ALLOWED=NO`), but `PiumUITests` and any
signed build do not. See [Signing.xcconfig](Signing.xcconfig).

From the command line:

```bash
xcodebuild test -project Pium.xcodeproj -scheme Pium -destination 'platform=macOS'
```

## License

MIT. See [LICENSE](LICENSE).
