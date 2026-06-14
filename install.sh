#!/usr/bin/env bash
set -euo pipefail

os_name="${ADTENTION_INSTALL_OS:-$(uname -s)}"
home_dir="${HOME:?HOME is required}"
install_root="${ADTENTION_INSTALL_ROOT:-$home_dir/.codex/adtention-codex}"
shared_cache="${ADTENTION_CACHE:-$home_dir/.codex/adtention}"
source_root=""
repo_root=""
plugin_root=""
client_bin=""

log() {
  printf '[adtention] %s\n' "$*"
}

find_codex() {
  local candidate
  for candidate in \
    "${CODEX_BIN:-}" \
    "${ADTENTION_CODEX_APP_BIN:-}" \
    "/Applications/Codex.app/Contents/Resources/codex" \
    "$(command -v codex 2>/dev/null || true)"
  do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    if "$candidate" --version >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

discover_source_root() {
  local script_path="${BASH_SOURCE[0]:-$0}"
  local candidate
  candidate="$(cd "$(dirname "$script_path")" 2>/dev/null && pwd || pwd)"
  if [ -f "$candidate/plugins/adtention-codex/.codex-plugin/plugin.json" ]; then
    source_root="$candidate"
    return 0
  fi
  if [ -f "$PWD/plugins/adtention-codex/.codex-plugin/plugin.json" ]; then
    source_root="$PWD"
    return 0
  fi
  source_root="$install_root"
  return 0
}

fetch_source_if_needed() {
  if [ -f "$source_root/plugins/adtention-codex/.codex-plugin/plugin.json" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$install_root")"
  if command -v git >/dev/null 2>&1; then
    rm -rf "$install_root.tmp"
    git clone --depth 1 https://github.com/adtention-ai/codex.git "$install_root.tmp" >/dev/null
    rm -rf "$install_root"
    mv "$install_root.tmp" "$install_root"
    source_root="$install_root"
    return 0
  fi
  log "Could not find repo files and git is unavailable. Clone https://github.com/adtention-ai/codex.git and run ./install.sh."
  exit 1
}

sync_to_install_root() {
  mkdir -p "$(dirname "$install_root")"
  if [ "$(cd "$source_root" && pwd)" = "$(mkdir -p "$install_root" && cd "$install_root" && pwd)" ]; then
    repo_root="$install_root"
    plugin_root="$repo_root/plugins/adtention-codex"
    client_bin="$plugin_root/bin/adtention-codex"
    return 0
  fi

  rm -rf "$install_root.tmp"
  mkdir -p "$install_root.tmp"
  (
    cd "$source_root"
    tar \
      --exclude './.git' \
      --exclude './plugins/adtention-codex/client/target' \
      -cf - .
  ) | (
    cd "$install_root.tmp"
    tar -xf -
  )
  rm -rf "$install_root"
  mv "$install_root.tmp" "$install_root"
  repo_root="$install_root"
  plugin_root="$repo_root/plugins/adtention-codex"
  client_bin="$plugin_root/bin/adtention-codex"
}

ensure_client() {
  local check_cache
  check_cache="$(mktemp -d "${TMPDIR:-/tmp}/adtention-client-check.XXXXXX")"
  if [ -x "$client_bin" ] && ADTENTION_CACHE="$check_cache" "$client_bin" setup >/dev/null 2>&1; then
    rm -rf "$check_cache"
    return 0
  fi
  rm -rf "$check_cache"
  if ! command -v cargo >/dev/null 2>&1; then
    log "Rust/Cargo is required to build $client_bin because no prebuilt binary is present."
    exit 1
  fi
  "$plugin_root/scripts/build-client.sh" >/dev/null
}

install_codex_plugin() {
  if [ "${ADTENTION_SKIP_CODEX_INSTALL:-0}" = "1" ]; then
    log "Skipping Codex plugin install because ADTENTION_SKIP_CODEX_INSTALL=1"
    return 0
  fi
  local codex_bin
  if ! codex_bin="$(find_codex)"; then
    log "Codex CLI not found. Install Codex or set CODEX_BIN, then rerun this installer."
    exit 1
  fi
  "$codex_bin" plugin marketplace add "$repo_root" >/dev/null || true
  "$codex_bin" plugin add adtention-codex@adtention-local >/dev/null
}

install_shell_integration() {
  HOME="$home_dir" ADTENTION_PLUGIN_ROOT="$plugin_root" ADTENTION_CACHE="$shared_cache" "$plugin_root/scripts/install-shell-integration.sh" >/dev/null
}

install_macos_helper() {
  local launch_dir="$home_dir/Library/LaunchAgents"
  local plist="$launch_dir/ai.adtention.codex.viewability.plist"
  mkdir -p "$launch_dir"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>ai.adtention.codex.viewability</string>
  <key>ProgramArguments</key>
  <array>
    <string>$client_bin</string>
    <string>viewability-daemon</string>
    <string>Codex</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ADTENTION_CACHE</key>
    <string>$shared_cache</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$home_dir/.codex/adtention/viewability.log</string>
  <key>StandardErrorPath</key>
  <string>$home_dir/.codex/adtention/viewability.err.log</string>
</dict>
</plist>
EOF
  if [ "${ADTENTION_NO_START_SERVICE:-0}" != "1" ] && command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  fi
}

install_linux_helper() {
  local service_dir="$home_dir/.config/systemd/user"
  local service="$service_dir/adtention-codex-viewability.service"
  mkdir -p "$service_dir"
  cat > "$service" <<EOF
[Unit]
Description=ADtention Codex viewability helper

[Service]
Environment=ADTENTION_CACHE=$shared_cache
ExecStart=$client_bin viewability-daemon Codex
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
  if [ "${ADTENTION_NO_START_SERVICE:-0}" != "1" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now adtention-codex-viewability.service >/dev/null 2>&1 || true
  fi
}

install_viewability_helper() {
  case "$os_name" in
    Darwin) install_macos_helper ;;
    Linux) install_linux_helper ;;
    *)
      log "No Unix helper installer for OS '$os_name'. Windows uses install.ps1."
      ;;
  esac
}

main() {
  discover_source_root
  fetch_source_if_needed
  sync_to_install_root
  mkdir -p "$shared_cache"
  ensure_client
  install_codex_plugin
  install_shell_integration
  install_viewability_helper
  "$client_bin" setup >/dev/null 2>&1 || true
  log "Installed ADtention for Codex."
}

main "$@"
