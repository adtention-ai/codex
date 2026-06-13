#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cargo="${CARGO:-cargo}"

"$cargo" build --release --manifest-path "$root/client/Cargo.toml"
mkdir -p "$root/bin"
cp "$root/client/target/release/adtention-codex" "$root/bin/adtention-codex"
chmod +x "$root/bin/adtention-codex"

printf 'Built %s\n' "$root/bin/adtention-codex"

