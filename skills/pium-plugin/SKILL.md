---
name: pium-plugin
description: Write, validate, and debug a plugin for Pium!, the macOS launcher. A plugin is one JSON manifest in ~/.config/pium/plugins/ that turns a command into a searchable result. Use when asked to create a Pium plugin, add a command or a search to Pium, or fix a plugin Pium reports as broken.
---

# Writing a Pium plugin

One JSON file describes one searchable command. It goes in
`~/.config/pium/plugins/`, its name ends in `.pium.json`, and Pium picks it up
without a restart.

A plugin runs as the user, with no review and no sandbox. Write only what the
person asked for, and say plainly what a command will do before they run it.

## The smallest one that works

```json
{
  "schemaVersion": 1,
  "id": "yourname.hello",
  "name": "Say hello",
  "command": { "executable": "say", "arguments": ["Hello"] }
}
```

`schemaVersion`, `id`, `name`, and `command` are required. Everything else is
optional: `description`, `keywords`, `aliases`, `icon` (an SF Symbol name),
`input`, `configuration`, `output`, `timeoutSeconds`, `confirmBeforeRun`.

## How to build one

1. **Read the schema before guessing a key.** It ships inside the app at
   `/Applications/Pium.app/Contents/Resources/PluginManifest.schema.json`, and
   in a clone at `Pium/Resources/PluginManifest.schema.json`. It is what the
   app enforces, so it is never out of date with the version on the machine.
   Three worked manifests sit beside it in `ExamplePlugins/`.
2. **Start from the smallest manifest and add one key at a time.**
3. **Validate**: `scripts/validate-manifest.py <file>.pium.json`, which reads
   that same schema. It needs no dependencies beyond `python3`.
4. **Install it** in `~/.config/pium/plugins/`, then look at Settings →
   Plugins. Every file in the folder is listed there, the broken ones with the
   reason. That list is the last word — a few rules live in the app rather than
   in the schema.
5. **Run it from the launcher** before calling it done.

## The things that go wrong

**There is no shell.** `executable` and `arguments` go to the kernel as an
argument array. Pipes, `>`, globs, `&&`, and `$VAR` are shell features and stay
literal text. Anything that needs them goes in a script with a `#!/bin/sh`
first line, and the manifest points at the script:

```json
"command": { "executable": "./report.sh", "arguments": ["{{input}}"] }
```

A relative `executable` resolves against the manifest's own folder, so a plugin
can ship its script beside itself.

**A bare name is looked up on Pium's own path**, not your shell's:
`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`,
`/sbin`, then anything added in Settings → Advanced. If the tool lives anywhere
else, write the absolute path.

**Always `url_encode` a value that lands in a URL.**
`{{input|url_encode}}`, never `{{input}}`, or a query containing `&` or `#`
silently becomes a different request.

**A `secret` configuration field cannot be interpolated into `arguments`.**
Trying stops the plugin from running at all. Arguments are visible in the
process table; the environment is not. Every configuration field arrives in the
child process as its `environmentVariable` — have the command read it there.

**Unknown keys are an error, not a warning.** `arguemnts` does not get ignored;
the plugin does not run.

**`id` keys the usage history.** It must be stable, globally unique across the
folder, and lowercase (`yourname.thing`). Changing it makes Pium forget
everything it learned about that plugin.

**One argument, maximum.** `input.mode` is `none`, `optional`, or `required`,
and `{{input}}` is the whole of it.

## Configuration

A server address or an API token belongs here rather than in the file. The user
fills it in Settings → Plugins; a `secret` goes to the Keychain.

```json
"configuration": [
  {
    "key": "baseURL",
    "label": "Home Assistant URL",
    "type": "string",
    "required": true,
    "environmentVariable": "PIUM_CONFIG_BASE_URL"
  }
]
```

`key` takes no dots and cannot be `input`; `environmentVariable` is capitals,
digits and underscores. Both are unique within the plugin — a rule the schema
cannot express and Settings will report.

## Output, timeout, confirmation

- `"output": { "mode": "toast" }` shows what the command printed on stdout.
  `silent` (the default) shows nothing on success. **A failure is always
  shown.** Pium parses no JSON: print the sentence a person should read.
- `"timeoutSeconds": 30` sends `SIGTERM`, waits two seconds, then `SIGKILL`.
  Absent means it waits forever.
- `"confirmBeforeRun": "This restarts the server."` asks every time, with no
  way to turn it off. Put it on anything destructive.

## What version 1 deliberately does not do

Several arguments or typed ones, localized `name` and `description` (put
translations in `keywords`), custom icons, several commands in one file,
retries, streaming, and interactive commands. Do not build a workaround for
these — say that the format does not do it.

## Reference

The full format, with every rule spelled out, is
[docs/plugin-format-v1.md](https://github.com/lardissone/pium/blob/main/docs/plugin-format-v1.md).
