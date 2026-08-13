# Security

## Reporting a vulnerability

Open a [private security advisory](https://github.com/lardissone/pium/security/advisories/new).
Please do not open a public issue for a vulnerability.

This is a personal project maintained by one person. Expect a first reply
within a week. There is no bounty.

## What Pium is, in security terms

Pium runs commands you wrote, on your Mac, with your privileges. That is the
product, not a flaw in it. **A plugin can do anything you can do**, and Pium
does not review it before it runs — it reached your plugins folder because you
put it there.

So the boundary Pium defends is not "the user against their own plugins". It is
narrower and it is real:

- A command is never handed to a shell.
- A secret never appears where another process can read it.
- A manifest that does not make sense cannot run at all.

Anyone who can write to `~/.config/pium/plugins/` can already run code as you by
easier means. A trust gate there would charge every legitimate edit for a
boundary already crossed.

## What Pium guarantees

**No implicit shell.** `executable` and `arguments` go to the kernel as an
argument array through `posix_spawn`. A plugin cannot smuggle a pipe, a
redirection, or a `$(…)` through an argument, because nothing expands them.

**Secrets are never in the process table.** A `secret` configuration field
reaches the command only as an environment variable. Interpolating one into
`arguments` is a validation error that stops the plugin from running — process
arguments are readable by every process on the machine, and environments are
not.

**Secrets live in the Keychain.** Never in the manifest, never in Pium's
preferences, never in usage history, never in a Git repository you keep your
plugins in.

**The child's environment is an allowlist.** `PATH`, `HOME`, `USER`, `LANG`,
`TMPDIR`, plus exactly what the manifest declares. Pium does not pass on its own
environment: what it carries depends on whether it was opened from the Finder or
a terminal, and a plugin whose behaviour follows from that is a bug nobody can
reproduce.

**`PATH` is controlled.** A fixed list, plus whatever you add in Settings →
Advanced, and additions are always searched *after* the defaults so a directory
you add cannot shadow `/usr/bin/git` with another `git`.

**Cancellation reaches the whole tree.** Every command runs in a process group
of its own, so cancelling sends `SIGTERM` to the group — the command and
everything it started — then `SIGKILL` two seconds later. A plugin cannot leave
orphans behind by backgrounding something.

**Nothing leaves the Mac.** No telemetry, no analytics, no account, no backend.
Pium makes exactly two kinds of network request: the ones plugins you wrote
make, and an update check. The update check sends nothing about you — it is a
fetch of a static file.

## Updates

Pium updates itself with [Sparkle](https://sparkle-project.org). The properties
that matter, all of them read from the application bundle rather than from
preferences, so no stored setting can turn them off:

**Every update is signature-checked before it runs.** The appcast names an
EdDSA signature for each archive, and Sparkle refuses to install one that does
not verify against the public key compiled into the app. A tampered download is
rejected without being launched. The feed itself is fetched over HTTPS.

**Nothing installs without you saying so.** Pium checks every six hours and
tells you when something is waiting, but the download and the install happen
only when you ask for them. Sparkle's "download and install automatically"
option is switched off in the bundle, which both hides the checkbox and pins
the behaviour — so it cannot be turned on by accident, and there is no state a
future version silently inherits.

**A check never interrupts you.** An available update appears as a row in the
launcher the next time you open it, not as a window over whatever you were
doing.

Pium also holds its relaunch while a plugin command is still running, so an
update does not cut one off mid-way. That one is written and unit-tested but
has not yet been walked end to end against a real Sparkle install, so it is
described here as intent rather than listed as a guarantee.

The signing key for updates is held by the maintainer and is not in this
repository. It is deliberately never rotated: an install trusts the key that
shipped inside it, so replacing the key would strand every existing copy of
Pium with no way to update itself back.

## Debug logging, and what it cannot hide

Debug logging is off by default. While on, it records what you type, the
arguments you pass, the commands Pium runs, and what they print, in
`~/Library/Application Support/Pium/DebugLogs/`, readable only by your account.
It stops on its own after 24 hours.

Two layers remove declared secrets:

1. A secret never reaches the logger. A run's environment is recorded as
   variable *names*.
2. A run's own secret values are removed from its `stdout` and `stderr` before
   they are written — the case where a script prints what it was handed.

**A secret you type by hand into a plugin's argument is recorded and cannot be
removed.** Pium cannot tell it apart from a search term. Read an exported log
before sending it to anyone; the export warns you again for this reason.

## Things Pium deliberately does not do

- **No plugin signing, fingerprinting, or trust prompt.** See above: it would
  defend a boundary already crossed.
- **No App Sandbox.** Pium must run local tools, read `~/.config`, and search
  your files. Hardened Runtime and Developer ID signing apply to releases.
- **No Full Disk Access request.** File search uses Spotlight, and asks for
  Documents, Desktop, and Downloads individually, each with a reason. If macOS
  refuses one, Pium says so instead of failing silently.
- **No automatic retries.** A command that failed is not run again behind your
  back.

## Supported versions

Nothing is released yet. Once releases begin, the latest release is the
supported one.
