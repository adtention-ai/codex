#!/usr/bin/env bash
# ADtention for Codex: cache-only renderer for external status bars.
set -u

cache_dir="${ADTENTION_CACHE:-$HOME/.codex/adtention}"
balance=$(cat "$cache_dir/balance_display" 2>/dev/null || true)
ad=$(cat "$cache_dir/current_ad.txt" 2>/dev/null || true)
mkdir -p "$cache_dir" 2>/dev/null || true
: > "$cache_dir/last_render_seen" 2>/dev/null || true

[ -z "$balance" ] && balance='⊕ $0.00'

line="$balance"
[ -n "$ad" ] && line="$line  $ad"

if [ -n "$ad" ]; then
  printf '%s · %s' "$balance" "$ad" > "$cache_dir/title.txt" 2>/dev/null || true
  printf '%s' "$line" > "$cache_dir/prompt_line.txt" 2>/dev/null || true
  printf '%s · %s\n%s\n' "$balance" "$ad" "$line" > "$cache_dir/terminal.txt" 2>/dev/null || true
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
    printf '\033[1;32m%s\033[0m  \033[36m%s\033[0m\n' "$balance" "$ad"
  else
    printf '\033[1;32m%s\033[0m\n' "$balance"
  fi
else
  printf '%s\n' "$line"
fi
