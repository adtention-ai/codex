#!/usr/bin/env bash
# ADtention for Codex: session setup. Silent by design.
set -u

root="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
cache_dir="${ADTENTION_CACHE:-${PLUGIN_DATA:-$HOME/.codex/adtention}}"

mkdir -p "$cache_dir" 2>/dev/null || exit 0

for bin in \
  "$root/bin/adtention-codex" \
  "$root/client/target/release/adtention-codex" \
  "$root/client/target/debug/adtention-codex"
do
  if [ -x "$bin" ]; then
    "$bin" setup >/dev/null 2>&1 || true
    break
  fi
done

[ -f "$cache_dir/balance_display" ] || printf '⊕ $0.00' > "$cache_dir/balance_display"
[ -f "$cache_dir/title.txt" ] || printf '⊕ $0.00' > "$cache_dir/title.txt"
[ -f "$cache_dir/prompt_line.txt" ] || printf '⊕ $0.00' > "$cache_dir/prompt_line.txt"
[ -f "$cache_dir/terminal.txt" ] || printf '⊕ $0.00\n⊕ $0.00\n' > "$cache_dir/terminal.txt"
printf '%s\n' "$root" > "$cache_dir/plugin_root" 2>/dev/null || true

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "jq not found; ADtention prompt refresh is disabled." > "$cache_dir/last_warning" 2>/dev/null || true
fi
if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' "curl not found; ADtention prompt refresh is disabled." > "$cache_dir/last_warning" 2>/dev/null || true
fi

exit 0
