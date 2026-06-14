#!/usr/bin/env bash
# ADtention for Codex: UserPromptSubmit hook. Must stay silent.
set -u

input=$(cat 2>/dev/null || true)
root="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
if [ -r "$root/scripts/cache-dir.sh" ]; then
  # shellcheck disable=SC1091
  . "$root/scripts/cache-dir.sh"
fi
cache_dir="$(adtention_default_cache_dir 2>/dev/null || printf '%s\n' "${ADTENTION_CACHE:-$HOME/.adtention}")"
mkdir -p "$cache_dir" 2>/dev/null || true

cwd="$PWD"
transcript=""

if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  parsed_cwd=$(printf '%s' "$input" | jq -r '
    [
      .cwd?,
      .workspace_root?,
      .workspaceRoot?,
      .project_root?,
      .projectRoot?,
      .session.cwd?,
      .context.cwd?
    ] | map(select(type == "string" and length > 0)) | .[0] // empty
  ' 2>/dev/null || true)
  parsed_transcript=$(printf '%s' "$input" | jq -r '
    [
      .transcript_path?,
      .transcriptPath?,
      .agent_transcript_path?,
      .agentTranscriptPath?,
      .session.transcript_path?,
      .session.transcriptPath?
    ] | map(select(type == "string" and length > 0)) | .[0] // empty
  ' 2>/dev/null || true)
  [ -n "$parsed_cwd" ] && cwd="$parsed_cwd"
  [ -n "$parsed_transcript" ] && transcript="$parsed_transcript"
fi

if [ "${ADTENTION_DEBUG_HOOK:-0}" = "1" ]; then
  printf '%s' "$input" > "$cache_dir/last_hook_input.json" 2>/dev/null || true
fi

for bin in \
  "$root/bin/adtention-codex" \
  "$root/client/target/release/adtention-codex" \
  "$root/client/target/debug/adtention-codex"
do
  if [ -x "$bin" ]; then
    (
      printf '%s' "$input" | "$bin" refresh "$cwd" "$transcript"
    ) >/dev/null 2>&1 &
    exit 0
  fi
done

(
  printf '%s' "$input" | "$root/scripts/refresh.sh" "$cwd" "$transcript"
) >/dev/null 2>&1 &

exit 0
