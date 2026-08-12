# Release checklist — local rehearsal

Phase 7a taught Pium to update itself with Sparkle. An update path that has
never run is not an update path, so before any release credential exists this
document exercises the full loop locally: a `file://` feed, a locally signed
appcast, and a 0.1.0 → 0.2.0 update walked by hand. Task 11 adds the second
half of this document — the real release pipeline, once the five repository
secrets exist.

Two parts follow. The first is what a machine verified, with the actual
commands and output. The second is what only a person can do — pressing a
global shortcut, watching a window appear, observing a relaunch — written so
someone can follow it without having read the plan that produced this file.

## What was verified automatically

Machine: Mac mini, Apple M4, 16 GB. macOS 26.5.2 (25F84). Xcode 26 (17F113).

### 1. Build and install 0.1.0

`/Applications/Pium.app` did not exist and Pium was not running, so installing
directly was safe.

```
$ xcodegen generate
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/lardissone/Developer/pium/Pium.xcodeproj

$ xcodebuild -scheme Pium -configuration Release -destination 'platform=macOS' \
    -derivedDataPath /tmp/pium-rehearsal archive \
    -archivePath /tmp/pium-rehearsal/Pium-0.1.0.xcarchive
...
** ARCHIVE SUCCEEDED **

$ cp -R /tmp/pium-rehearsal/Pium-0.1.0.xcarchive/Products/Applications/Pium.app /Applications/

$ plutil -p /Applications/Pium.app/Contents/Info.plist | grep -i "CFBundleShortVersionString\|CFBundleVersion\|CFBundleIdentifier"
  "CFBundleIdentifier" => "com.lardissone.pium"
  "CFBundleShortVersionString" => "0.1.0"
  "CFBundleVersion" => "1"
```

### 2. Build 0.2.0 and package it

`project.yml`'s `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` were bumped to
`0.2.0`/`2`, the project regenerated, and archived the same way:

```
$ xcodebuild -scheme Pium -configuration Release -destination 'platform=macOS' \
    -derivedDataPath /tmp/pium-rehearsal archive \
    -archivePath /tmp/pium-rehearsal/Pium-0.2.0.xcarchive
...
** ARCHIVE SUCCEEDED **

$ mkdir -p /tmp/pium-feed
$ ditto -c -k --sequesterRsrc --keepParent \
    /tmp/pium-rehearsal/Pium-0.2.0.xcarchive/Products/Applications/Pium.app \
    /tmp/pium-feed/Pium-0.2.0.zip

$ ls -la /tmp/pium-feed/
-rw-r--r--@  1 lardissone  wheel  4696514 Aug 12 16:29 Pium-0.2.0.zip

$ shasum -a 256 /tmp/pium-feed/Pium-0.2.0.zip
424635fc955a8a4a03ddbb7c15f78b28c77dad2d09343e36e462f1c281865f07  Pium-0.2.0.zip

$ unzip -l /tmp/pium-feed/Pium-0.2.0.zip | head
Archive:  /tmp/pium-feed/Pium-0.2.0.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  08-12-2026 16:29   Pium.app/
        0  08-12-2026 16:29   Pium.app/Contents/
        ...
```

`Pium.app/` sits at the top of the archive, as `--keepParent` requires for
Sparkle to unpack it correctly. The zip's own `CFBundleShortVersionString` was
confirmed as `0.2.0` (`CFBundleVersion` `2`) before packaging.

`project.yml` was then reverted to `0.1.0`/`1` and the project regenerated
again; `git diff` against `HEAD` came back empty. **The 0.2.0 bump was never
committed** — the release workflow sets versions from the tag, and a version
committed by hand would disagree with one.

### 3. Point the installed 0.1.0 at the local feed

```
$ defaults write com.lardissone.pium SUFeedURL 'file:///tmp/pium-feed/appcast.xml'
$ defaults read com.lardissone.pium SUFeedURL
file:///tmp/pium-feed/appcast.xml
```

This is a user default, so it overrides the `SUFeedURL` baked into the
installed app's `Info.plist` (still the GitHub release URL) without touching
the bundle.

### 4. Generate and verify the signed appcast — NOT COMPLETED

This is where the automatable half stops. It could not be finished headlessly,
and the reason is worth recording precisely rather than papering over.

```
$ /tmp/sparkle/bin/generate_appcast /tmp/pium-feed
```

This command produced no output and did not return. `ps aux` while it was
running showed:

