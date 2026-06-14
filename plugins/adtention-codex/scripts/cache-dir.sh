# Shared cache selection for ADtention clients.
#
# Claude shipped first and stores the user's publisher identity and balance in
# ~/.claude/adtention. Prefer that directory when it exists so Codex and Claude
# share the same account state. New Codex-only installs use ~/.adtention.

adtention_default_cache_dir() {
  if [ -n "${ADTENTION_CACHE:-}" ]; then
    printf '%s\n' "$ADTENTION_CACHE"
    return 0
  fi

  if [ -d "$HOME/.claude/adtention" ] || [ -f "$HOME/.claude/adtention/identity.json" ]; then
    printf '%s\n' "$HOME/.claude/adtention"
    return 0
  fi

  printf '%s\n' "$HOME/.adtention"
}
