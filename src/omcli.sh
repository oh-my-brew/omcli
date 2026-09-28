#!/bin/sh

OMCLI_VERSION="@VERSION@"

omcli_usage() {
  cat <<'EOF'
Usage: omcli <command> [arguments]

Commands:
  lockscreen [command]   Lock the screen and confirm the lock took effect
  ncdu [command]         Create or read ncdu snapshots
  sidecar [command]      Connect or disconnect an iPad with Sidecar
  codex                  Terminate processes holding Codex thread-writer locks
  help                   Show this help

Options:
  -h, --help             Show this help
  -v, --version          Show the installed version

Run "omcli ncdu help" for ncdu snapshot commands.
Run "omcli sidecar help" for Sidecar commands.
Run "omcli lockscreen help" for lock screen commands.
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

omcli_lockscreen_usage() {
  cat <<'EOF'
Usage: omcli lockscreen [--method METHOD]
       omcli lockscreen lock [--method METHOD]
       omcli lockscreen status
       omcli lockscreen doctor

Commands:
  lock                   Lock the screen and confirm the lock took effect (default)
  status                 Report whether the screen is currently locked
  doctor                 Report lock-screen capabilities without changing state
  help                   Show this help

Methods:
  auto                   Select direct or agent, then use display-sleep as fallback
  direct                 Call the login framework in the current session
  agent                  Call direct from a temporary GUI LaunchAgent
  display-sleep          Put the display to sleep
  hotkey                 Post Control-Command-Q (requires Accessibility permission)

Exit status: 0 locked, 1 not locked, 2 usage error, 3 lock unavailable.
EOF
}

omcli_lockscreen_manager() {
  /bin/launchctl managername 2>/dev/null || printf 'unknown\n'
}

omcli_lockscreen_console_uid() {
  /usr/bin/stat -f '%u' /dev/console 2>/dev/null
}

omcli_lockscreen_console_user() {
  /usr/bin/stat -f '%Su' /dev/console 2>/dev/null
}

omcli_lockscreen_is_locked() {
  "$1" status >/dev/null 2>&1
}

omcli_lockscreen_wait() {
  omcli_wait_helper="$1"
  omcli_wait_count=0
  while [ "$omcli_wait_count" -lt 60 ]; do
    omcli_lockscreen_is_locked "$omcli_wait_helper" && return 0
    /bin/sleep 0.05
    omcli_wait_count=$((omcli_wait_count + 1))
  done
  return 1
}

omcli_lockscreen_agent_cleanup() {
  [ -n "${omcli_agent_target:-}" ] && /bin/launchctl bootout "$omcli_agent_target" >/dev/null 2>&1 || :
  [ -n "${omcli_agent_dir:-}" ] && /bin/rm -f "$omcli_agent_dir/agent.plist" "$omcli_agent_dir/run.sh" "$omcli_agent_dir/result" "$omcli_agent_dir/stdout" "$omcli_agent_dir/stderr" 2>/dev/null || :
  [ -n "${omcli_agent_dir:-}" ] && /bin/rmdir "$omcli_agent_dir" 2>/dev/null || :
  [ -n "${omcli_agent_lock:-}" ] && /bin/rm -f "$omcli_agent_lock/pid" 2>/dev/null || :
  [ -n "${omcli_agent_lock:-}" ] && /bin/rmdir "$omcli_agent_lock" 2>/dev/null || :
  omcli_agent_target=''
  omcli_agent_dir=''
  omcli_agent_lock=''
}

omcli_lockscreen_agent_run() (
  omcli_agent_helper="$1"
  omcli_agent_method="$2"
  omcli_agent_uid="$(omcli_lockscreen_console_uid)" || return 3
  omcli_agent_user="$(omcli_lockscreen_console_user)" || return 3
  case "$omcli_agent_uid" in
    ''|*[!0-9]*|0) omcli_fail "no logged-in GUI user is available"; return 3 ;;
  esac
  case "$omcli_agent_user" in
    ''|root|loginwindow|_mbsetupuser)
      omcli_fail "no logged-in GUI user is available"; return 3 ;;
  esac

  omcli_agent_label="com.oh-my-brew.omcli.lockscreen.transient"
  omcli_agent_domain="gui/$omcli_agent_uid"
  omcli_agent_target="$omcli_agent_domain/$omcli_agent_label"
  omcli_agent_lock="${TMPDIR:-/tmp}/omcli-lockscreen-agent-$omcli_agent_uid.lock"

  if ! /bin/mkdir "$omcli_agent_lock" 2>/dev/null; then
    omcli_agent_owner=''
    [ -f "$omcli_agent_lock/pid" ] && read -r omcli_agent_owner < "$omcli_agent_lock/pid"
    case "$omcli_agent_owner" in
      ''|*[!0-9]*) omcli_agent_owner='' ;;
    esac
    if [ -z "$omcli_agent_owner" ] || ! /bin/kill -0 "$omcli_agent_owner" 2>/dev/null; then
      /bin/rm -f "$omcli_agent_lock/pid" 2>/dev/null || :
      /bin/rmdir "$omcli_agent_lock" 2>/dev/null || :
      /bin/mkdir "$omcli_agent_lock" 2>/dev/null || {
        omcli_fail "cannot recover a stale lockscreen agent lock" || return 3
      }
    else
      omcli_fail "another lockscreen agent request is already running" || return 3
    fi
  fi
  printf '%s\n' "$$" > "$omcli_agent_lock/pid"

  omcli_agent_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omcli-lockscreen-agent.XXXXXX")" || {
    omcli_lockscreen_agent_cleanup
    return 3
  }
  /bin/chmod 700 "$omcli_agent_dir"
  trap 'omcli_lockscreen_agent_cleanup' EXIT
  trap 'omcli_lockscreen_agent_cleanup; exit 130' HUP INT TERM

  case "$omcli_agent_helper" in
    *"'"*) omcli_fail "lockscreen helper path contains an unsupported quote"; omcli_lockscreen_agent_cleanup; return 3 ;;
  esac

  {
    printf '%s\n' '#!/bin/sh'
    printf "'%s' '%s' > '%s/stdout' 2> '%s/stderr'\n" "$omcli_agent_helper" "$omcli_agent_method" "$omcli_agent_dir" "$omcli_agent_dir"
    printf '%s\n' 'omcli_agent_code=$?'
    printf "printf '%%s\\n' \"\$omcli_agent_code\" > '%s/result'\n" "$omcli_agent_dir"
    printf '%s\n' "exit \"\$omcli_agent_code\""
  } > "$omcli_agent_dir/run.sh"
  /bin/chmod 700 "$omcli_agent_dir/run.sh"

  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '<key>Label</key><string>%s</string>\n' "$omcli_agent_label"
    printf '<key>ProgramArguments</key><array><string>%s/run.sh</string></array>\n' "$omcli_agent_dir"
    printf '%s\n' '<key>RunAtLoad</key><false/>'
    printf '%s\n' '</dict></plist>'
  } > "$omcli_agent_dir/agent.plist"

  /bin/launchctl bootout "$omcli_agent_target" >/dev/null 2>&1 || :
  if ! /bin/launchctl bootstrap "$omcli_agent_domain" "$omcli_agent_dir/agent.plist"; then
    omcli_fail "cannot bootstrap a temporary agent in $omcli_agent_domain"
    omcli_lockscreen_agent_cleanup
    return 3
  fi
  if ! /bin/launchctl kickstart "$omcli_agent_target"; then
    omcli_fail "cannot start the temporary lockscreen agent"
    omcli_lockscreen_agent_cleanup
    return 3
  fi

  omcli_agent_count=0
  while [ ! -f "$omcli_agent_dir/result" ] && [ "$omcli_agent_count" -lt 40 ]; do
    /bin/sleep 0.05
    omcli_agent_count=$((omcli_agent_count + 1))
  done
  omcli_agent_code=3
  [ -f "$omcli_agent_dir/result" ] && read -r omcli_agent_code < "$omcli_agent_dir/result"
  [ -s "$omcli_agent_dir/stdout" ] && /bin/cat "$omcli_agent_dir/stdout"
  [ -s "$omcli_agent_dir/stderr" ] && /bin/cat "$omcli_agent_dir/stderr" >&2
  omcli_lockscreen_agent_cleanup
  trap - EXIT HUP INT TERM
  case "$omcli_agent_code" in
    0|1|2|3) return "$omcli_agent_code" ;;
    *) return 3 ;;
  esac
)

