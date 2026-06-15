# ADtention for Codex shell integration.
# Source this file from zsh or bash. Sourcing is quiet by default: it defines
# helpers and a scoped codex wrapper, but it does not render in every terminal.

if [ -z "${ADTENTION_PLUGIN_ROOT:-}" ]; then
  if [ -n "${BASH_SOURCE:-}" ]; then
    ADTENTION_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    ADTENTION_PLUGIN_ROOT="$(cd "$(dirname "${(%):-%N}")/.." 2>/dev/null && pwd)"
  fi
fi

if [ -n "${ADTENTION_PLUGIN_ROOT:-}" ] && [ -r "$ADTENTION_PLUGIN_ROOT/scripts/cache-dir.sh" ]; then
  # shellcheck disable=SC1091
  . "$ADTENTION_PLUGIN_ROOT/scripts/cache-dir.sh"
fi

__adtention_codex_cache_dir() {
  if command -v adtention_default_cache_dir >/dev/null 2>&1; then
    adtention_default_cache_dir
  else
    printf '%s\n' "${ADTENTION_CACHE:-$HOME/.adtention}"
  fi
}

__adtention_codex_should_display() {
  [ "${ADTENTION_DISPLAY:-0}" = "1" ] || \
    [ "${ADTENTION_CODEX_ACTIVE:-0}" = "1" ] || \
    [ "${ADTENTION_CODEX_DISPLAY:-0}" = "1" ] || \
    [ "${CODEX_SHELL:-0}" = "1" ] || \
    [ "${__CFBundleIdentifier:-}" = "com.openai.codex" ]
}

__adtention_codex_should_run_title_daemon() {
  [ "${ADTENTION_DISPLAY:-0}" = "1" ] || \
    [ "${ADTENTION_CODEX_ACTIVE:-0}" = "1" ] || \
    [ "${ADTENTION_CODEX_DISPLAY:-0}" = "1" ]
}

__adtention_codex_prompt() {
  __adtention_codex_should_display || return 0

  local cache title line
  cache="$(__adtention_codex_cache_dir)"

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

__adtention_codex_title_daemon_running() {
  local cache pid_file pid
  cache="$(__adtention_codex_cache_dir)"
  pid_file="$cache/title_daemon.pid"
  [ -s "$pid_file" ] || return 1
  IFS= read -r pid < "$pid_file" || return 1
  case "$pid" in (*[!0-9]*|'') return 1;; esac
  kill -0 "$pid" 2>/dev/null
}

__adtention_codex_start_title_daemon() {
  [ "${ADTENTION_DISABLE_TITLE_DAEMON:-0}" = "1" ] && return 0
  [ "${ADTENTION_TITLE_DAEMON:-1}" = "0" ] && return 0
  __adtention_codex_title_daemon_running && {
    export ADTENTION_CODEX_TITLE_DAEMON_STARTED=1
    return 0
  }

  local bin cache pid_file
  bin="$(__adtention_codex_find_bin)" || return 0
  cache="$(__adtention_codex_cache_dir)"
  pid_file="$cache/title_daemon.pid"
  mkdir -p "$cache" 2>/dev/null || return 0
  export ADTENTION_CODEX_TITLE_DAEMON_STARTED=1
  if { : >/dev/tty; } 2>/dev/null; then
    ( ADTENTION_PARENT_PID="$$" "$bin" title-daemon >/dev/tty 2>/dev/null & printf '%s\n' "$!" > "$pid_file" )
  else
    ( ADTENTION_PARENT_PID="$$" "$bin" title-daemon >/dev/null 2>/dev/null & printf '%s\n' "$!" > "$pid_file" )
  fi
}

__adtention_codex_stop_title_daemon() {
  local cache pid_file pid
  cache="$(__adtention_codex_cache_dir)"
  pid_file="$cache/title_daemon.pid"
  [ -s "$pid_file" ] || return 0
  IFS= read -r pid < "$pid_file" || return 0
  case "$pid" in (*[!0-9]*|'') rm -f "$pid_file"; return 0;; esac
  kill "$pid" 2>/dev/null || true
  rm -f "$pid_file"
  unset ADTENTION_CODEX_TITLE_DAEMON_STARTED
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

learn-more() {
  local bin
  if ! bin="$(__adtention_codex_find_bin)"; then
    printf '%s\n' "adtention: client binary not found." >&2
    return 1
  fi
  "$bin" learn-more "$@"
}

adtention-open() {
  learn-more "$@"
}

adtention-codex-on() {
  export ADTENTION_DISPLAY=1
  __adtention_codex_start_title_daemon
  __adtention_codex_prompt
}

adtention-codex-off() {
  unset ADTENTION_DISPLAY
  unset ADTENTION_CODEX_ACTIVE
  unset ADTENTION_CODEX_DISPLAY
  __adtention_codex_stop_title_daemon
}

__adtention_codex_capture_real_codex() {
  [ -n "${ADTENTION_REAL_CODEX_BIN:-}" ] && return 0

  local candidate
  candidate="$(command -v codex 2>/dev/null || true)"
  case "$candidate" in
    /*)
      export ADTENTION_REAL_CODEX_BIN="$candidate"
      ;;
  esac
}

__adtention_codex_install_codex_wrapper() {
  [ "${ADTENTION_WRAP_CODEX_CLI:-1}" != "0" ] || return 0
  [ -n "${ADTENTION_REAL_CODEX_BIN:-}" ] || return 0

  codex() {
    local adtention_status had_display old_display had_active old_active had_daemon
    had_display=0
    old_display=""
    had_active=0
    old_active=""
    had_daemon=0

    if [ "${ADTENTION_DISPLAY+x}" = "x" ]; then
      had_display=1
      old_display="$ADTENTION_DISPLAY"
    fi
    if [ "${ADTENTION_CODEX_ACTIVE+x}" = "x" ]; then
      had_active=1
      old_active="$ADTENTION_CODEX_ACTIVE"
    fi
    __adtention_codex_title_daemon_running && had_daemon=1

    export ADTENTION_DISPLAY=1
    export ADTENTION_CODEX_ACTIVE=1
    __adtention_codex_start_title_daemon

    "$ADTENTION_REAL_CODEX_BIN" "$@"
    adtention_status=$?

    if [ "$had_daemon" -eq 0 ]; then
      __adtention_codex_stop_title_daemon
    fi
    if [ "$had_display" -eq 1 ]; then
      export ADTENTION_DISPLAY="$old_display"
    else
      unset ADTENTION_DISPLAY
    fi
    if [ "$had_active" -eq 1 ]; then
      export ADTENTION_CODEX_ACTIVE="$old_active"
    else
      unset ADTENTION_CODEX_ACTIVE
    fi

    return "$adtention_status"
  }
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

__adtention_codex_capture_real_codex
__adtention_codex_install_codex_wrapper
__adtention_codex_install_prompt_hook
if __adtention_codex_should_display; then
  if __adtention_codex_should_run_title_daemon; then
    __adtention_codex_start_title_daemon
  fi
fi
