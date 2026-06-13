# ADtention for Codex

Codex client for the ADtention prompt-based sponsor system.

The Claude version uses two Claude-specific features: a prompt hook for impressions and a custom shell-command status line for display. Codex currently matches the first part but not the second:

- Codex has `SessionStart` and `UserPromptSubmit` hooks, so ADtention can refresh sponsor state on real user prompts.
- Codex does not currently expose a custom footer/statusline command slot. Its footer accepts built-in item IDs only, such as model, context, branch, and token items.

So this plugin implements the native Codex hook side and ships a terminal integration that shows ADtention in the Codex app terminal without forcing tmux, zellij, or a special terminal.

The display model is:

- persistent surface: terminal title/tab text
- readable surface: one sponsor line above the shell prompt
- render signal: terminal integration writes `last_render_seen`
- viewability signal: an OS-specific helper writes `last_viewable_seen` plus `viewability.json`
- billing gate: `/v1/serve` is only called after both signals are fresh

That last point matters. Terminal rendering alone is not treated as billable. Fetching and billing are intentionally blocked until a future macOS/Windows/Linux helper verifies likely window viewability.

## Layout

```text
.agents/plugins/marketplace.json
plugins/adtention-codex/
  .codex-plugin/plugin.json
  hooks/hooks.json
  client/
  bin/adtention-codex
  scripts/setup.sh
  scripts/on-prompt.sh
  scripts/refresh.sh
  scripts/statusline.sh
  scripts/shell-integration.sh
  scripts/install-shell-integration.sh
  scripts/uninstall-shell-integration.sh
  scripts/build-client.sh
  scripts/diagnose.sh
```

## Build the Fast Client

The prompt path is shell builtins only. The background client is Rust.

```sh
/Users/JulianPechler/CODE/adtention-codex/plugins/adtention-codex/scripts/build-client.sh
```

This builds:

```text
/Users/JulianPechler/CODE/adtention-codex/plugins/adtention-codex/bin/adtention-codex
```

## Install Locally

From this repo:

```sh
/Applications/Codex.app/Contents/Resources/codex plugin marketplace add /Users/JulianPechler/CODE/adtention-codex
/Applications/Codex.app/Contents/Resources/codex plugin add adtention-codex@adtention-local
```

Then start a new Codex CLI or Codex app thread and review/trust the hook with `/hooks` if prompted.

The global `codex` npm shim on this machine currently points to a missing binary, so the commands above use the Codex app-bundled CLI.

## Display in the Codex App Terminal

Install the shell integration:

```sh
/Users/JulianPechler/CODE/adtention-codex/plugins/adtention-codex/scripts/install-shell-integration.sh
```

Open a new terminal tab after installing.

What it does:

- updates the terminal title/tab from `terminal.txt`
- prints the readable sponsor line above the prompt
- starts the Rust title daemon when available, so the title stays fresh while commands run
- writes `last_render_seen`

Rendering alone does **not** allow `/v1/serve`. A separate viewability helper must also write `last_viewable_seen`. Until such a helper is installed, the terminal integration can show cached/preview text but will not generate billable serves.

Manual helper command for tests or a future OS helper:

```sh
/Users/JulianPechler/CODE/adtention-codex/plugins/adtention-codex/bin/adtention-codex mark-viewable verified-macos-helper
```

Uninstall:

```sh
/Users/JulianPechler/CODE/adtention-codex/plugins/adtention-codex/scripts/uninstall-shell-integration.sh
```

You can also render the cached line manually:

```sh
/Users/JulianPechler/CODE/adtention-codex/plugins/adtention-codex/scripts/statusline.sh
```

Renderers never call the network. They only read cache files written by the background refresh path.

## Privacy Model

The hook reads local signals only:

- project folder markers, such as `package.json`, `Dockerfile`, `go.mod`, or `foundry.toml`
- recent local transcript text, when Codex provides a transcript path
- current hook JSON, only in memory, to classify the prompt text if Codex includes it

Only these values are sent to ADtention:

- anonymous publisher ID
- one broad category: `web3`, `web`, `devops`, `data`, `systems`, or `general`
- nonce for impression deduplication

Code, file contents, file names, repo names, prompts, and replies are not sent.

## Runtime State

By default the plugin writes state to Codex plugin data when `PLUGIN_DATA` is provided, otherwise:

```text
~/.codex/adtention/
```

Override with:

```sh
export ADTENTION_CACHE=/some/other/cache
export ADTENTION_API=https://api.adtention.ai
```

Useful diagnostics:

```sh
/Users/JulianPechler/CODE/adtention-codex/plugins/adtention-codex/scripts/diagnose.sh
```

## Tests

```sh
cd /Users/JulianPechler/CODE/adtention-codex/plugins/adtention-codex/client
cargo test

cd /Users/JulianPechler/CODE/adtention-codex
bash plugins/adtention-codex/tests/shell_integration_test.sh
```

The Rust tests cover:

- terminal-control stripping
- title/prompt rendering
- separate render and viewability heartbeat freshness
- serve gating that blocks render-only traffic
- register/serve cache writes with a mocked backend

The shell tests cover:

- prompt function heartbeat behavior
- idempotent installer writes for `.zshrc` and `.bashrc`

## Current Codex App Support

The Codex app uses the same Codex configuration, plugin, and hook system as the CLI. That means the impression refresh path should work in app threads after the plugin is installed and trusted.

The app UI also does not expose a supported custom persistent ad/statusline slot today. Until it does, the app terminal title/tab is the persistent surface and the prompt line is the readable surface.