```
lardissone  39645  ...  /tmp/sparkle/bin/generate_appcast /tmp/pium-feed
lardissone  39646  ...  /System/Library/.../SecurityAgent.bundle/Contents/MacOS/SecurityAgent
```

`generate_appcast` reads the EdDSA private key from the login Keychain (as
Task 1 set up). Both `generate_appcast` and `sign_update` are ad-hoc signed
with no Team ID:

```
$ codesign -dv /tmp/sparkle/bin/generate_appcast
CodeDirectory v=20500 ... flags=0x10002(adhoc,runtime) ...
TeamIdentifier=not set
```

Because neither binary has ever touched this Keychain item before, and
neither carries a stable Team ID the Keychain ACL could have pre-trusted, the
first access from each one triggers a macOS Keychain confirmation dialog —
the "generate_appcast wants to use your confidential information stored in
'Private key for signing Sparkle updates' in your keychain" prompt, asking to
click Allow, Always Allow, or Deny. That dialog needs a person at the screen;
there is no non-interactive way to answer it, and none was attempted — this
machine has no login-keychain password available to script around it, and
scripting around a Keychain access-control prompt is not something to do
quietly even if one did.

The process was killed after confirming it was blocked on this dialog rather
than doing any real work (120+ seconds with zero output, `SecurityAgent`
alive, nothing written to `/tmp/pium-feed`). **No `appcast.xml` exists yet.**
Because of this, the appcast's existence, its version, its `sparkle:edSignature`,
its enclosure URL/length, and whether that signature validates against
`e+uU8/nj3yePBYLz1yV9EZZM824YeiqQj68wzqtjGbE=` were **not verified** — there
was nothing to check. Saying otherwise would be worse than saying nothing.

`sign_update`'s `--verify` mode (`sign_update --verify <file> [<signature>]`)
is the right tool for the signature check once an appcast exists, per its
`--help`:

```
OVERVIEW: Sign or verify an update file using your signing keys.
...
--verify   Verify that the file is signed correctly. If this is set, a second
           argument <verify-signature> denoting the signature must be passed
           after the <update-path>.
```

It reads keys the same way `generate_appcast` does (`--account`, default
`ed25519`, matching the Keychain item's `acct` attribute confirmed via
`security dump-keychain`), so it is expected to hit the same kind of
first-access prompt, separately, the first time it runs.

## What needs a person

Nothing below has been run. Every result line is unfilled on purpose — do not
check a box you did not personally watch happen.

### Setup

Three directories the steps below need. The section above used the values on
the right; `/tmp` does not survive a restart, so set them to wherever these
live on the machine doing the walk:

```bash
export SPARKLE_BIN=/tmp/sparkle/bin       # Sparkle's distribution tools
export FEED_DIR=/tmp/pium-feed            # holds the 0.2.0 zip and the appcast
export REHEARSAL_DIR=/tmp/pium-rehearsal  # the 0.1.0 and 0.2.0 archives
```

All three must already hold what the automated section built:
`$SPARKLE_BIN/generate_appcast` and `$SPARKLE_BIN/sign_update` from Sparkle's
distribution, `$FEED_DIR/Pium-0.2.0.zip`, and the two `.xcarchive`s in
`$REHEARSAL_DIR`. If the archives or the zip are gone, rebuild them by following
sections 1–3 above with these variables in place of the literal paths. The tools
are not built here — they ship in Sparkle's own release, and `$SPARKLE_BIN` is
where that tarball was unpacked:

```bash
curl -fsSL -o /tmp/Sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.5/Sparkle-2.9.5.tar.xz
mkdir -p "$(dirname "$SPARKLE_BIN")"
tar -xJf /tmp/Sparkle.tar.xz -C "$(dirname "$SPARKLE_BIN")"
```

The version must match the one `project.yml` pins, because the appcast is
signed by these tools and verified by the app. `/Applications/Pium.app`
must be the 0.1.0 build, and the feed default must point into `$FEED_DIR`:

```bash
defaults write com.lardissone.pium SUFeedURL "file://$FEED_DIR/appcast.xml"
```

Steps 0–1 finish what could not be finished headlessly; steps 2–5 are the walk
from the brief.

### Step 0 — generate the signed appcast (required first)

```bash
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "file://$FEED_DIR/" "$FEED_DIR"
```

`--download-url-prefix` is not optional here. Without it `generate_appcast`
builds each enclosure URL from the app's own `SUFeedURL` — the GitHub release
URL — and writes an appcast pointing at a release that does not exist. Sparkle
would find the update and then fail to download it, several steps later, for a
reason that has nothing to do with what is being rehearsed.

