#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/adtention-refresh-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

fake_bin="$tmp/bin"
cache="$tmp/cache"
log="$tmp/curl.log"
mkdir -p "$fake_bin" "$cache"

cat > "$fake_bin/curl" <<SH
#!/usr/bin/env bash
body=""
url=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -d) body="\$2"; shift 2 ;;
    http*) url="\$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\\t%s\\n' "\$url" "\$body" >> "$log"
case "\$url" in
  */v1/register) printf '{"publisher_id":"pub_shell"}' ;;
  */v1/serve) printf '{"text":"Shell fallback sponsor","balance_usd":3.21,"click_url":"https://example.com/shell"}' ;;
  *) exit 22 ;;
esac
SH
chmod +x "$fake_bin/curl"

test_refresh_serves_after_render_without_viewability() {
  : > "$cache/last_render_seen"
  printf 'ABC-123_!!' > "$cache/ref"

  PATH="$fake_bin:$PATH" \
  ADTENTION_CACHE="$cache" \
  ADTENTION_API="http://127.0.0.1:9" \
  ADTENTION_MIN_DWELL=0 \
  "$root/scripts/refresh.sh" "$PWD" "" <<<'{"prompt":"Fix this React component"}'

  grep -q '/v1/register' "$log" || fail "refresh did not register"
  grep -q '{"ref":"abc123"}' "$log" || fail "refresh did not send sanitized referral code"
  grep -q '/v1/serve' "$log" || fail "refresh did not serve"
  ! grep -q 'viewability' "$log" || fail "serve payload should not include viewability"
  grep -q 'Shell fallback sponsor' "$cache/current_ad.txt" || fail "ad cache was not updated"
  grep -q 'https://example.com/shell' "$cache/current_click.txt" || fail "click cache was not updated"
  [[ ! -f "$cache/ref" ]] || fail "referral file was not consumed after registration"
}

test_refresh_serves_after_render_without_viewability

printf 'refresh shell tests passed\n'
