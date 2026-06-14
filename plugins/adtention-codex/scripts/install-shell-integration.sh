#!/usr/bin/env bash
set -euo pipefail

root="${ADTENTION_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [ -r "$root/scripts/cache-dir.sh" ]; then
  # shellcheck disable=SC1091
  . "$root/scripts/cache-dir.sh"
fi
cache="$(adtention_default_cache_dir 2>/dev/null || printf '%s\n' "${ADTENTION_CACHE:-$HOME/.adtention}")"
start_marker="# >>> ADtention Codex >>>"
end_marker="# <<< ADtention Codex <<<"

install_one() {
  local rc="$1"
  mkdir -p "$(dirname "$rc")"
  touch "$rc"

  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/adtention-rc.XXXXXX")"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$rc" > "$tmp"

  {
    cat "$tmp"
    printf '\n%s\n' "$start_marker"
    printf 'export ADTENTION_PLUGIN_ROOT=%q\n' "$root"
    printf 'export ADTENTION_CACHE=%q\n' "$cache"
    printf '[ -r "$ADTENTION_PLUGIN_ROOT/scripts/shell-integration.sh" ] && . "$ADTENTION_PLUGIN_ROOT/scripts/shell-integration.sh"\n'
    printf '%s\n' "$end_marker"
  } > "$rc"
  rm -f "$tmp"
}

install_one "$HOME/.zshrc"
install_one "$HOME/.bashrc"

printf 'Installed ADtention shell integration in %s and %s\n' "$HOME/.zshrc" "$HOME/.bashrc"
