# Contributing

Pium is a small, personal project that happens to be open. Issues and pull
requests are welcome; so is being told an idea is out of scope.

## Before you write code

**Open an issue first for anything larger than a fix.** The MVP scope is
deliberately narrow and a fair amount is settled — the product document lists
what is intentionally excluded. A pull request that adds a feature from that
list will not be merged however good it is, and finding that out after the work
is the worst possible order.

Fixes need no ceremony. Fix it and send it.

## Getting it building

Requires macOS 26 and Xcode 26.

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project Pium.xcodeproj -scheme Pium -destination 'platform=macOS'
```

`Pium.xcodeproj` is **generated from `project.yml` and is not checked in**. Edit
the YAML, never the project — the next `xcodegen generate` discards anything
else. Adding a file means regenerating, or it is silently not in the target.

Signing uses your own team, which is not checked in. Create `Local.xcconfig` in
the repository root:

```
DEVELOPMENT_TEAM = YOURTEAMID
```

Without it the unit tests still run
(`-only-testing:PiumTests CODE_SIGNING_ALLOWED=NO`), but the UI tests and any
signed build do not.

## House style

The code has a voice. Matching it matters more than any rule below, and reading
a neighbouring file is the fastest way to learn it.

**Comments say what or why, never what changed.** No "new", "legacy", "wrapper",
"unified", "enhanced". No "previously" or "moved from". The code is evergreen:
somebody reading it in a year has no idea what it replaced and should not need
to.

**Names describe what a thing does, not how it was built.** `ExecutionEnding`,
not `ExecutionEndingV2`.

**Everything is in English** — code, comments, commit messages, documents.

**Explain the decisions that look wrong.** Most comments in this codebase exist
because something surprising is going on: a lock where an actor would seem
natural, `posix_spawn` where `Process` would, a check that appears redundant.
If you had to think about it, write down what you thought.

## Tests

**swift-testing** (`import Testing`, `@Test`, `#expect`) for unit and
integration tests. **XCTest only for XCUITest**, which is the one thing
swift-testing does not cover.

Write the test first, and watch it fail before making it pass. A test that has
never failed has never been shown to test anything.

A few local hazards, learned the hard way:

- **`#expect` with a literal right-hand side** type-checks as `Int`, and an
  `Int` never equals a `CGFloat` or a `TimeInterval`. Bind the expected value
  to a typed constant first.
- **The Xcode test host ignores `SIGTERM`**, so two execution tests cannot
  discriminate under it. They say so in their own comments. Do not "fix" them.
- **Never pass `CODE_SIGNING_ALLOWED=NO` to a UI test.** The runner refuses to
  load a bundle signed differently from itself. That flag is for the unit tests.
- **A UI test cannot execute a script the runner wrote** — the sandboxed runner
  marks files as quarantined and the kernel refuses them. UI fixtures run
  system binaries.

## Pull requests

Run the full suite before opening one.

Say **why** in the description, not just what: the diff already says what. If
you decided something a reviewer might disagree with, say that you decided it
and why the alternative lost. That is the part worth reading.

One PR, one subject. A fix bundled with a refactor is two reviews wearing one
coat.

## Plugins

A plugin is a JSON file, not a code change. If you wrote one worth sharing,
open an issue describing it — the repository ships a small set of examples and
the bar is that an example teaches something the others do not.

The format is documented in
[docs/plugin-format-v1.md](docs/plugin-format-v1.md), and the schema in
`Pium/Resources/PluginManifest.schema.json` is what the app actually enforces.

## Security

Do not open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).
