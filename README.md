# AI Usage for Omarchy

An [Omarchy](https://omarchy.org/) bar widget that shows how much of your **Claude Code** and
**Codex** subscription limits you've used, for **several accounts at once**. It is the Omarchy
port of [kletse-ai-usage-macos](https://github.com/kletse/kletse-ai-usage-macos).

If you switch between logins with `CLAUDE_CONFIG_DIR` or `CODEX_HOME` (a work account and a
personal one, say), this shows all of them side by side. It reads the logins the CLIs already have,
so there's nothing to sign in to.

## Features

- **One number per account in the bar:** Claude's session or overall weekly usage (your choice,
  defaulting to Session), or Codex's shortest-period limit, with a provider icon as tall as the
  numbers and a dot between groups of accounts.
- **Every limit in the panel**, with the time until it resets:
  - **Claude:** 5-hour session, weekly, per-model weekly (e.g. Fable), and the monthly spend cap on
    Enterprise plans.
  - **Codex:** 5-hour, weekly, and any extra per-model limits.
- **Colour-coded** in your theme's own colours: meters turn yellow at 75% and red at 90%.
- **An animated mascot:** each Claude mascot plays one of 35 little animations when its usage
  changes, and now and then for no reason. See [The mascot](#the-mascot).
- **Automatic Claude renewal:** runs Claude Code's local `/usage` command four minutes before the
  access token expires, checks that the saved token really moved on, and schedules again from its
  new expiry. Claude Code owns all credential writes. See [Safety](#safety).
- **Native to Omarchy:** an Omarchy shell plugin that follows the theme, the bar's position and
  font size, and `omarchy toggle animations`, with a stdlib-only Python backend. No other
  dependencies.

## Requirements

- Omarchy with the Quickshell-based Omarchy shell (4.x)
- `python3` (part of every Omarchy install)
- A Claude Code and/or Codex CLI login

## Install

```sh
git clone https://github.com/kletse/kletse-ai-usage-omarchy.git
cd kletse-ai-usage-omarchy
./install.sh
```

`install.sh` links the repo to `~/.config/omarchy/plugins/ward.ai-usage`, links the `ai-usage` CLI
into `~/.local/bin`, and adds the widget to the right of the bar (just before Omarchy's own Agents
icon when that is there). Move it like any widget, e.g. `omarchy bar move ward.ai-usage --section
centerEnd`, and remove it with `omarchy plugin disable ward.ai-usage`.

The shell keeps a plugin's code in memory once loaded, and it doesn't watch a linked folder, so
after a `git pull` run `omarchy restart shell` to load the new version.

## Using it

- **Left click** opens the panel; **right or middle click** refreshes.
- In the panel, **R** refreshes, **E** opens `accounts.json` in your editor, and **Esc** closes it.
  The arrow keys scroll when there are more accounts than fit.
- On a Claude account, the **SESSION / WEEK** chip chooses what the bar shows for it: the 5-hour
  session or the overall weekly allowance (not a per-model limit). All limits stay in the panel. If
  weekly usage isn't reported, Week shows a dash.
- Hovering a reset time shows the exact date; hovering the bar lists every account's number.
- `omarchy-shell ward.ai-usage toggle`, `open`, `close` and `refresh` work from keybindings and
  scripts.

The CLI shows the same thing in a terminal:

```sh
ai-usage show        # usage as text
ai-usage refresh     # fetch now (the widget does this every 5 minutes)
ai-usage status      # the status file as JSON, for scripts
```

## Configure your accounts

On first run the widget creates `~/.config/ai-usage/accounts.json` with the logins it finds in
`~/.claude` and `~/.codex`. It is the same file, in the same format, as the macOS app's, so a copy
works on both. Edit it with **E** in the panel, by hand, or with the CLI:

```sh
ai-usage add claude ~/.claude-work --group Work
ai-usage add codex ~/.codex-work --group Work
ai-usage accounts                     # numbered list
ai-usage usage-type 1 week            # what account 1 shows in the bar
ai-usage remove 2
```

Changes apply at once: the widget watches the file, and a new account is fetched straight away.

```json
[
  { "name": "Claude", "group": "Work",     "provider": "claude", "dir": "~/.claude-work" },
  { "name": "Codex",  "group": "Work",     "provider": "codex",  "dir": "~/.codex-work" },
  { "name": "Claude", "group": "Personal", "provider": "claude", "dir": "~/.claude" },
  { "name": "Codex",  "group": "Personal", "provider": "codex",  "dir": "~/.codex" }
]
```

| Field | Meaning |
| --- | --- |
| `name` | Shown in the panel. |
| `provider` | `claude` or `codex`. |
| `dir` | That login's `CLAUDE_CONFIG_DIR` or `CODEX_HOME`. Use `~/.claude` / `~/.codex` for the default login. |
| `group` | Optional. Accounts in a group are shown together under a header, with a dot between groups in the bar. |
| `usageType` | Optional, Claude only. `session` (default) or `week` for the bar and the panel headline. |
| `keychainService` | macOS only; kept, but unused on Linux, where Claude Code keeps its login in a file. |
| `short` | Optional legacy label; reserved for compatibility. |

The order of the list is the order in the bar and the panel. With shell aliases like these you
would add `~/.claude-work` and `~/.codex-work` as above:

```sh
alias cc='CLAUDE_CONFIG_DIR=~/.claude-work claude'
alias co='CODEX_HOME=~/.codex-work codex'
```

## Settings

The widget's settings live in its entry in `~/.config/omarchy/shell.json`; set them with
`omarchy bar set`:

```sh
omarchy bar set ward.ai-usage refreshIntervalSec 600
omarchy bar set ward.ai-usage colorMascot false --json
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `refreshIntervalSec` | `300` | How often usage is fetched (60–3600 seconds). |
| `colorMascot` | `true` | The Claude mascot in its orange; `false` draws it in the bar's text colour. |
| `animations` | `true` | Mascots animate when usage changes and now and then. |
| `renewClaude` | `true` | Renew Claude logins shortly before their access tokens expire. |

## The mascot

Each Claude account's icon in the bar is the Claude Code mascot, drawn as crisp pixel art at the
height of the numbers beside it. When an account's usage changes, its mascot plays a random
animation (two that change together never play the same one), and about every ten minutes one
mascot plays one just because. Click the big mascot in the panel to see one.

Play one yourself, even with animations off:

```sh
omarchy-shell ward.ai-usage animations     # the 35 names
omarchy-shell ward.ai-usage play backflip
omarchy-shell ward.ai-usage play ""        # a different random one on each mascot
```

`omarchy toggle animations` stops them along with the rest of the shell's motion.

## How it works

The widget runs `bin/ai-usage refresh`, which writes `~/.local/state/ai-usage/status.json`; every
copy of the widget (one per monitor) watches that file, and only one of them drives the refreshes.
Refreshes are serialized with a lock, and one within a minute of the last fetch reuses it unless
you ask for a refresh, so several monitors never mean several requests. The widget also refreshes
after the machine wakes from sleep, respecting API rate-limit back-off.

### Claude Code

- **Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`, the same one `/usage` uses.
- **Token:** read from `.credentials.json` in the account's directory, where Claude Code keeps it
  on Linux. Identity and plan come from `~/.claude.json` (or `$CLAUDE_CONFIG_DIR/.claude.json`).
- **Enterprise plans** report a monthly spend cap instead of session and weekly windows. The API
  doesn't say when it resets, so the widget assumes the 1st of the month (shown as `~`).
- **If the request can't be made** (an expired or rejected token), the widget shows Claude Code's
  own cached copy of the usage from `.claude.json`, marked as cached.
- **Four minutes before token expiry**, a refresh runs Claude Code's noninteractive local `/usage`
  command for that login. It then rereads the credentials and requires a different access token
  with a later expiry before confirming renewal and scheduling the next attempt. Normal refreshes
  notice renewals made by another CLI session, and waking the machine rechecks missed deadlines.
- **If renewal fails**, attempts back off from 30 seconds up to five minutes. A CLI exit code of
  zero alone is not taken as success. Existing usage and cached data remain available.
- **Final login expiry** still requires `claude auth login`; automatic renewal cannot extend it.
  Claude Code must be installed. Tested with Claude Code 2.1.330.

### Codex

- **Endpoint:** `GET https://chatgpt.com/backend-api/wham/usage`, the data behind `/status`.
- **Token:** the ChatGPT login from `$CODEX_HOME/auth.json`.
- **If the request fails**, the widget shows the newest rate-limit snapshot Codex wrote to
  `$CODEX_HOME/sessions/`, marked as cached.

## Safety

- **CLI-owned credentials.** Nothing here writes to CLI config files or credentials or calls the
  OAuth refresh endpoint. It asks Claude Code to renew its own login, then reads the result. Codex
  credentials stay read-only.
- **Bounded local command.** Renewal runs `/usage` without model prompts, tools, hooks, MCP, Chrome,
  settings files or conversation persistence, in the login's own config directory and with every
  inherited `CLAUDE_*` and `ANTHROPIC_*` variable removed. Its output is discarded and it is killed
  after 30 seconds.
- **No secrets in output.** Tokens stay in memory. The status file (mode `0600`) holds usage,
  account names and login identities, never credentials. Errors show HTTP status codes, never
  response bodies or tokens, and redirects are refused so a token can't follow one elsewhere.
- **Untrusted text stays text.** Everything the panel shows is drawn as plain text, never as markup.
- **Gentle on the APIs.** It polls every 5 minutes and backs off when asked to (`429` +
  `Retry-After`).

These are private, undocumented endpoints that the official CLIs use. They can change at any time,
which may break the widget until it's updated.

## Development

```sh
python3 -m unittest discover -s tests       # the backend: parsing, refresh, renewal, config
node --test tests/test_js.mjs               # the widget's display logic and all 35 animations
python3 tests/check_claude_renewal.py       # disposable OAuth fixture + the real installed Claude CLI
ai-usage show --sample                      # made-up accounts, for screenshots
AI_USAGE_CONFIG=/tmp/test.json AI_USAGE_STATE_DIR=/tmp/ai-usage ai-usage refresh
```

The renewal check sends all of the CLI's traffic to a local fixture server, so no real token is
used and nothing reaches Anthropic. `omarchy plugin validate .` checks the manifest.

| File | Purpose |
| --- | --- |
| `bin/ai-usage` | Accounts, Claude and Codex requests, fallbacks, back-off, renewal, the status file, the CLI |
| `Panel.qml` | The bar widget and its panel |
| `Mascot.qml`, `Mascot.js` | The pixel-art mascot and its 35 animations |
| `CodexIcon.qml` | The Codex knot as a vector |
| `Model.js` | Display helpers: thresholds, countdowns, bar segments |
| `manifest.json` | The Omarchy plugin manifest and settings |
| `install.sh` | Links the plugin and CLI and adds the widget to the bar |

## Credits

- Inspired by [CodexBar](https://github.com/steipete/CodexBar) by Peter Steinberger, whose source
  showed how to read these endpoints safely.
- The Codex icon is the OpenAI knot as shipped in CodexBar (MIT). The Claude icon is drawn from the
  block characters Claude Code prints on startup.

Not affiliated with or endorsed by Anthropic, OpenAI or Omarchy. Claude and Claude Code are
trademarks of Anthropic; Codex and OpenAI are trademarks of OpenAI.

## License

[MIT](LICENSE) © 2026 Ward Werbrouck