omcli_lockscreen_screen_lock_immediate() {
  /usr/sbin/sysadminctl -screenLock status 2>&1 | /usr/bin/grep -F 'delay is immediate' >/dev/null
}

omcli_lockscreen_try_method() {
  omcli_method_helper="$1"
  omcli_method_name="$2"
  case "$omcli_method_name" in
    direct)
      "$omcli_method_helper" direct || return $?
      ;;
    agent)
      omcli_lockscreen_agent_run "$omcli_method_helper" direct || return $?
      ;;
    hotkey)
      if [ "$(omcli_lockscreen_manager)" = Aqua ]; then
        "$omcli_method_helper" hotkey || return $?
      else
        omcli_lockscreen_agent_run "$omcli_method_helper" hotkey || return $?
      fi
      ;;
    display-sleep)
      omcli_lockscreen_screen_lock_immediate || {
        omcli_fail "display-sleep requires an immediate screen-lock delay" || return 3
      }
      /usr/bin/pmset displaysleepnow || return 3
      ;;
    *) return 2 ;;
  esac

  if omcli_lockscreen_wait "$omcli_method_helper"; then
    printf 'screen locked (method=%s)\n' "$omcli_method_name"
    return 0
  fi
  omcli_fail "$omcli_method_name completed but the screen did not lock within 3 seconds" || return 1
}

