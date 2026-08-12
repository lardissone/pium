# Pium plugin format, version 1

One JSON file describes one searchable command. Put it in
`~/.config/pium/plugins/` with a name ending in `.pium.json`, and Pium picks it
up without a restart.

A plugin is your own code. Pium does not review what it does before it runs —
it reaches your plugins folder because you put it there. What Pium does
guarantee is narrower and worth knowing: no shell is involved, your secrets
never enter the command line, and a manifest that does not make sense cannot
run at all.

The machine-readable version of everything below is
[`Pium/Resources/PluginManifest.schema.json`](../Pium/Resources/PluginManifest.schema.json),
which ships inside the app and is confronted by a test, so it cannot drift from
what Pium accepts.

## The smallest plugin that works

```json
{
  "schemaVersion": 1,
  "id": "demo.hello",
  "name": "Say hello",
  "command": { "executable": "say", "arguments": ["Hello"] }
}
```

Four keys are required: `schemaVersion`, `id`, `name`, and `command`.

## Every key

| Key | Type | Required | What it does |
|---|---|---|---|
| `schemaVersion` | integer | yes | Always `1`. |
| `id` | string | yes | Stable and globally unique. Keys your usage history — change it and Pium forgets what it learned. |
| `name` | string | yes | Shown in the result list, and its normalised form is an automatic trigger. |
| `description` | string | no | Shown as the result's subtitle. |
| `keywords` | array of strings | no | Extra words that match this plugin. Put translations here — v1 does not localize a plugin's own text. |
| `aliases` | array of strings | no | Extra triggers. Two plugins claiming one alias is reported, and neither steals it. |
| `icon` | string | no | An SF Symbol name. An unknown symbol falls back to a generic one rather than failing. |
| `input` | object | no | `mode` is `none`, `optional`, or `required`; `placeholder` is the grey text shown while typing the argument. Defaults to `none`. |
| `command` | object | yes | `executable`, `arguments`, `workingDirectory`. See below. |
| `configuration` | array | no | Values the user fills in Settings. See below. |
| `output` | object | no | `mode` is `silent` or `toast`. Defaults to `silent`. |
| `timeoutSeconds` | integer | no | 1 to 3600. Absent means no timeout. |
| `confirmBeforeRun` | string | no | A sentence shown before every run. The user confirms every time; there is no "don't ask again". |

Unknown keys are an error, not a warning. A typo like `arguemnts` is reported
where you can see it rather than silently ignored.

## `id`

Lowercase letters, digits, dots, and hyphens, starting and ending with a letter
or digit. `web.youtube-search` is fine; `Web.YouTube` is not.

Use a prefix you control — `yourname.thing` — because ids are global across
everything in the folder.

## `command`

```json
"command": {
  "executable": "curl",
  "arguments": ["-s", "https://example.com/?q={{input|url_encode}}"],
  "workingDirectory": "."
}
```

**`executable`** is resolved three ways, in this order of shape:

1. **An absolute path** — `/opt/homebrew/bin/jq` — used as written.
2. **A relative path** — `./fetch.sh` — resolved against the folder the
   manifest is in, so a plugin can ship its own script beside itself.
3. **A bare name** — `curl` — looked up along Pium's controlled search path:
   `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`,
   `/sbin`, followed by anything you added in Settings → Advanced.

The controlled path is deliberately not the one your shell has. Pium opened
from the Finder and Pium opened from a terminal would otherwise resolve
differently, and a plugin that works one way and not the other is a bug nobody
can reproduce.

**There is no shell.** `executable` and `arguments` are handed to the kernel as
an argument array. This does not work:

```json
"arguments": ["cat file.txt | grep foo > out.txt"]
```

Pipes, redirections, globs, `&&`, and `$VAR` expansion are shell features, and
there is no shell to expand them. Put them in a script and point the manifest
at the script:

```json
"command": { "executable": "./report.sh", "arguments": ["{{input}}"] }
```

A relative script is run through its own shebang, so `#!/bin/sh` on the first
line is what makes it a shell script.

**`workingDirectory`** defaults to the manifest's own folder. A relative value
resolves from there; an absolute one is used as written.

## Input

A plugin takes at most one free-form argument in v1.

```json
"input": { "mode": "required", "placeholder": "Search terms" }
```

- `none` — the plugin runs on `Return` with nothing to type.
- `optional` — it can take an argument, and runs without one.
- `required` — `Return` will not run it until something is typed.

