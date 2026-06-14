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
  ADTENTION_INSTALL_OS="$os_name" \
  ADTENTION_SKIP_CODEX_INSTALL=1 \
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
  PATH="$fake_bin:$PATH" \
  ADTENTION_INSTALL_OS="Linux" \
  ADTENTION_CODEX_APP_BIN="$good_codex" \
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
  [[ -f "$plist" ]] || fail "macOS install did not write LaunchAgent"
  grep -q 'viewability-daemon' "$plist" || fail "LaunchAgent does not start viewability daemon"
  grep -q "$installed_root/plugins/adtention-codex" "$home/.zshrc" || fail "macOS shell rc does not point at stable install root"
  grep -q 'ADTENTION_CACHE' "$plist" || fail "LaunchAgent does not pin shared cache path"
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
  [[ -f "$service" ]] || fail "Linux install did not write systemd user service"
  grep -q 'viewability-daemon' "$service" || fail "systemd service does not start viewability daemon"
  grep -q "$installed_root/plugins/adtention-codex" "$home/.bashrc" || fail "Linux shell rc does not point at stable install root"
  grep -q 'ADTENTION_CACHE' "$service" || fail "systemd service does not pin shared cache path"
  [[ "$(grep -c 'ADtention Codex' "$home/.bashrc")" -eq 2 ]] || fail "Linux .bashrc integration is not idempotent"
}

test_installer_skips_broken_codex_path_shim() {
  run_install_with_codex_lookup
}

test_macos_installer_is_one_command_and_idempotent
test_linux_installer_is_one_command_and_idempotent
test_installer_skips_broken_codex_path_shim

printf 'installer tests passed\n'
