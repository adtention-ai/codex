#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/adtention-install-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_install() {
  local os_name="$1"
  HOME="$tmp/home-$os_name" \
  ADTENTION_CACHE= \
  ADTENTION_INSTALL_OS="$os_name" \
  ADTENTION_SKIP_BINARY_DOWNLOAD=1 \
  ADTENTION_SKIP_CODEX_INSTALL=1 \
  ADTENTION_SKIP_DAEMON_CLEANUP=1 \
  ADTENTION_NO_START_SERVICE=1 \
  "$repo_root/install.sh" >/tmp/adtention-install-test.out
}

run_install_with_codex_lookup() {
  local fake_bin="$tmp/fake-bin"
  local good_codex="$tmp/good-codex"
  local codex_log="$tmp/codex.log"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/codex" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$fake_bin/codex"
  cat > "$good_codex" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then
  printf 'codex-cli test\\n'
  exit 0
fi
printf '%s\\n' "\$*" >> "$codex_log"
exit 0
SH
  chmod +x "$good_codex"

  HOME="$tmp/home-codex-lookup" \
  ADTENTION_CACHE= \
  PATH="$fake_bin:$PATH" \
  ADTENTION_INSTALL_OS="Linux" \
  ADTENTION_SKIP_BINARY_DOWNLOAD=1 \
  ADTENTION_CODEX_APP_BIN="$good_codex" \
  ADTENTION_SKIP_DAEMON_CLEANUP=1 \
  ADTENTION_NO_START_SERVICE=1 \
  "$repo_root/install.sh" >/tmp/adtention-install-test-codex.out

  grep -q 'plugin marketplace add' "$codex_log" || fail "installer did not add marketplace with working Codex binary"
  grep -q 'plugin add adtention-codex@adtention-local' "$codex_log" || fail "installer did not add plugin with working Codex binary"
}

test_macos_installer_is_one_command_and_idempotent() {
  run_install Darwin
  run_install Darwin

  local home="$tmp/home-Darwin"
  local installed_root="$home/.codex/adtention-codex"
  local plist="$home/Library/LaunchAgents/ai.adtention.codex.viewability.plist"
  [[ -f "$home/.zshrc" ]] || fail "macOS install did not write .zshrc"
  [[ -f "$home/.bashrc" ]] || fail "macOS install did not write .bashrc"
  [[ -x "$installed_root/plugins/adtention-codex/bin/adtention-codex" ]] || fail "macOS install did not copy client to stable install root"
  [[ ! -f "$plist" ]] || fail "macOS install should not write a viewability LaunchAgent"
  grep -q "$installed_root/plugins/adtention-codex" "$home/.zshrc" || fail "macOS shell rc does not point at stable install root"
  [[ "$(grep -c 'ADtention Codex' "$home/.zshrc")" -eq 2 ]] || fail "macOS .zshrc integration is not idempotent"
}

test_linux_installer_is_one_command_and_idempotent() {
  run_install Linux
  run_install Linux

  local home="$tmp/home-Linux"
  local installed_root="$home/.codex/adtention-codex"
  local service="$home/.config/systemd/user/adtention-codex-viewability.service"
  [[ -f "$home/.zshrc" ]] || fail "Linux install did not write .zshrc"
  [[ -f "$home/.bashrc" ]] || fail "Linux install did not write .bashrc"
  [[ -x "$installed_root/plugins/adtention-codex/bin/adtention-codex" ]] || fail "Linux install did not copy client to stable install root"
  [[ ! -f "$service" ]] || fail "Linux install should not write a viewability systemd service"
  grep -q "$installed_root/plugins/adtention-codex" "$home/.bashrc" || fail "Linux shell rc does not point at stable install root"
  [[ "$(grep -c 'ADtention Codex' "$home/.bashrc")" -eq 2 ]] || fail "Linux .bashrc integration is not idempotent"
}

test_installer_skips_broken_codex_path_shim() {
  run_install_with_codex_lookup
}

