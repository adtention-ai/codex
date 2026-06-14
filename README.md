# ADtention for Codex

**Sponsor text in the Codex terminal, with viewability-gated billing.**

ADtention for Claude Code gets a true status line because Claude exposes one.
Codex does not currently expose a custom statusline slot, so this client uses
the next best supported surface: the Codex app or CLI terminal.

It shows:

```text
⊕ $0.42  Alchemy: APIs for every chain -> alchemy.com
```

The terminal title/tab stays updated while you work, and the readable sponsor
line appears above the prompt. No popups. No forced tmux. No special terminal.

---

## "Wait. An ad plugin reading my code?"

Good instinct. The client is built so your code does not need to leave your
machine.

When you submit a prompt, a Codex hook classifies your work locally into one of
six broad buckets:

`web3` · `web` · `devops` · `data` · `systems` · `general`

The server receives that bucket, an anonymous install ID, and a nonce. It does
not receive your source code.

| Leaves your machine | Never leaves your machine |
|---|---|
| One bucket word, such as `web` | Your code or file contents |
| Anonymous publisher/install ID | Your prompts or Codex replies |
| Impression nonce | File names, paths, or repo names |
| Viewability metadata | Anything identifying your project |

The visible terminal path makes no network calls. It only reads cache files.
The network path runs in the background from Codex hooks.

---

## Install

macOS/Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/adtention-ai/codex/main/install.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/adtention-ai/codex/main/install.ps1 | iex
```

Local development:

```sh
./install.sh
```

The installer does all of this:

- copies the client to a stable location under `~/.codex/adtention-codex`
- builds the Rust binary if a valid binary is not already present
- installs the Codex plugin from the local marketplace
- installs shell terminal integration
- installs and starts the OS viewability helper

Codex may still ask you to review and trust plugin hooks with `/hooks`. That is
a Codex safety step, not an ADtention prompt.

---

## What You Get

- **Persistent terminal title/tab text** while commands run.
- **Readable sponsor line above the prompt** when the terminal is ready.
- **No terminal lock-in**: works through shell integration, not tmux/zellij.
- **Fast prompt path**: shell builtins read one tiny cache file.
- **Viewability-gated billing**: render-only traffic is non-billable.
- **One install command** for plugin, shell integration, and helper.

---

## How Money Works

ADtention only allows `/v1/serve` when all of these are true:

1. A real Codex prompt hook runs.
2. The terminal renderer recently wrote `last_render_seen`.
3. The OS helper recently wrote `last_viewable_seen`.
4. The minimum dwell window has elapsed.

An idle terminal earns nothing. A background render-only terminal earns nothing.
Unsupported/unverified platforms can show cached preview text but do not create
billable serves.

---

## How It Works Under the Hood

Three parts are deliberately separate:

- **Terminal renderer**: updates the title/tab and prompt line from local cache.
  It writes `last_render_seen` and never calls the network.
- **OS viewability helper**: checks whether Codex is likely frontmost and
  visible. Only verified checks write `last_viewable_seen`; failed checks clear
  it immediately.
- **Codex prompt hook**: classifies the prompt locally, checks both heartbeats,
  calls `/v1/serve`, and updates the cache.

Current helper behavior:

- macOS: checks the frontmost app and visible window rectangle through the
  system scripting interface. You may need to allow Accessibility/Automation
  permission in System Settings.
- Windows: checks foreground process/window state and window rectangle through
  PowerShell/Win32 APIs.
- Linux X11: checks the active window and screen intersection through `xdotool`
  when available.
- Linux Wayland: treated as unavailable by default because global window
  inspection is intentionally restricted.

This is fraud resistance, not impossible-to-cheat proof. Server-side fraud
scoring, payout review, and caps still matter.

---

## Runtime State

All components use the same cache by default:

```text
~/.codex/adtention/
```

Override it with:

```sh
export ADTENTION_CACHE=/some/other/cache
```

The installed client lives at:

```text
~/.codex/adtention-codex/
```

---

## Developer Commands

Build the Rust client:

```sh
plugins/adtention-codex/scripts/build-client.sh
```

Run diagnostics:

```sh
plugins/adtention-codex/scripts/diagnose.sh
```

Run tests:

```sh
cd plugins/adtention-codex/client
cargo test

cd ../../..
bash plugins/adtention-codex/tests/shell_integration_test.sh
bash plugins/adtention-codex/tests/install_test.sh
```

---

## Uninstall

Shell integration can be removed with:

```sh
plugins/adtention-codex/scripts/uninstall-shell-integration.sh
```

Full uninstall support for plugin + helper services is planned next. For now,
remove the Codex plugin from the Codex plugin browser or CLI and remove the
viewability service from your OS startup mechanism.