**What to expect:** a Keychain dialog — "generate_appcast wants to use your
confidential information stored in 'Private key for signing Sparkle updates'
in your keychain." Click **Always Allow** (Allow works too, but you will be
asked again on the next release). The command then prints what it wrote and
exits; `$FEED_DIR/appcast.xml` should exist afterward.

Check it:

```bash
cat "$FEED_DIR/appcast.xml"
```

**What it should show:** an item for version `0.2.0`, an `enclosure` whose
`url` is `file://$FEED_DIR/Pium-0.2.0.zip` — spelled out, the local file, not
a `https://github.com/...` address — a `length` matching the zip on disk
(`stat -f%z "$FEED_DIR/Pium-0.2.0.zip"`; it was `4696514` for the build in the
section above), and a `sparkle:edSignature` attribute holding a base64
signature.

Result: ☐ appcast generated, version and enclosure look right — NOT YET RUN

### Step 1 — verify the signature

Open `$FEED_DIR/appcast.xml`, find the `enclosure` element for 0.2.0, and
copy its `sparkle:edSignature` value. Then:

```bash
"$SPARKLE_BIN/sign_update" --verify "$FEED_DIR/Pium-0.2.0.zip" '<paste the edSignature value here>'
```

**What to expect:** a second, separate Keychain dialog (this is a different
binary from `generate_appcast`, ad-hoc signed with no Team ID, so it is a
fresh trust decision) — click Always Allow. The tool should then print that
the signature is valid.

Result: ☐ signature verified against `e+uU8/nj3yePBYLz1yV9EZZM824YeiqQj68wzqtjGbE=` — NOT YET RUN

### Step 2 — Sparkle's own window, cancelled

With Pium (0.1.0) running (`open /Applications/Pium.app`):

1. Click the menubar icon → **Check for Updates…**
2. **What to expect:** Sparkle's own update window appears, offering 0.2.0.
   Click **Cancel** — the point of this step is only that the window appears
   at all when explicitly requested.

Result: ☐ Sparkle's window appeared and offered 0.2.0 — NOT YET RUN

### Step 3 — a relaunch waits for a running plugin

1. Start a long-running plugin — any example plugin command with a `sleep`
   works; run it from the launcher so it is executing.
2. Menubar → **Check for Updates…** → accept the 0.2.0 update this time
   (download, verify, install).
3. **What to expect:** the update installs, but Pium does **not** relaunch
   while the plugin command is still running. The relaunch happens only after
   the command finishes.

Result: ☐ the relaunch waited for the running plugin to finish — NOT YET RUN

If step 3 relaunches Pium as 0.2.0, steps 4 and 5 need version 0.1.0
reinstalled and the feed default re-pointed before they can be walked
(`cp -R "$REHEARSAL_DIR/Pium-0.1.0.xcarchive/Products/Applications/Pium.app" /Applications/`,
then repeat the `defaults write` from the setup section).

### Step 4 — a scheduled check surfaces a discreet notice, not a window

```bash
defaults write com.lardissone.pium SULastCheckTime -date '2020-01-01 00:00:00 +0000'
```

Quit and reopen Pium so the scheduled check has a chance to fire, then press
**⌥ Space** to open the launcher.

**What to expect:** the launcher opens normally, with a discreet notice row
about the available update — not Sparkle's own window. That window only
appears when the user explicitly asks via the menubar (step 2); a scheduled
find must never take over focus.

Result: ☐ the discreet notice appeared, no window stole focus — NOT YET RUN

### Step 5 — installing from the notice

1. Activate the notice row from inside the launcher.
2. **What to expect:** download, verify, install, and a relaunch.
3. Open **About Pium** (menubar) after the relaunch.

**What it should show:** version **0.2.0**.

Result: ☐ About reports 0.2.0 after installing from the notice — NOT YET RUN

## Cleanup

Once every result above is recorded — pass or fail, this is not optional —
run:

```bash
defaults delete com.lardissone.pium SUFeedURL
rm -rf "$FEED_DIR" "$REHEARSAL_DIR"
rm -rf /Applications/Pium.app
```

The last line removes the rehearsal install. It is safe once the walk above
is done — nothing about the real release depends on this copy of `Pium.app`
surviving.

`$SPARKLE_BIN` is deliberately not removed here. It may point at a directory
holding more than Sparkle's tools, and deleting the parent of a path someone
else supplied is not a thing a checklist should do. Unpacked under `/tmp`, it
goes on its own at the next restart.
