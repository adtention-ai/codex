#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/adtention-setup-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

write_fake_client() {
  local plugin_root="$1"
  local log="$2"
  mkdir -p "$plugin_root/bin"
  cat > "$plugin_root/bin/adtention-codex" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$log"
if [ "\${1:-}" = "setup" ]; then
  mkdir -p "\${ADTENTION_CACHE:-$tmp/cache}"
fi
SH
  chmod +x "$plugin_root/bin/adtention-codex"
}

wait_for_log() {
  local log="$1"
  local pattern="$2"
  local i
  for i in $(seq 1 50); do
    grep -q "$pattern" "$log" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

test_setup_starts_quiet_update_check() {
  local plugin_root="$tmp/plugin"
  local cache="$tmp/cache"
  local log="$tmp/setup.log"
  write_fake_client "$plugin_root" "$log"

  PLUGIN_ROOT="$plugin_root" \
  ADTENTION_CACHE="$cache" \
  "$root/scripts/setup.sh"

  wait_for_log "$log" '^update --quiet$' || fail "setup did not start quiet update check"
  grep -q '^setup$' "$log" || fail "setup did not initialize client cache"
}

test_setup_can_disable_update_check() {
  local plugin_root="$tmp/plugin-disabled"
  local cache="$tmp/cache-disabled"
  local log="$tmp/setup-disabled.log"
  write_fake_client "$plugin_root" "$log"

  PLUGIN_ROOT="$plugin_root" \
  ADTENTION_CACHE="$cache" \
  ADTENTION_DISABLE_UPDATE_CHECK=1 \
  "$root/scripts/setup.sh"

  grep -q '^setup$' "$log" || fail "setup did not initialize client cache"
  ! grep -q '^update --quiet$' "$log" || fail "setup started update check despite disable flag"
}

test_setup_starts_quiet_update_check
test_setup_can_disable_update_check

printf 'setup shell tests passed\n'