omcli_lockscreen_auto() {
  omcli_auto_helper="$1"
  if [ "$(omcli_lockscreen_manager)" = Aqua ]; then
    omcli_auto_first=direct
  else
    omcli_auto_first=agent
  fi

  omcli_lockscreen_try_method "$omcli_auto_helper" "$omcli_auto_first" && return 0
  if omcli_lockscreen_screen_lock_immediate; then
    omcli_lockscreen_try_method "$omcli_auto_helper" display-sleep && return 0
  fi
  omcli_fail "all automatic lock methods failed" || return 1
}

omcli_lockscreen_doctor() {
  omcli_doctor_helper="$1"
  omcli_doctor_state="$("$omcli_doctor_helper" status 2>/dev/null || :)"
  case "$omcli_doctor_state" in
    locked|unlocked) ;;
    *) omcli_doctor_state=unknown ;;
  esac
  omcli_doctor_manager="$(omcli_lockscreen_manager)"
  omcli_doctor_uid="$(omcli_lockscreen_console_uid 2>/dev/null || printf 'unknown\n')"
  omcli_doctor_user="$(omcli_lockscreen_console_user 2>/dev/null || printf 'unknown\n')"
  printf 'state=%s\n' "$omcli_doctor_state"
  printf 'session=%s\n' "$omcli_doctor_manager"
  printf 'console_user=%s\n' "$omcli_doctor_user"
  printf 'console_uid=%s\n' "$omcli_doctor_uid"
  if /bin/launchctl print "gui/$omcli_doctor_uid" >/dev/null 2>&1; then
    printf 'gui_domain=available\n'
  else
    printf 'gui_domain=unavailable\n'
  fi
  if omcli_lockscreen_screen_lock_immediate; then
    printf 'screen_lock_delay=immediate\n'
  else
    printf 'screen_lock_delay=not-immediate-or-unknown\n'
  fi
  if [ -x /usr/bin/pmset ]; then
    printf 'display-sleep=available\n'
  else
    printf 'display-sleep=unavailable\n'
  fi
  "$omcli_doctor_helper" capabilities
}

omcli_lockscreen() {
  omcli_lockscreen_command="${1:-lock}"
  case "$omcli_lockscreen_command" in
    --method) omcli_lockscreen_command=lock ;;
    *) if [ "$#" -gt 0 ]; then shift; fi ;;
  esac

  case "$omcli_lockscreen_command" in
    lock)
      omcli_lockscreen_method=auto
      if [ "$#" -gt 0 ]; then
        [ "$1" = --method ] || omcli_fail "lockscreen lock expects --method METHOD" || return 2
        [ "$#" -eq 2 ] || omcli_fail "lockscreen lock expects exactly one method" || return 2
        omcli_lockscreen_method="$2"
      fi
      case "$omcli_lockscreen_method" in
        auto|direct|agent|display-sleep|hotkey) ;;
        *) omcli_fail "unknown lockscreen method: $omcli_lockscreen_method" || return 2 ;;
      esac
      ;;
    status)
      [ "$#" -eq 0 ] || omcli_fail "lockscreen status does not accept arguments" || return
      ;;
    doctor)
      [ "$#" -eq 0 ] || omcli_fail "lockscreen doctor does not accept arguments" || return
      ;;
    help|-h|--help)
      [ "$#" -eq 0 ] || omcli_fail "lockscreen help does not accept arguments" || return
      omcli_lockscreen_usage
      return 0 ;;
    *)
      omcli_lockscreen_usage >&2
      omcli_fail "unknown lockscreen command: $omcli_lockscreen_command" || return ;;
  esac

  omcli_helper="$(omcli_lockscreen_path)" || return
  omcli_helper_is_executable "$omcli_helper" || omcli_fail "lockscreen helper is not installed" || return
  case "$omcli_lockscreen_command" in
    status) omcli_external "$omcli_helper" status ;;
    doctor) omcli_lockscreen_doctor "$omcli_helper" ;;
    lock)
      if omcli_lockscreen_is_locked "$omcli_helper"; then
        printf 'screen is already locked\n'
        return 0
      else
        omcli_lockscreen_state_code=$?
        [ "$omcli_lockscreen_state_code" -eq 1 ] || {
          omcli_fail "cannot determine the current lock-screen state" || return 3
        }
      fi
      if [ "$omcli_lockscreen_method" = auto ]; then
        omcli_lockscreen_auto "$omcli_helper"
      else
        omcli_lockscreen_try_method "$omcli_helper" "$omcli_lockscreen_method"
      fi
      ;;
  esac
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

omcli_codex() {
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
    codex) omcli_codex "$@" ;;
    *) omcli_usage >&2; omcli_fail "unknown command: $omcli_command" ;;
  esac
}

if [ "${OMCLI_SOURCE_ONLY:-0}" != "1" ]; then
  omcli_main "$@"
fi