test_installer_downloads_release_binary_and_writes_ref() {
  local fake_bin="$tmp/fake-download-bin"
  local curl_log="$tmp/download-curl.log"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/curl" <<SH
#!/usr/bin/env bash
out=""
url=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    http*) url="\$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\\n' "\$url" >> "$curl_log"
cat > "\$out" <<'BIN'
#!/usr/bin/env bash
if [ "\${1:-}" = "setup" ]; then
  mkdir -p "\${ADTENTION_CACHE:-\$HOME/.adtention}"
  exit 0
fi
printf 'fake release binary\n'
BIN
chmod +x "\$out"
SH
  chmod +x "$fake_bin/curl"

  HOME="$tmp/home-download" \
  ADTENTION_CACHE= \
  PATH="$fake_bin:$PATH" \
  ADTENTION_INSTALL_OS="Linux" \
  ADTENTION_INSTALL_ARCH="x86_64" \
  ADTENTION_SKIP_CODEX_INSTALL=1 \
  ADTENTION_SKIP_DAEMON_CLEANUP=1 \
  "$repo_root/install.sh" --version v9.9.9 --ref "ABC-123_!!" >/tmp/adtention-install-test-download.out

  local installed_root="$tmp/home-download/.codex/adtention-codex"
  grep -q 'releases/download/v9.9.9/adtention-codex-linux-amd64' "$curl_log" || fail "installer did not download linux amd64 release asset"
  [[ -x "$installed_root/plugins/adtention-codex/bin/adtention-codex-linux-amd64" ]] || fail "downloaded release asset is missing"
  [[ "$(cat "$tmp/home-download/.adtention/ref")" = "abc123" ]] || fail "installer did not write sanitized referral code"
}

test_installer_uses_claude_cache_when_present() {
  local home="$tmp/home-claude-cache"
  mkdir -p "$home/.claude/adtention"

  HOME="$home" \
  ADTENTION_CACHE= \
  ADTENTION_INSTALL_OS="Linux" \
  ADTENTION_SKIP_BINARY_DOWNLOAD=1 \
  ADTENTION_SKIP_CODEX_INSTALL=1 \
  ADTENTION_SKIP_DAEMON_CLEANUP=1 \
  ADTENTION_NO_START_SERVICE=1 \
  "$repo_root/install.sh" >/tmp/adtention-install-test-claude.out

  grep -q "$home/.claude/adtention" "$home/.zshrc" || fail "installer did not point shell integration at existing Claude cache"
}

test_installer_migrates_legacy_codex_cache() {
  local home="$tmp/home-legacy-cache"
  mkdir -p "$home/.codex/adtention"
  printf '{"publisher_id":"pub_legacy"}' > "$home/.codex/adtention/identity.json"
  printf '⊕ $4.20' > "$home/.codex/adtention/balance_display"

  HOME="$home" \
  ADTENTION_CACHE= \
  ADTENTION_INSTALL_OS="Linux" \
  ADTENTION_SKIP_BINARY_DOWNLOAD=1 \
  ADTENTION_SKIP_CODEX_INSTALL=1 \
  ADTENTION_SKIP_DAEMON_CLEANUP=1 \
  ADTENTION_NO_START_SERVICE=1 \
  "$repo_root/install.sh" >/tmp/adtention-install-test-legacy.out

  grep -q 'pub_legacy' "$home/.adtention/identity.json" || fail "installer did not migrate legacy identity"
  grep -q '⊕ $4.20' "$home/.adtention/balance_display" || fail "installer did not migrate legacy balance"
}

test_macos_installer_is_one_command_and_idempotent
test_linux_installer_is_one_command_and_idempotent
test_installer_skips_broken_codex_path_shim
test_installer_downloads_release_binary_and_writes_ref
test_installer_uses_claude_cache_when_present
test_installer_migrates_legacy_codex_cache

printf 'installer tests passed\n'
