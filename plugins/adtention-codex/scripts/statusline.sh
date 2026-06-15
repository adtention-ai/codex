#!/usr/bin/env bash
# ADtention for Codex: cache-only renderer for external status bars.
set -u

root="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
if [ -r "$root/scripts/cache-dir.sh" ]; then
  # shellcheck disable=SC1091
  . "$root/scripts/cache-dir.sh"
fi
cache_dir="$(adtention_default_cache_dir 2>/dev/null || printf '%s\n' "${ADTENTION_CACHE:-$HOME/.adtention}")"
balance=$(cat "$cache_dir/balance_display" 2>/dev/null || true)
ad=$(cat "$cache_dir/current_ad.txt" 2>/dev/null || true)
mkdir -p "$cache_dir" 2>/dev/null || true
: > "$cache_dir/last_render_seen" 2>/dev/null || true

[ -z "$balance" ] && balance='⊕ $0.00'

with_learn_more_hint() {
  case "$1" in
    *'-> learn-more') printf '%s' "$1" ;;
    *) printf '%s -> learn-more' "$1" ;;
  esac
}

line="$balance"
display_ad=""
if [ -n "$ad" ]; then
  display_ad="$(with_learn_more_hint "$ad")"
  line="$line  $display_ad"
fi

if [ -n "$ad" ]; then
  printf '%s · %s' "$balance" "$display_ad" > "$cache_dir/title.txt" 2>/dev/null || true
  printf '%s' "$line" > "$cache_dir/prompt_line.txt" 2>/dev/null || true
  printf '%s · %s\n%s\n' "$balance" "$display_ad" "$line" > "$cache_dir/terminal.txt" 2>/dev/null || true
else
  printf '%s' "$balance" > "$cache_dir/title.txt" 2>/dev/null || true
  printf '%s' "$balance" > "$cache_dir/prompt_line.txt" 2>/dev/null || true
  printf '%s\n%s\n' "$balance" "$balance" > "$cache_dir/terminal.txt" 2>/dev/null || true
fi

max_width="${ADTENTION_MAX_WIDTH:-${COLUMNS:-120}}"
case "$max_width" in (*[!0-9]*|'') max_width=120;; esac

if [ "${#line}" -gt "$max_width" ] && [ "$max_width" -gt 8 ]; then
  line="${line:0:$((max_width - 3))}..."
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${ADTENTION_COLOR:-1}" != "0" ]; then
  if [ -n "$ad" ]; then
    printf '\033[1;32m%s\033[0m  \033[36m%s\033[0m\n' "$balance" "$display_ad"
  else
    printf '\033[1;32m%s\033[0m\n' "$balance"
  fi
else
  printf '%s\n' "$line"
fi
