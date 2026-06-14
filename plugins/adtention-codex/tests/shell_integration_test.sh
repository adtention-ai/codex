#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/adtention-shell-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test_prompt_function_marks_display() {
  export ADTENTION_CACHE="$tmp/cache"
  export ADTENTION_DISABLE_TITLE_DAEMON=1
  mkdir -p "$ADTENTION_CACHE"
  printf '⊕ $1.23 · Neon\n' > "$ADTENTION_CACHE/title.txt"
  printf '⊕ $1.23  Neon\n' > "$ADTENTION_CACHE/prompt_line.txt"

  [[ -r "$root/scripts/shell-integration.sh" ]] || fail "shell integration script is missing"

  # shellcheck disable=SC1091
  source "$root/scripts/shell-integration.sh"
  out="$(__adtention_codex_prompt)"

  [[ "$out" == *"⊕ \$1.23  Neon"* ]] || fail "prompt line was not printed"
  [[ -f "$ADTENTION_CACHE/last_render_seen" ]] || fail "render heartbeat was not written"
}

test_prompt_marks_display_when_title_daemon_is_enabled() {
  export ADTENTION_CACHE="$tmp/cache-daemon"
  export ADTENTION_DISABLE_TITLE_DAEMON=1
  export ADTENTION_CODEX_TITLE_DAEMON_STARTED=1
  mkdir -p "$ADTENTION_CACHE"
  printf '⊕ $2.00 · Supabase\n⊕ $2.00  Supabase\n' > "$ADTENTION_CACHE/terminal.txt"

  # shellcheck disable=SC1091
  source "$root/scripts/shell-integration.sh"
  __adtention_codex_prompt >/dev/null

  [[ -f "$ADTENTION_CACHE/last_render_seen" ]] || fail "prompt did not mark render while title daemon flag was set"
  unset ADTENTION_CODEX_TITLE_DAEMON_STARTED
}

test_installer_is_idempotent() {
  local fake_home="$tmp/home"
  mkdir -p "$fake_home"

  HOME="$fake_home" "$root/scripts/install-shell-integration.sh" >/dev/null
  HOME="$fake_home" "$root/scripts/install-shell-integration.sh" >/dev/null

  [[ -f "$fake_home/.zshrc" ]] || fail ".zshrc was not created"
  [[ -f "$fake_home/.bashrc" ]] || fail ".bashrc was not created"

  zsh_count="$(grep -c 'ADtention Codex' "$fake_home/.zshrc")"
  bash_count="$(grep -c 'ADtention Codex' "$fake_home/.bashrc")"
  [[ "$zsh_count" -eq 2 ]] || fail ".zshrc marker count expected 2, got $zsh_count"
  [[ "$bash_count" -eq 2 ]] || fail ".bashrc marker count expected 2, got $bash_count"
}

test_prompt_function_marks_display
test_prompt_marks_display_when_title_daemon_is_enabled
test_installer_is_idempotent

printf 'shell integration tests passed\n'
