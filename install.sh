#!/usr/bin/env bash
set -euo pipefail

home_dir="${HOME:?HOME is required}"
install_root="${ADTENTION_INSTALL_ROOT:-$home_dir/.codex/adtention-codex}"
source_root=""
repo_root=""
plugin_root=""
client_bin=""
ref_code="${ADTENTION_REF:-}"
release_version="${ADTENTION_VERSION:-latest}"

default_cache_dir() {
  if [ -n "${ADTENTION_CACHE:-}" ]; then
    printf '%s\n' "$ADTENTION_CACHE"
    return 0
  fi
  if [ -d "$home_dir/.claude/adtention" ] || [ -f "$home_dir/.claude/adtention/identity.json" ]; then
    printf '%s\n' "$home_dir/.claude/adtention"
    return 0
  fi
  printf '%s\n' "$home_dir/.adtention"
}

shared_cache="$(default_cache_dir)"

log() {
  printf '[adtention] %s\n' "$*"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ref)
        [ "$#" -ge 2 ] || { log "--ref requires a value"; exit 2; }
        ref_code="$2"
        shift 2
        ;;
      --version)
        [ "$#" -ge 2 ] || { log "--version requires a value"; exit 2; }
        release_version="$2"
        shift 2
        ;;
      *)
        log "Unknown argument: $1"
        exit 2
        ;;
    esac
  done
}

sanitize_ref() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cd 'a-z0-9' | cut -c 1-32
}

write_ref_code() {
  local safe_ref
  safe_ref="$(sanitize_ref "$ref_code")"
  [ -n "$safe_ref" ] || return 0
  mkdir -p "$shared_cache"
  printf '%s' "$safe_ref" > "$shared_cache/ref"
  chmod 600 "$shared_cache/ref" 2>/dev/null || true
}

migrate_legacy_cache() {
  local legacy file
  legacy="$home_dir/.codex/adtention"
  [ "$legacy" != "$shared_cache" ] || return 0
  [ -d "$legacy" ] || return 0
  mkdir -p "$shared_cache"
  for file in identity.json balance balance_display current_ad.txt current_click.txt title.txt prompt_line.txt terminal.txt category.txt source.txt ref; do
    [ -e "$legacy/$file" ] || continue
    [ ! -e "$shared_cache/$file" ] || continue
    cp -p "$legacy/$file" "$shared_cache/$file" 2>/dev/null || cp "$legacy/$file" "$shared_cache/$file" 2>/dev/null || true
  done
}

stop_old_title_daemons() {
  [ "${ADTENTION_SKIP_DAEMON_CLEANUP:-0}" = "1" ] && return 0
  if command -v pkill >/dev/null 2>&1; then
    pkill -f 'adtention-codex.*title-daemon' 2>/dev/null || true
  fi
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

release_asset_name() {
  local os_name arch
  os_name="${ADTENTION_INSTALL_OS:-$(uname -s)}"
  arch="${ADTENTION_INSTALL_ARCH:-$(uname -m)}"
  case "$arch" in
    x86_64|amd64) arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
  esac
  case "$os_name:$arch" in
    Darwin:amd64|darwin:amd64) printf '%s\n' "adtention-codex-darwin-amd64" ;;
    Darwin:arm64|darwin:arm64) printf '%s\n' "adtention-codex-darwin-arm64" ;;
    Linux:amd64|linux:amd64) printf '%s\n' "adtention-codex-linux-amd64" ;;
    Linux:arm64|linux:arm64) printf '%s\n' "adtention-codex-linux-arm64" ;;
    *) return 1 ;;
  esac
}

download_release_binary() {
  [ "${ADTENTION_SKIP_BINARY_DOWNLOAD:-0}" != "1" ] || return 1
  local asset url tmp
  asset="$(release_asset_name)" || return 1
  mkdir -p "$plugin_root/bin"

  if [ "$release_version" = "latest" ]; then
    url="https://github.com/adtention-ai/codex/releases/latest/download/$asset"
  else
    url="https://github.com/adtention-ai/codex/releases/download/$release_version/$asset"
  fi

  tmp="$plugin_root/bin/$asset.download"
  rm -f "$tmp"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  else
    return 1
  fi
  mv "$tmp" "$plugin_root/bin/$asset"
  chmod +x "$plugin_root/bin/$asset"
  log "Installed prebuilt client $asset"
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

main() {
  parse_args "$@"
  discover_source_root
  fetch_source_if_needed
  sync_to_install_root
  mkdir -p "$shared_cache"
  migrate_legacy_cache
  write_ref_code
  stop_old_title_daemons
  download_release_binary || true
  ensure_client
  install_codex_plugin
  install_shell_integration
  "$client_bin" setup >/dev/null 2>&1 || true
  log "Installed ADtention for Codex."
}

main "$@"
