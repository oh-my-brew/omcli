omcli_thread_writer_lock_pids() {
  omcli_lock_dir="$HOME/.codex/thread-writer-locks"
  [ -d "$omcli_lock_dir" ] || return 0
  /usr/sbin/lsof -t +D "$omcli_lock_dir" 2>/dev/null | /usr/bin/sort -nu
}

omcli_codex_usage() {
  cat <<'EOF'
Usage: omcli codex recover

Commands:
  recover                Terminate processes holding Codex thread-writer locks
  help                   Show this help

Use recover only after Codex reports an active writer or thread-lock conflict.
EOF
}

omcli_codex_recover() {
  [ "$#" -eq 0 ] || omcli_fail "codex does not accept arguments" || return

  omcli_lock_pids="$(omcli_thread_writer_lock_pids)" || \
    omcli_fail "cannot inspect Codex thread-writer locks" || return
  [ -n "$omcli_lock_pids" ] || {
    printf 'no Codex thread-writer lock holders found\n'
    return 0
  }

  set --
  for omcli_lock_pid in $omcli_lock_pids; do
    case "$omcli_lock_pid" in
      ''|*[!0-9]*) omcli_fail "invalid lock-holder process ID: $omcli_lock_pid" || return ;;
    esac
    set -- "$@" "$omcli_lock_pid"
  done

  omcli_run /bin/kill -TERM "$@" || \
    omcli_fail "failed to terminate one or more Codex thread-writer lock holders" || return
  printf 'sent SIGTERM to Codex thread-writer lock holders: %s\n' "$*"
}

omcli_codex() {
  omcli_codex_command="${1:-help}"
  if [ "$#" -gt 0 ]; then shift; fi
  case "$omcli_codex_command" in
    help|-h|--help)
      [ "$#" -eq 0 ] || omcli_fail "codex help does not accept arguments" || return
      omcli_codex_usage
      ;;
    recover) omcli_codex_recover "$@" ;;
    *) omcli_codex_usage >&2; omcli_fail "unknown codex command: $omcli_codex_command" ;;
  esac
}