Typing a space when the plugin is the selected result enters argument mode: the
result list is replaced by the plugin's name, and everything you type after
that goes to it. `Backspace` on an empty argument goes back.

### Templates

Inside `arguments`, `{{input}}` is replaced by what the user typed.

| Template | Gives you |
|---|---|
| `{{input}}` | The text as typed. |
| `{{input\|url_encode}}` | Percent-encoded, for putting inside a URL. |
| `{{fieldKey}}` | A `string` configuration field's value. |
| `{{fieldKey\|url_encode}}` | The same, percent-encoded. |

Spaces inside the braces are allowed: `{{ input }}` and `{{input}}` are the
same thing.

**Always use `url_encode` when the value lands in a URL.** Without it a query
containing `&` or `#` silently becomes a different request.

## Configuration

Values you do not want written into the file — a server address, an API token —
are declared here and filled by the user in Settings → Plugins.

```json
"configuration": [
  {
    "key": "baseURL",
    "label": "Home Assistant URL",
    "type": "string",
    "required": true,
    "environmentVariable": "PIUM_CONFIG_BASE_URL"
  },
  {
    "key": "token",
    "label": "Access token",
    "type": "secret",
    "required": true,
    "environmentVariable": "PIUM_SECRET_TOKEN"
  }
]
```

| Field | Rules |
|---|---|
| `key` | Starts with a letter, then letters, digits, `_` and `-`. **No dots.** `input` is reserved. Unique within the plugin. |
| `label` | What the user sees in Settings. |
| `type` | `string` or `secret`. |
| `required` | A required field that is empty blocks the run and says which field. |
| `environmentVariable` | Capitals, digits, and underscores, starting with a capital. Unique within the plugin. |

Every declared field arrives in the child process as its
`environmentVariable`. A `string` field can *also* be interpolated into
`arguments` with `{{key}}`.

**A `secret` cannot be interpolated into arguments, and trying is an error that
stops the plugin from running at all.** Arguments are visible in the process
table to everything on the machine; the environment is not. Secrets live in the
macOS Keychain, never in this file, never in your Git history, and never in
Pium's usage history.

## Output

```json
"output": { "mode": "toast" }
```

- `silent` — a successful run shows nothing.
- `toast` — a successful run shows what the command printed on `stdout`, in a
  HUD.

**A failure is always shown, whatever the mode.** `silent` means silent about
success. A cancelled run shows nothing — you cancelled it, you know.

Output is captured up to 64 KB per stream and truncated with a note rather than
grown without bound. Pium does not parse JSON or any other structure in v1: if
your command produces something complicated, have it print the sentence a
person should read.

## Timeout and confirmation

```json
"timeoutSeconds": 30,
"confirmBeforeRun": "This will restart the server."
```

A timeout sends `SIGTERM` to the command and everything it started, waits two
seconds, then sends `SIGKILL`. Pium never retries a command by itself.

`confirmBeforeRun` asks every single time, inside the launcher rather than in a
dialog that steals your place.

## When a plugin does not work

Settings → Plugins lists every file in the folder, including the broken ones,
with the reason. A plugin that fails validation is never executable — it cannot
half-run.

Common reasons, in the words Pium uses:

| What you see | What it means |
|---|---|
| Unknown key `x` | A typo, or a key from a version that does not exist. |
| `"…"` has no value yet | A `required` field is empty. It names the field; fill it in Settings → Plugins. |
| A secret cannot be used in arguments | Move it to the environment; see Configuration above. |
| Executable not found | The name is not on the controlled path. Use an absolute path, or add the directory in Settings → Advanced. |
| The file is quarantined | macOS marked a downloaded script. `xattr -d com.apple.quarantine <file>` clears it, after you have read the script. |

One broken plugin never blocks the others.

## Worked examples

Three complete manifests ship in the repository under
[`Pium/Resources/ExamplePlugins`](../Pium/Resources/ExamplePlugins): a URL
search with encoded input, a silent command, and one that shows its output.

## What version 1 does not do

Deliberately, so the format stays small enough to read:

- More than one argument, or typed arguments (numbers, dates, choices).
- Localized `name` and `description`. Put translations in `keywords`.
- Custom icons. SF Symbols only.
- Several commands in one file, or a folder that is one plugin.
- Automatic retries, streaming output, or interactive commands.
