#!/bin/sh

OMCLI_VERSION="@VERSION@"

omcli_usage() {
  cat <<'EOF'
Usage: omcli <command> [arguments]

Commands:
  lockscreen             Lock the macOS screen immediately
  ncdu [command]         Create or read ncdu snapshots
  sidecar [command]      Connect or disconnect an iPad with Sidecar
  xcodex                 Terminate processes holding Codex thread-writer locks
  help                   Show this help

Options:
  -h, --help             Show this help
  -v, --version          Show the installed version

Run "omcli ncdu help" for ncdu snapshot commands.
Run "omcli sidecar help" for Sidecar commands.
EOF
}

omcli_fail() {
  printf 'omcli: %s\n' "$*" >&2
  return 1
}

omcli_resolve_self() {
  omcli_target="$1"
  while [ -L "$omcli_target" ]; do
    omcli_link="$(/usr/bin/readlink "$omcli_target")" || return 1
    case "$omcli_link" in
      /*) omcli_target="$omcli_link" ;;
      *) omcli_target="$(dirname -- "$omcli_target")/$omcli_link" ;;
    esac
  done
  omcli_dir="$(CDPATH='' cd -- "$(dirname -- "$omcli_target")" && pwd)" || return 1
  printf '%s/%s\n' "$omcli_dir" "$(basename -- "$omcli_target")"
}

omcli_external() {
  exec "$@"
}

omcli_run() {
  "$@"
}

omcli_lockscreen_path() {
  omcli_self="$(omcli_resolve_self "$0")" || omcli_fail "cannot resolve executable path" || return
  omcli_bin_dir="$(dirname -- "$omcli_self")"
  printf '%s/../libexec/omcli-lockscreen\n' "$omcli_bin_dir"
}

omcli_helper_is_executable() {
  [ -x "$1" ]
}

omcli_lockscreen() {
  [ "$#" -eq 0 ] || omcli_fail "lockscreen does not accept arguments" || return
  omcli_helper="$(omcli_lockscreen_path)" || return
  omcli_helper_is_executable "$omcli_helper" || omcli_fail "lockscreen helper is not installed" || return
  omcli_external "$omcli_helper"
}

omcli_sidecar_path() {
  omcli_self="$(omcli_resolve_self "$0")" || omcli_fail "cannot resolve executable path" || return
  omcli_bin_dir="$(dirname -- "$omcli_self")"
  printf '%s/../libexec/omcli-sidecar\n' "$omcli_bin_dir"
}

omcli_sidecar_usage() {
  cat <<'EOF'
Usage: omcli sidecar <command> [device]

Connect and disconnect supported iPads using macOS Sidecar.
Running without a command displays this help and does not change displays.

Commands:
  list                   List reachable Sidecar devices
  connect [DEVICE]       Connect DEVICE, or the only reachable device
  disconnect [DEVICE]    Disconnect DEVICE, or the only connected device
  help                   Show this help

Options:
  -h, --help             Show this help
EOF
}

omcli_sidecar() {
  omcli_sidecar_command="${1:-help}"
  if [ "$#" -gt 0 ]; then shift; fi

  case "$omcli_sidecar_command" in
    help|-h|--help)
      [ "$#" -eq 0 ] || omcli_fail "sidecar help does not accept arguments" || return
      omcli_sidecar_usage
      return
      ;;
    list)
      [ "$#" -eq 0 ] || omcli_fail "sidecar list does not accept arguments" || return
      ;;
    connect|disconnect)
      [ "$#" -le 1 ] || omcli_fail "sidecar $omcli_sidecar_command accepts at most one device" || return
      ;;
    *)
      omcli_sidecar_usage >&2
      omcli_fail "unknown sidecar command: $omcli_sidecar_command" || return
      ;;
  esac

  omcli_helper="$(omcli_sidecar_path)" || return
  omcli_helper_is_executable "$omcli_helper" || omcli_fail "sidecar helper is not installed" || return
  omcli_external "$omcli_helper" "$omcli_sidecar_command" "$@"
}

omcli_has_ncdu() {
  command -v ncdu >/dev/null 2>&1
}

omcli_epoch() {
  /bin/date +%s
}

omcli_ncdu_threads() {
  omcli_detected_threads="$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null)" || \
    omcli_detected_threads=1
  case "$omcli_detected_threads" in
    ''|0|*[!0-9]*) omcli_detected_threads=1 ;;
  esac
  printf '%s\n' "$omcli_detected_threads"
}

omcli_ncdu_usage() {
  cat <<'EOF'
Usage: omcli ncdu <command> [arguments]

Create and read ncdu snapshots of the startup volume.
Running without a command displays this help and does not scan the disk.

Commands:
  dump                   Scan the startup volume into ~/.ncdu.<timestamp>
  read [FILE]            Open FILE, or the latest timestamped snapshot
  help                   Show this help

Options:
  -h, --help             Show this help
EOF
}

omcli_ncdu_dump() {
  [ "$#" -eq 0 ] || omcli_fail "ncdu does not accept arguments" || return
  omcli_has_ncdu || omcli_fail "ncdu is required" || return
  omcli_started="$(omcli_epoch)"
  omcli_output="$HOME/.ncdu.$omcli_started"
  omcli_threads="$(omcli_ncdu_threads)"
  [ ! -e "$omcli_output" ] || omcli_fail "snapshot already exists: $omcli_output" || return
  omcli_run ncdu -0 -x -t "$omcli_threads" -O "$omcli_output" / \
    --exclude System --exclude Volumes --exclude "$HOME/.Trash" || {
      omcli_status=$?
      /bin/rm -f "$omcli_output"
      return "$omcli_status"
    }
  omcli_finished="$(omcli_epoch)"
  printf 'snapshot: %s\n' "$omcli_output"
  printf 'expect:90s, actual: %ss\n' "$((omcli_finished - omcli_started))"
}

omcli_ncdu_latest_snapshot() {
  omcli_latest_path=""
  omcli_latest_epoch=""
  omcli_snapshot_prefix="$HOME/.ncdu."

  for omcli_candidate in "$HOME"/.ncdu.*; do
    [ -f "$omcli_candidate" ] || continue
    omcli_candidate_epoch="${omcli_candidate#"$omcli_snapshot_prefix"}"
    case "$omcli_candidate_epoch" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ -z "$omcli_latest_epoch" ] || [ "$omcli_candidate_epoch" -gt "$omcli_latest_epoch" ]; then
      omcli_latest_epoch="$omcli_candidate_epoch"
      omcli_latest_path="$omcli_candidate"
    fi
  done

  [ -n "$omcli_latest_path" ] || omcli_fail "no ncdu snapshots found in $HOME" || return
  printf '%s\n' "$omcli_latest_path"
}

omcli_ncdu_read() {
  [ "$#" -le 1 ] || omcli_fail "ncdu read accepts at most one file" || return
  omcli_has_ncdu || omcli_fail "ncdu is required" || return

  if [ "$#" -eq 1 ]; then
    omcli_input="$1"
  else
    omcli_input="$(omcli_ncdu_latest_snapshot)" || return
  fi

  [ -f "$omcli_input" ] || omcli_fail "snapshot is not a file: $omcli_input" || return
  [ -r "$omcli_input" ] || omcli_fail "snapshot is not readable: $omcli_input" || return
  omcli_external ncdu -f "$omcli_input" --show-itemcount --show-percent
}

omcli_ncdu() {
  omcli_ncdu_command="${1:-help}"
  if [ "$#" -gt 0 ]; then shift; fi
  case "$omcli_ncdu_command" in
    help|-h|--help)
      [ "$#" -eq 0 ] || omcli_fail "ncdu help does not accept arguments" || return
      omcli_ncdu_usage
      ;;
    dump) omcli_ncdu_dump "$@" ;;
    read) omcli_ncdu_read "$@" ;;
    *) omcli_ncdu_usage >&2; omcli_fail "unknown ncdu command: $omcli_ncdu_command" ;;
  esac
}

omcli_thread_writer_lock_pids() {
  omcli_lock_dir="$HOME/.codex/thread-writer-locks"
  [ -d "$omcli_lock_dir" ] || return 0
  /usr/sbin/lsof -t +D "$omcli_lock_dir" 2>/dev/null | /usr/bin/sort -nu
}

omcli_xcodex() {
  [ "$#" -eq 0 ] || omcli_fail "xcodex does not accept arguments" || return

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

omcli_main() {
  omcli_command="${1:-help}"
  if [ "$#" -gt 0 ]; then shift; fi
  case "$omcli_command" in
    help|-h|--help)
      [ "$#" -eq 0 ] || omcli_fail "help does not accept arguments" || return
      omcli_usage
      ;;
    version|-v|--version)
      [ "$#" -eq 0 ] || omcli_fail "version does not accept arguments" || return
      printf 'omcli %s\n' "$OMCLI_VERSION"
      ;;
    lockscreen) omcli_lockscreen "$@" ;;
    ncdu) omcli_ncdu "$@" ;;
    sidecar) omcli_sidecar "$@" ;;
    xcodex) omcli_xcodex "$@" ;;
    *) omcli_usage >&2; omcli_fail "unknown command: $omcli_command" ;;
  esac
}

if [ "${OMCLI_SOURCE_ONLY:-0}" != "1" ]; then
  omcli_main "$@"
fi
