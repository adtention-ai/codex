#!/usr/bin/env bash
set -euo pipefail

start_marker="# >>> ADtention Codex >>>"
end_marker="# <<< ADtention Codex <<<"

remove_one() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/adtention-rc.XXXXXX")"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"
}

remove_one "$HOME/.zshrc"
remove_one "$HOME/.bashrc"

printf 'Removed ADtention shell integration from %s and %s\n' "$HOME/.zshrc" "$HOME/.bashrc"

