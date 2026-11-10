#!/bin/sh
# This launcher is added only to FoxVim terminal PATHs; other shells keep normal Codex.
if [ "$#" -eq 0 ] && [ -n "$FOX_AGENTIC_TOKEN" ] && [ -n "$FOX_AGENTIC_SERVER" ]; then
  session_id=$("$FOX_AGENTIC_NVIM" --headless -u NONE -i NONE -n -l "$FOX_AGENTIC_BRIDGE" create)
  bridge_status=$?
  case "$session_id" in ''|*[!a-zA-Z0-9_-]*) bridge_status=1 ;; esac
  if [ "$bridge_status" -eq 0 ]; then
    (unset FOX_AGENTIC_TOKEN FOX_AGENTIC_SERVER; "$FOX_AGENTIC_REAL_CODEX" resume "$session_id")
    codex_status=$?
    "$FOX_AGENTIC_NVIM" --headless -u NONE -i NONE -n -l "$FOX_AGENTIC_BRIDGE" finish "$session_id" >/dev/null 2>&1
    exit "$codex_status"
  fi
fi
unset FOX_AGENTIC_TOKEN FOX_AGENTIC_SERVER
exec "$FOX_AGENTIC_REAL_CODEX" "$@"
