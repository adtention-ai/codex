#!/usr/bin/env bash
# ADtention for Codex: background refresh. This is the only path that calls the API.
set -uo pipefail

root="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
if [ -r "$root/scripts/cache-dir.sh" ]; then
  # shellcheck disable=SC1091
  . "$root/scripts/cache-dir.sh"
fi
cache_dir="$(adtention_default_cache_dir 2>/dev/null || printf '%s\n' "${ADTENTION_CACHE:-$HOME/.adtention}")"
api="${ADTENTION_API:-https://api.adtention.ai}"
mkdir -p "$cache_dir" 2>/dev/null || exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

mtime() {
  local out
  out=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || true)
  case "$out" in (*[!0-9]*|'') echo 0;; (*) echo "$out";; esac
}
sanitize_line() { LC_ALL=C tr -d '\000-\037\177' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'; }
sanitize_ref() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cd 'a-z0-9' | cut -c 1-32; }
with_learn_more_hint() {
  case "$1" in
    *'-> learn-more') printf '%s' "$1" ;;
    *) printf '%s -> learn-more' "$1" ;;
  esac
}

read_ref_code() {
  local ref=""
  if [ -n "${ADTENTION_REF:-}" ]; then
    sanitize_ref "$ADTENTION_REF"
    return 0
  elif [ -f "$cache_dir/ref" ]; then
    ref=$(sanitize_ref "$(cat "$cache_dir/ref" 2>/dev/null || true)")
  fi
  printf '%s' "$ref"
}

register_call() {
  local ref="${1:-}"
  if [ -n "$ref" ]; then
    curl -s -m 5 -X POST "$api/v1/register" -H 'content-type: application/json' \
      -d "$(jq -nc --arg ref "$ref" '{ref:$ref}')" 2>/dev/null || true
  else
    curl -s -m 5 -X POST "$api/v1/register" 2>/dev/null || true
  fi
}

lock="$cache_dir/refresh.lock"
[ -d "$lock" ] && [ $(( $(date +%s) - $(mtime "$lock") )) -ge 60 ] && rmdir "$lock" 2>/dev/null || true
if ! mkdir "$lock" 2>/dev/null; then exit 0; fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

display_ttl="${ADTENTION_DISPLAY_TTL:-30}"
case "$display_ttl" in (*[!0-9]*|'') display_ttl=30;; esac
last_render="$cache_dir/last_render_seen"
nowsec=$(date +%s)
if [ ! -f "$last_render" ] || [ $(( nowsec - $(mtime "$last_render") )) -gt "$display_ttl" ]; then
  printf '%s' "no_render" > "$cache_dir/last_skipped" 2>/dev/null || true
  exit 0
fi

cwd="${1:-$PWD}"
transcript="${2:-}"
hook_input=$(cat 2>/dev/null || true)

classify_folder() {
  local d="$1"
  if [ -e "$d/foundry.toml" ] || compgen -G "$d/*.sol" >/dev/null || compgen -G "$d/hardhat.config.*" >/dev/null; then echo web3; return; fi
  if [ -e "$d/Dockerfile" ] || compgen -G "$d/*.tf" >/dev/null; then echo devops; return; fi
  if [ -e "$d/package.json" ]; then echo web; return; fi
  if [ -e "$d/requirements.txt" ] || compgen -G "$d/*.py" >/dev/null; then echo data; return; fi
  if [ -e "$d/Cargo.toml" ] || [ -e "$d/go.mod" ]; then echo systems; return; fi
  echo general
}

