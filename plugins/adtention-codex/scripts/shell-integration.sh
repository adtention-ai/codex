# ADtention for Codex shell integration.
# Source this file from zsh or bash. The prompt path uses shell builtins only.

if [ -z "${ADTENTION_PLUGIN_ROOT:-}" ]; then
  if [ -n "${BASH_SOURCE:-}" ]; then
    ADTENTION_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    ADTENTION_PLUGIN_ROOT="$(cd "$(dirname "${(%):-%N}")/.." 2>/dev/null && pwd)"
  fi
fi

__adtention_codex_prompt() {
  local cache title line
  cache="${ADTENTION_CACHE:-$HOME/.codex/adtention}"

  if [ -r "$cache/terminal.txt" ]; then
    {
      IFS= read -r title || title=""
      IFS= read -r line || line=""
    } < "$cache/terminal.txt"
  else
    title=""
    line=""
  fi

  if [ -z "$title" ] && [ -r "$cache/title.txt" ]; then
    IFS= read -r title < "$cache/title.txt" || title=""
  fi

  if [ -z "$line" ] && [ -r "$cache/prompt_line.txt" ]; then
    IFS= read -r line < "$cache/prompt_line.txt" || line=""
  fi

  if [ -n "$title" ]; then
    printf '\033]0;%s\007' "$title"
    : > "$cache/last_render_seen" 2>/dev/null || true
  fi

  if [ "${ADTENTION_PROMPT_LINE:-1}" != "0" ] && [ -n "$line" ]; then
    printf '%s\n' "$line"
  fi
}

__adtention_codex_start_title_daemon() {
  [ "${ADTENTION_DISABLE_TITLE_DAEMON:-0}" = "1" ] && return 0
  [ "${ADTENTION_TITLE_DAEMON:-1}" = "0" ] && return 0
  [ -n "${ADTENTION_CODEX_TITLE_DAEMON_STARTED:-}" ] && return 0

  local bin
  bin="$(__adtention_codex_find_bin)" || return 0
  export ADTENTION_CODEX_TITLE_DAEMON_STARTED=1
  if [ -w /dev/tty ]; then
    "$bin" title-daemon >/dev/tty 2>/dev/null &
  else
    "$bin" title-daemon >/dev/null 2>/dev/null &
  fi
}

__adtention_codex_find_bin() {
  local root bin
  root="${ADTENTION_PLUGIN_ROOT:-}"
  for bin in \
    "${ADTENTION_CODEX_BIN:-}" \
    "$root/bin/adtention-codex" \
    "$root/client/target/release/adtention-codex" \
    "$root/client/target/debug/adtention-codex"
  do
    [ -n "$bin" ] || continue
    [ -x "$bin" ] || continue
    printf '%s\n' "$bin"
    return 0
  done
  return 1
}

adtention-open() {
  local bin
  if ! bin="$(__adtention_codex_find_bin)"; then
    printf '%s\n' "adtention: client binary not found." >&2
    return 1
  fi
  "$bin" open "$@"
}

__adtention_codex_install_prompt_hook() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null || true
    if command -v add-zsh-hook >/dev/null 2>&1; then
      add-zsh-hook precmd __adtention_codex_prompt 2>/dev/null || true
    else
      precmd_functions+=(__adtention_codex_prompt)
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    case ";${PROMPT_COMMAND:-};" in
      *";__adtention_codex_prompt;"*) ;;
      *) PROMPT_COMMAND="__adtention_codex_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
  fi
}

__adtention_codex_start_title_daemon
__adtention_codex_install_prompt_hook
