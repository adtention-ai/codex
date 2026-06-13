#!/usr/bin/env bash
set -u

cache_dir="${ADTENTION_CACHE:-${PLUGIN_DATA:-$HOME/.codex/adtention}}"
root="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"

printf 'cache: %s\n' "$cache_dir"
printf 'api: %s\n' "${ADTENTION_API:-https://api.adtention.ai}"
printf 'client: '
for bin in \
  "$root/bin/adtention-codex" \
  "$root/client/target/release/adtention-codex" \
  "$root/client/target/debug/adtention-codex"
do
  if [ -x "$bin" ]; then printf '%s\n' "$bin"; break; fi
done
if ! [ -x "$root/bin/adtention-codex" ] && ! [ -x "$root/client/target/release/adtention-codex" ] && ! [ -x "$root/client/target/debug/adtention-codex" ]; then
  printf 'missing; shell fallback will be used\n'
fi
printf 'jq: '
if command -v jq >/dev/null 2>&1; then command -v jq; else printf 'missing\n'; fi
printf 'curl: '
if command -v curl >/dev/null 2>&1; then command -v curl; else printf 'missing\n'; fi

for file in identity.json balance_display current_ad.txt title.txt prompt_line.txt terminal.txt category.txt source.txt last_render_seen last_viewable_seen viewability.json last_skipped last_warning; do
  path="$cache_dir/$file"
  if [ -f "$path" ]; then
    printf '%s: ' "$file"
    if [ "$file" = "identity.json" ]; then
      jq -r '{publisher_id: .publisher_id} | @json' "$path" 2>/dev/null || printf 'present\n'
    else
      head -c 300 "$path" 2>/dev/null
      printf '\n'
    fi
  fi
done
