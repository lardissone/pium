# Troubleshooting

Messages below are quoted as Pium shows them, so you can search this file for
what is on your screen.

## The shortcut does nothing

Another application owns `⌥ Space` — Spotlight and several launchers claim it.
Pium reports the conflict but stays usable from the menubar: use its menu to
open the launcher, then Settings → General to record a different combination.

Pium never needs Accessibility permission, and it does not appear in that list.
If something is asking you for it on Pium's behalf, it is not Pium.

## A plugin does not appear in the results

In order of likelihood:

1. **The file is not named right.** It must end in `.pium.json` and live in
   `~/.config/pium/plugins/`. Anything else in that folder is left alone on
   purpose — a README, a script, a `.git` directory.
2. **The plugin is invalid.** Settings → Plugins lists every file including the
   broken ones, with the reason. An invalid plugin is never searchable and
   never executable.
3. **It is switched off.** Settings → Plugins, the toggle. Disabled means
   absent from search, and Settings is the way back.
4. **You are in argument mode.** If a plugin's name is showing as a pill, the
   result list belongs to that plugin. `Backspace` on an empty argument leaves.

Plugin changes are picked up without a restart. "Reload Plugins" in the menubar
exists for when you want to be certain.

## What Settings says about a broken plugin

| Message | Fix |
|---|---|
| `This file is not valid JSON: …` | A trailing comma or a missing quote. The message says where. |
| `Unknown key "x" in …` | A typo, or a key that does not exist in version 1. Keys are case-sensitive. |
| `Missing required key "x".` | `schemaVersion`, `id`, `name`, and `command` are all required. |
| `"x" must be …` | Right key, wrong type — a string where a number belongs, usually. |
| `"x" is not a valid id.` | Lowercase letters, digits, dots, hyphens; start and end alphanumeric. |
| `Another plugin already uses the id "x".` | Two files claim one id. Ids are global; prefix yours. |
| `Another plugin already uses the alias "x".` | Same, for a trigger. Neither plugin gets it until you resolve it. |
| `"x" is not a valid configuration key.` | Letters, digits, `_`, `-`, starting with a letter. **No dots.** |
| `"input" is reserved…` | `input` is the plugin's own argument in a template. Rename the field. |
| `Configuration key "x" is declared more than once.` | Two fields share a key, so they share one storage slot. |
| `Environment variable "X" is declared by more than one field.` | Two fields would write the same variable. |
| `Secret "x" cannot be used in arguments.` | Arguments are visible to every process on the machine. Read it from its environment variable instead. |
| `Invalid argument template: …` | Usually an unclosed `{{`, or a filter that does not exist. `url_encode` is the only one. |
| `timeoutSeconds must be between 1 and 3600` | Or leave it out for no timeout. |
| `Schema version N is not supported.` | The file was written for a newer Pium. Update, or set `schemaVersion` to 1. |

## A plugin will not run

| Message | What happened |
|---|---|
| `Could not find "x". Looked in: …` | A bare executable name is looked up along Pium's own `PATH`, not your shell's. Use an absolute path, or add the directory in Settings → Advanced. |
| `There is no file at /…` | The path is wrong, or the file moved. |
| `x is not executable. Give it permission with chmod +x` | Exactly that. |
| `macOS quarantined x because it was downloaded.` | Read the script first, then `xattr -d com.apple.quarantine <file>`. |
| `"x" has no value yet. Fill it in Settings` | A required configuration field is empty. |
| `The Keychain would not give up the secret for "x"` | macOS refused the read — usually a locked Keychain, or a prompt you dismissed. Unlock and try again. |
| `x is still running` | One command at a time. Cancel from the menubar or the launcher footer. |
| `The command could not be started (error N)` | The kernel refused the spawn. `N` is an `errno`; 13 is permission, 8 is a bad executable format. |

## The command runs but nothing happens

Check `output.mode`. `silent` shows nothing on success, deliberately. Set it to
`toast` to see what the command printed.

A failure is always shown, whatever the mode. So "nothing at all" means the
command succeeded and said nothing.

## The command works in Terminal but not in Pium

Nearly always one of two things:

**There is no shell.** Pipes, `>`, `&&`, `*`, and `$VAR` are shell features, and
Pium does not use one. Put them in a script and point the plugin at the script.

**The environment is smaller.** A child gets `PATH`, `HOME`, `USER`, `LANG`,
`TMPDIR`, and whatever the manifest declares — not your shell's exports, not
your `.zshrc`. If your command needs a variable, declare it as a configuration
field.

## File results are missing

Files come from Spotlight, and Pium creates no index of its own.

- **Nothing at all:** file search may be off, in Settings → Search.
- **Nothing from Documents, Desktop, or Downloads:** macOS guards those three
  separately. Settings → Search shows each one and can ask for access. If a
  folder says it was refused, macOS will not ask again — the button there opens
  the right pane of System Settings.
- **Nothing from an external disk:** scope defaults to your home folder. Widen
  it in Settings → Search.
- **Nothing for one or two characters:** file search starts at two characters
  and waits briefly, on purpose. Applications and plugins search from the first.

## Where things live

| What | Where |
|---|---|
| Plugins | `~/.config/pium/plugins/` |
| Usage history | `~/Library/Application Support/Pium/frecency.json` |
| Debug logs | `~/Library/Application Support/Pium/DebugLogs/` |
| Settings | `defaults read com.lardissone.pium` |
| Secrets | macOS Keychain, one item per plugin field |

Deleting the usage history is a button in Settings → Search. Deleting the logs
is a button in Settings → Advanced.

## Sending a bug report

Settings → Advanced → Debug logging records what you type, the arguments you
pass, the commands Pium runs, and what they print. It stops on its own after 24
hours.

Turn it on, reproduce the problem, then Export Logs.

**Read the file before you send it.** Declared secrets are removed, including
from what a command printed. A secret you typed by hand into a plugin's
argument is not — Pium cannot tell it apart from a search term.
