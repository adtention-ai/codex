# ADtention for Codex

**Sponsor text in the Codex terminal, served only after real Codex prompts.**

ADtention for Claude Code gets a true status line because Claude exposes one.
Codex does not currently expose a custom statusline slot, so this client uses
the next best supported surface: the Codex app or CLI terminal.

It shows:

```text
⊕ $0.42  Alchemy: APIs for every chain -> alchemy.com
```

The terminal title/tab stays updated while you work, and the readable sponsor
line appears above the prompt. No popups. No forced tmux. No special terminal.

Open the current sponsor with:

```sh
adtention-open
```

Or open an explicit sponsor URL:

```sh
adtention-open https://example.com/sponsor
```

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

Referral install:

```sh
curl -fsSL https://raw.githubusercontent.com/adtention-ai/codex/main/install.sh | bash -s -- --ref YOURCODE
```

Windows referral install:

```powershell
$env:ADTENTION_REF = "YOURCODE"; irm https://raw.githubusercontent.com/adtention-ai/codex/main/install.ps1 | iex
```

The installer does all of this:

- copies the client to a stable location under `~/.codex/adtention-codex`
- uses the released prebuilt Rust binary for your OS and CPU
- builds with Rust/Cargo only if the released binary is unavailable
- installs the Codex plugin from the local marketplace
- installs shell terminal integration

The referral code is one-shot. It is saved locally and sent only with the first
anonymous `/v1/register` call, then removed. If a user already has an
`identity.json`, installing with a new referral code does not reattribute that
existing install.

Codex may still ask you to review and trust plugin hooks with `/hooks`. That is
a Codex safety step, not an ADtention prompt.

---

## What You Get

- **Persistent terminal title/tab text** while commands run.
- **Readable sponsor line above the prompt** when the terminal is ready.
- **Open command**: `adtention-open` opens the cached sponsor URL.
- **No terminal lock-in**: works through shell integration, not tmux/zellij.
- **Fast prompt path**: shell builtins read one tiny cache file.
- **Prompt-gated serving**: sponsor text changes only after real Codex input.
- **One install command** for plugin and shell integration.

---

## How It Works Under the Hood

Two parts are deliberately separate:

- **Terminal renderer**: updates the title/tab and prompt line from local cache.
  It writes `last_render_seen` and never calls the network.
- **Codex prompt hook**: classifies the prompt locally, checks the render heartbeat,
  calls `/v1/serve`, and updates the cache.

There is no macOS Accessibility permission, Windows scheduled task, Linux
systemd helper, tmux requirement, or foreground-window watcher.

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

Build release artifacts:

```sh
./build.sh
cd plugins/adtention-codex/bin && shasum -a 256 -c SHA256SUMS
```

Tagged releases attach the same platform binaries and `SHA256SUMS`. The release
workflow only runs for `v*` tags, and the tag must match the plugin version.

Run diagnostics:

```sh
plugins/adtention-codex/scripts/diagnose.sh
```

Open a sponsor URL directly:

```sh
plugins/adtention-codex/bin/adtention-codex open https://example.com/sponsor
```

Run tests:

```sh
cd plugins/adtention-codex/client
cargo test

cd ../../..
bash plugins/adtention-codex/tests/shell_integration_test.sh
bash plugins/adtention-codex/tests/install_test.sh
bash plugins/adtention-codex/tests/refresh_shell_test.sh
```

---

## Uninstall

Shell integration can be removed with:

```sh
plugins/adtention-codex/scripts/uninstall-shell-integration.sh
```

Full uninstall support for plugin removal is planned next. For now, remove the
Codex plugin from the Codex plugin browser or CLI.
