#!/bin/sh
# Release build of the ADtention Codex client binaries.
#
# This follows the same release shape as adtention-claude: one root build script
# writes platform binaries into bin/ and CI/release use this script as the source
# of truth. Rust needs a linker for each target, so the release path uses a
# pinned Docker builder with Zig through cargo-zigbuild.
set -eu

cd "$(dirname "$0")"

PLUGIN_DIR="plugins/adtention-codex"
BIN_DIR="$PLUGIN_DIR/bin"
MANIFEST="$PLUGIN_DIR/.codex-plugin/plugin.json"
VERSION="v$(grep '"version"' "$MANIFEST" | head -1 \
  | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

echo "Building adtention-codex $VERSION"

write_launcher() {
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/adtention-codex" <<'SH'
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
  chmod +x "$BIN_DIR/adtention-codex"
}

if [ "${ADTENTION_BUILD_LOCAL_ONLY:-0}" = "1" ]; then
  cargo build --release --locked --manifest-path "$PLUGIN_DIR/client/Cargo.toml"
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
  mkdir -p "$BIN_DIR"
  cp "$PLUGIN_DIR/client/target/release/adtention-codex" "$BIN_DIR/adtention-codex-$os-$arch"
  chmod +x "$BIN_DIR/adtention-codex-$os-$arch"
  write_launcher
  echo "Wrote $BIN_DIR/adtention-codex-$os-$arch"
  exit 0
fi

docker run --rm --platform linux/amd64 \
  -e PLUGIN_DIR="$PLUGIN_DIR" \
  -e ZIG_VERSION="${ZIG_VERSION:-0.13.0}" \
  -e CARGO_ZIGBUILD_VERSION="${CARGO_ZIGBUILD_VERSION:-0.20.1}" \
  -v "$PWD":/w \
  -w /w \
  rust:1.83.0-bookworm sh -euc '
    zig_dir="/tmp/zig-linux-x86_64-$ZIG_VERSION"
    curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-linux-x86_64-$ZIG_VERSION.tar.xz" \
      | tar -xJ -C /tmp
    export PATH="$zig_dir:$PATH"

    cargo install --locked --version "$CARGO_ZIGBUILD_VERSION" cargo-zigbuild >/dev/null
    rustup target add \
      x86_64-apple-darwin \
      aarch64-apple-darwin \
      x86_64-unknown-linux-gnu \
      aarch64-unknown-linux-gnu \
      x86_64-pc-windows-gnu >/dev/null

    bin="$PLUGIN_DIR/bin"
    mkdir -p "$bin"
    rm -f "$bin"/adtention-codex-* "$bin/SHA256SUMS"

    build_one() {
      target="$1"
      asset="$2"
      exe="${3:-}"
      strip_config=""
      case "$target" in
        *-apple-darwin) strip_config="--config profile.release.strip=false" ;;
      esac
      cargo zigbuild --release --locked $strip_config \
        --manifest-path "$PLUGIN_DIR/client/Cargo.toml" --target "$target" >/dev/null
      cp "$PLUGIN_DIR/client/target/$target/release/adtention-codex$exe" "$bin/$asset$exe"
      if [ "$exe" = ".exe" ]; then
        python3 - "$bin/$asset$exe" <<'PY'
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
if data[:2] != b"MZ":
    raise SystemExit(f"{path} is not a PE executable")
pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
if data[pe_offset:pe_offset + 4] != b"PE\0\0":
    raise SystemExit(f"{path} has no PE header")
struct.pack_into("<I", data, pe_offset + 8, 0)
path.write_bytes(data)
PY
      fi
      chmod +x "$bin/$asset$exe" 2>/dev/null || true
      echo "  built $asset$exe"
    }

    build_one x86_64-apple-darwin adtention-codex-darwin-amd64
    build_one aarch64-apple-darwin adtention-codex-darwin-arm64
    build_one x86_64-unknown-linux-gnu adtention-codex-linux-amd64
    build_one aarch64-unknown-linux-gnu adtention-codex-linux-arm64
    build_one x86_64-pc-windows-gnu adtention-codex-windows-amd64 .exe

    cd "$bin"
    sha256sum \
      adtention-codex-darwin-amd64 \
      adtention-codex-darwin-arm64 \
      adtention-codex-linux-amd64 \
      adtention-codex-linux-arm64 \
      adtention-codex-windows-amd64.exe > SHA256SUMS
  '

write_launcher
rm -f .intentionally-empty-file.o
echo "Wrote $BIN_DIR/SHA256SUMS"
