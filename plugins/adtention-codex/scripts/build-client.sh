#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cargo="${CARGO:-cargo}"

"$cargo" build --release --manifest-path "$root/client/Cargo.toml"
mkdir -p "$root/bin"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$os" in
  darwin) os=darwin ;;
  linux) os=linux ;;
esac
case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
esac

asset="$root/bin/adtention-codex-$os-$arch"
cp "$root/client/target/release/adtention-codex" "$asset"
chmod +x "$asset"

cat > "$root/bin/adtention-codex" <<'SH'
#!/bin/sh
set -eu

d=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)

case "$os" in
  darwin) os=darwin ;;
  linux) os=linux ;;
esac

case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
esac

exec "$d/adtention-codex-$os-$arch" "$@"
SH
chmod +x "$root/bin/adtention-codex"

printf 'Built %s\n' "$asset"