classify_topic() {
  local tp="$1"
  local prompt_text=""
  if [ -n "$hook_input" ]; then
    prompt_text=$(printf '%s' "$hook_input" | jq -r '
      [
        .prompt?,
        .user_prompt?,
        .userPrompt?,
        .message?,
        .input?,
        .text?
      ] | map(select(type == "string" and length > 0)) | .[0] // empty
    ' 2>/dev/null || true)
  fi

  local text=""
  [ -n "$prompt_text" ] && text="$prompt_text"
  if [ -f "$tp" ]; then
    text="$text
$(tail -n 400 "$tp" 2>/dev/null || true)"
  fi
  text=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
  [ -z "$text" ] && return 1

  hits() { printf '%s' "$text" | grep -oE "$1" 2>/dev/null | grep -c . ; }
  local s_web3 s_web s_devops s_data s_systems
  s_web3=$(hits 'solidity|ethereum|web3|smart contract|defi|onchain|blockchain|wallet|stablecoin|crypto|erc-?20')
  s_web=$(hits 'react|tailwind|next\.js|frontend|vite|jsx|tsx|css|component')
  s_devops=$(hits 'docker|kubernetes|terraform|kubectl|nginx|ci/cd|pipeline|deployment')
  s_data=$(hits 'dataset|training data|pandas|embedding|inference|fine-tune|gpu|machine learning')
  s_systems=$(hits 'goroutine|borrow checker|mutex|concurrency|memory safety|rustc')

  local best n c
  best=$(printf '%s web3\n%s web\n%s devops\n%s data\n%s systems\n' \
    "$s_web3" "$s_web" "$s_devops" "$s_data" "$s_systems" | sort -rn | head -1)
  n="${best%% *}"
  c="${best##* }"
  if [ "${n:-0}" -ge 3 ]; then echo "$c"; return 0; fi
  return 1
}

category=""
src="folder"
if category="$(classify_topic "$transcript")" && [ -n "$category" ]; then
  src="topic"
else
  category="$(classify_folder "$cwd")"
fi

id_file="$cache_dir/identity.json"
publisher_id=""
[ -f "$id_file" ] && publisher_id=$(jq -r '.publisher_id // empty' "$id_file" 2>/dev/null || true)
if [ -z "$publisher_id" ]; then
  ref=$(read_ref_code)
  reg=$(register_call "$ref")
  if [ -n "$reg" ]; then
    printf '%s' "$reg" > "$id_file"
    chmod 600 "$id_file" 2>/dev/null || true
    publisher_id=$(printf '%s' "$reg" | jq -r '.publisher_id // empty' 2>/dev/null || true)
    [ -n "$publisher_id" ] && rm -f "$cache_dir/ref" 2>/dev/null || true
  fi
fi
[ -z "$publisher_id" ] && exit 0

min_dwell=15
last_file="$cache_dir/last_serve"
last=$(cat "$last_file" 2>/dev/null || echo 0)
if [ $(( nowsec - last )) -lt "$min_dwell" ]; then exit 0; fi
printf '%s' "$nowsec" > "$last_file"

serve_call() {
  curl -s -m 5 -X POST "$api/v1/serve" -H 'content-type: application/json' \
    -d "{\"publisher_id\":\"$publisher_id\",\"category\":\"$category\",\"nonce\":\"$1\"}" 2>/dev/null || true
}

nonce="$(date +%s)-codex-${RANDOM}"
resp=$(serve_call "$nonce")

if printf '%s' "$resp" | grep -q 'unknown_publisher'; then
  reg=$(register_call "")
  if [ -n "$reg" ]; then
    printf '%s' "$reg" > "$id_file"
    chmod 600 "$id_file" 2>/dev/null || true
    publisher_id=$(printf '%s' "$reg" | jq -r '.publisher_id // empty' 2>/dev/null || true)
    resp=$(serve_call "${nonce}-r")
  fi
fi
[ -z "$resp" ] && exit 0

adtext=$(printf '%s' "$resp" | jq -r '.text // empty' 2>/dev/null || true)
adtext=$(printf '%s' "$adtext" | sanitize_line)
balance=$(printf '%s' "$resp" | jq -r '.balance_usd // empty' 2>/dev/null || true)
click=$(printf '%s' "$resp" | jq -r '.click_url // empty' 2>/dev/null || true)
if [ -z "$click" ]; then
  imp_id=$(printf '%s' "$resp" | jq -r '.impression_id // empty' 2>/dev/null || true)
  [ -n "$imp_id" ] && click="/v1/click/$imp_id"
fi

if [ -n "$balance" ]; then
  printf '%s' "$balance" > "$cache_dir/balance"
  awk -v b="$balance" 'BEGIN{printf "⊕ $%.2f", b}' > "$cache_dir/balance_display"
fi

if [ -z "$adtext" ]; then
  : > "$cache_dir/current_ad.txt"
  : > "$cache_dir/current_click.txt"
  exit 0
fi

printf '%s' "$adtext" > "$cache_dir/current_ad.txt"
printf '%s' "$click" > "$cache_dir/current_click.txt"
printf '%s' "$category" > "$cache_dir/category.txt"
printf '%s' "$src" > "$cache_dir/source.txt"
balance_display=$(cat "$cache_dir/balance_display" 2>/dev/null || printf '⊕ $0.00')
display_ad="$(with_learn_more_hint "$adtext")"
printf '%s · %s' "$balance_display" "$display_ad" > "$cache_dir/title.txt"
printf '%s  %s' "$balance_display" "$display_ad" > "$cache_dir/prompt_line.txt"
printf '%s · %s\n%s  %s\n' "$balance_display" "$display_ad" "$balance_display" "$display_ad" > "$cache_dir/terminal.txt"
printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$src" "$category" "$adtext" >> "$cache_dir/impressions.log"
