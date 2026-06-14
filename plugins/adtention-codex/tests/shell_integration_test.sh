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
  export ADTENTION_DISPLAY=1
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
  unset ADTENTION_DISPLAY
}

test_prompt_is_quiet_by_default() {
  export ADTENTION_CACHE="$tmp/cache-quiet"
  export ADTENTION_DISABLE_TITLE_DAEMON=1
  unset ADTENTION_DISPLAY ADTENTION_CODEX_ACTIVE ADTENTION_CODEX_DISPLAY CODEX_SHELL __CFBundleIdentifier
  mkdir -p "$ADTENTION_CACHE"
  printf '⊕ $9.99 · Quiet\n⊕ $9.99  Quiet\n' > "$ADTENTION_CACHE/terminal.txt"

  # shellcheck disable=SC1091
  source "$root/scripts/shell-integration.sh"
  out="$(__adtention_codex_prompt)"

  [[ -z "$out" ]] || fail "prompt printed even though Codex display was inactive"
  [[ ! -f "$ADTENTION_CACHE/last_render_seen" ]] || fail "inactive prompt marked a render heartbeat"
}

test_prompt_displays_inside_codex_app_terminal() {
  export ADTENTION_CACHE="$tmp/cache-app-terminal"
  export ADTENTION_DISABLE_TITLE_DAEMON=1
  export CODEX_SHELL=1
  unset ADTENTION_DISPLAY ADTENTION_CODEX_ACTIVE ADTENTION_CODEX_DISPLAY __CFBundleIdentifier
  mkdir -p "$ADTENTION_CACHE"
  printf '⊕ $5.00 · App\n⊕ $5.00  App\n' > "$ADTENTION_CACHE/terminal.txt"

  # shellcheck disable=SC1091
  source "$root/scripts/shell-integration.sh"
  out="$(__adtention_codex_prompt)"

  [[ "$out" == *"⊕ \$5.00  App"* ]] || fail "Codex app terminal did not print prompt line"
  [[ -f "$ADTENTION_CACHE/last_render_seen" ]] || fail "Codex app terminal did not mark render heartbeat"
  unset CODEX_SHELL
}

test_prompt_marks_display_when_codex_is_active() {
  export ADTENTION_CACHE="$tmp/cache-daemon"
  export ADTENTION_DISABLE_TITLE_DAEMON=1
  export ADTENTION_CODEX_ACTIVE=1
  mkdir -p "$ADTENTION_CACHE"
  printf '⊕ $2.00 · Supabase\n⊕ $2.00  Supabase\n' > "$ADTENTION_CACHE/terminal.txt"

  # shellcheck disable=SC1091
  source "$root/scripts/shell-integration.sh"
  __adtention_codex_prompt >/dev/null

  [[ -f "$ADTENTION_CACHE/last_render_seen" ]] || fail "prompt did not mark render while Codex display was active"
  unset ADTENTION_CODEX_ACTIVE
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

test_open_function_invokes_client() {
  local plugin_root="$tmp/plugin"
  local log="$tmp/open.log"
  mkdir -p "$plugin_root/bin"
  cat > "$plugin_root/bin/adtention-codex" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$log"
SH
  chmod +x "$plugin_root/bin/adtention-codex"

  export ADTENTION_PLUGIN_ROOT="$plugin_root"
  export ADTENTION_DISABLE_TITLE_DAEMON=1
  # shellcheck disable=SC1091
  source "$root/scripts/shell-integration.sh"
  adtention-open "https://example.com/sponsor"

  grep -q 'open https://example.com/sponsor' "$log" || fail "adtention-open did not invoke client open command"
}

test_codex_wrapper_scopes_display() {
  local fake_path="$tmp/fake-path"
  local log="$tmp/codex-wrapper.log"
  mkdir -p "$fake_path"
  cat > "$fake_path/codex" <<SH
#!/usr/bin/env bash
printf 'display=%s active=%s args=%s\\n' "\${ADTENTION_DISPLAY:-}" "\${ADTENTION_CODEX_ACTIVE:-}" "\$*" >> "$log"
exit 7
SH
  chmod +x "$fake_path/codex"

  unset -f codex 2>/dev/null || true
  unset ADTENTION_REAL_CODEX_BIN ADTENTION_DISPLAY ADTENTION_CODEX_ACTIVE ADTENTION_CODEX_DISPLAY
  export ADTENTION_DISABLE_TITLE_DAEMON=1
  PATH="$fake_path:$PATH"
  # shellcheck disable=SC1091
  source "$root/scripts/shell-integration.sh"

  set +e
  codex alpha beta
  status=$?
  set -e

  [[ "$status" -eq 7 ]] || fail "codex wrapper did not return the real codex status"
  grep -q 'display=1 active=1 args=alpha beta' "$log" || fail "codex wrapper did not activate display for real codex"
  [[ -z "${ADTENTION_DISPLAY:-}" ]] || fail "codex wrapper did not restore ADTENTION_DISPLAY"
  [[ -z "${ADTENTION_CODEX_ACTIVE:-}" ]] || fail "codex wrapper did not restore ADTENTION_CODEX_ACTIVE"
}

test_prompt_function_marks_display
test_prompt_is_quiet_by_default
test_prompt_displays_inside_codex_app_terminal
test_prompt_marks_display_when_codex_is_active
test_installer_is_idempotent
test_open_function_invokes_client
test_codex_wrapper_scopes_display

printf 'shell integration tests passed\n'
