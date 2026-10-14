#!/bin/sh

OMCLI_VERSION="@VERSION@"

omcli_usage() {
  cat <<'EOF'
Usage: omcli <command> [arguments]

Commands:
  lockscreen [command]   Lock the screen and confirm the lock took effect
  ncdu [command]         Create or read ncdu snapshots
  sidecar [command]      Connect or disconnect an iPad with Sidecar
  iphone [command]       Connect to an iPhone SSH server over USB
  codex                  Terminate processes holding Codex thread-writer locks
  help                   Show this help

Options:
  -h, --help             Show this help
  -v, --version          Show the installed version

Run "omcli ncdu help" for ncdu snapshot commands.
Run "omcli sidecar help" for Sidecar commands.
Run "omcli iphone help" for iPhone USB commands.
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

omcli_ncdu_timestamp() {
  /bin/date '+%Y%m%d-%H%M%S'
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

Create, read, list, and prune ncdu snapshots.
Running without a command displays this help and does not scan the disk.

Commands:
  dump [DIRECTORY]       Scan DIRECTORY, or the startup volume when omitted
  read [SNAPSHOT|DIRECTORY]
                         Open a snapshot, a directory's latest, or the latest overall
  list                   List managed snapshots, newest first
  prune [--keep N] [--dry-run]
                         Keep the latest N snapshots per target (default: 3)
  help                   Show this help

Options:
  -h, --help             Show this help
EOF
}

omcli_ncdu_state_dir() {
  omcli_state_base="${XDG_STATE_HOME:-$HOME/.local/state}"
  case "$omcli_state_base" in
    /*) ;;
    *) omcli_state_base="$HOME/.local/state" ;;
  esac
  printf '%s/omcli/ncdu\n' "$omcli_state_base"
}

omcli_ncdu_canonical_directory() {
  [ -d "$1" ] || omcli_fail "scan target is not a directory: $1" || return
  [ -r "$1" ] || omcli_fail "scan target is not readable: $1" || return
  (CDPATH='' cd -- "$1" 2>/dev/null && pwd -P) || \
    omcli_fail "cannot resolve scan target: $1"
}

omcli_ncdu_target_label() {
  if [ "$1" = / ]; then
    printf 'root\n'
    return
  fi
  omcli_target_label="$(basename -- "$1" | /usr/bin/tr -cs 'A-Za-z0-9._-' '_')"
  omcli_target_label="$(printf '%s' "$omcli_target_label" | /usr/bin/cut -c 1-40)"
  [ -n "$omcli_target_label" ] || omcli_target_label=target
  printf '%s\n' "$omcli_target_label"
}

omcli_ncdu_target_dir() {
  omcli_target_label="$(omcli_ncdu_target_label "$1")" || return
  omcli_target_hash="$(printf '%s' "$1" | /usr/bin/shasum -a 256 | /usr/bin/cut -c 1-8)" || return
  printf '%s/%s-%s\n' "$(omcli_ncdu_state_dir)" "$omcli_target_label" "$omcli_target_hash"
}

omcli_ncdu_prepare_target_dir() {
  omcli_prepare_dir="$1"
  omcli_prepare_target="$2"
  /bin/mkdir -p "$omcli_prepare_dir" || omcli_fail "cannot create snapshot directory: $omcli_prepare_dir" || return
  /bin/chmod 700 "$omcli_prepare_dir" 2>/dev/null || :

  if [ -f "$omcli_prepare_dir/target" ]; then
    omcli_recorded_target="$(/bin/cat "$omcli_prepare_dir/target")" || return
    [ "$omcli_recorded_target" = "$omcli_prepare_target" ] || \
      omcli_fail "snapshot target hash collision: $omcli_prepare_dir" || return
  else
    printf '%s\n' "$omcli_prepare_target" > "$omcli_prepare_dir/.target.$$" || return
    /bin/mv -f "$omcli_prepare_dir/.target.$$" "$omcli_prepare_dir/target" || return
  fi
}

omcli_ncdu_snapshot_valid() {
  [ -f "$1" ] || return 1
  basename -- "$1" | /usr/bin/grep -Eq '^[0-9]{8}-[0-9]{6}-[0-9]{3}\.ncdu$'
}

omcli_ncdu_dump() (
  [ "$#" -le 1 ] || omcli_fail "ncdu dump accepts at most one directory" || return
  omcli_has_ncdu || omcli_fail "ncdu is required" || return
  umask 077

  omcli_requested_target="${1:-/}"
  omcli_target="$(omcli_ncdu_canonical_directory "$omcli_requested_target")" || return
  omcli_target_dir="$(omcli_ncdu_target_dir "$omcli_target")" || return
  omcli_ncdu_prepare_target_dir "$omcli_target_dir" "$omcli_target" || return

  omcli_started="$(omcli_epoch)"
  omcli_timestamp="$(omcli_ncdu_timestamp)"
  omcli_sequence=1
  while [ "$omcli_sequence" -le 999 ]; do
    omcli_suffix="$(printf '%03d' "$omcli_sequence")"
    omcli_output="$omcli_target_dir/$omcli_timestamp-$omcli_suffix.ncdu"
    [ -e "$omcli_output" ] || break
    omcli_sequence=$((omcli_sequence + 1))
  done
  [ "$omcli_sequence" -le 999 ] || omcli_fail "too many snapshots created in the same second" || return

  omcli_partial="$omcli_target_dir/.$omcli_timestamp-$omcli_suffix.ncdu.partial.$$"
  trap '[ -n "${omcli_partial:-}" ] && /bin/rm -f "$omcli_partial"' 0 1 2 15
  omcli_threads="$(omcli_ncdu_threads)"

  if [ "$omcli_target" = / ]; then
    omcli_run ncdu -0 -x -t "$omcli_threads" -O "$omcli_partial" \
      --exclude System --exclude Volumes --exclude "$HOME/.Trash" -- "$omcli_target"
  else
    omcli_run ncdu -0 -x -t "$omcli_threads" -O "$omcli_partial" -- "$omcli_target"
  fi || {
      omcli_status=$?
      return "$omcli_status"
    }

  /bin/mv "$omcli_partial" "$omcli_output" || return
  omcli_partial=''
  omcli_finished="$(omcli_epoch)"
  printf 'target: %s\n' "$omcli_target"
  printf 'snapshot: %s\n' "$omcli_output"
  printf 'actual: %ss\n' "$((omcli_finished - omcli_started))"
)

omcli_ncdu_consider_snapshot_dir() {
  omcli_snapshot_dir="$1"
  [ -d "$omcli_snapshot_dir" ] || return 0
  [ -f "$omcli_snapshot_dir/target" ] || return 0
  for omcli_candidate in "$omcli_snapshot_dir"/*.ncdu; do
    omcli_ncdu_snapshot_valid "$omcli_candidate" || continue
    omcli_candidate_key="$(basename -- "$omcli_candidate" .ncdu | /usr/bin/tr -d '-')"
    if [ -z "$omcli_latest_key" ] || [ "$omcli_candidate_key" -gt "$omcli_latest_key" ]; then
      omcli_latest_key="$omcli_candidate_key"
      omcli_latest_path="$omcli_candidate"
    fi
  done
}

omcli_ncdu_latest_snapshot() (
  LC_ALL=C
  export LC_ALL
  omcli_latest_path=""
  omcli_latest_key=""
  omcli_state_dir="$(omcli_ncdu_state_dir)"

  if [ "$#" -eq 1 ]; then
    omcli_ncdu_consider_snapshot_dir "$1"
  else
    for omcli_snapshot_dir in "$omcli_state_dir"/*; do
      omcli_ncdu_consider_snapshot_dir "$omcli_snapshot_dir"
    done
  fi
  [ -n "$omcli_latest_path" ] || omcli_fail "no managed ncdu snapshots found" || return
  printf '%s\n' "$omcli_latest_path"
)

omcli_ncdu_read() {
  [ "$#" -le 1 ] || omcli_fail "ncdu read accepts at most one file" || return
  omcli_has_ncdu || omcli_fail "ncdu is required" || return

  if [ "$#" -eq 0 ]; then
    omcli_input="$(omcli_ncdu_latest_snapshot)" || return
  elif [ -f "$1" ]; then
    omcli_input="$1"
  elif [ -d "$1" ]; then
    omcli_target="$(omcli_ncdu_canonical_directory "$1")" || return
    omcli_target_dir="$(omcli_ncdu_target_dir "$omcli_target")" || return
    omcli_input="$(omcli_ncdu_latest_snapshot "$omcli_target_dir")" || return
  else
    omcli_fail "not a snapshot file or directory: $1" || return
  fi

  [ -f "$omcli_input" ] || omcli_fail "snapshot is not a file: $omcli_input" || return
  [ -r "$omcli_input" ] || omcli_fail "snapshot is not readable: $omcli_input" || return
  omcli_external ncdu -f "$omcli_input" --show-itemcount --show-percent
}

omcli_ncdu_created_display() {
  omcli_created="$(basename -- "$1" .ncdu)"
  printf '%s-%s-%s %s:%s:%s\n' \
    "$(printf '%s' "$omcli_created" | /usr/bin/cut -c 1-4)" \
    "$(printf '%s' "$omcli_created" | /usr/bin/cut -c 5-6)" \
    "$(printf '%s' "$omcli_created" | /usr/bin/cut -c 7-8)" \
    "$(printf '%s' "$omcli_created" | /usr/bin/cut -c 10-11)" \
    "$(printf '%s' "$omcli_created" | /usr/bin/cut -c 12-13)" \
    "$(printf '%s' "$omcli_created" | /usr/bin/cut -c 14-15)"
}

omcli_ncdu_list() (
  [ "$#" -eq 0 ] || omcli_fail "ncdu list does not accept arguments" || return
  omcli_state_dir="$(omcli_ncdu_state_dir)"
  omcli_rows="${TMPDIR:-/tmp}/omcli-ncdu-list.$$"
  trap '/bin/rm -f "$omcli_rows"' 0 1 2 15
  : > "$omcli_rows" || return

  for omcli_snapshot_dir in "$omcli_state_dir"/*; do
    [ -d "$omcli_snapshot_dir" ] || continue
    [ -f "$omcli_snapshot_dir/target" ] || continue
    omcli_target="$(/bin/cat "$omcli_snapshot_dir/target")" || continue
    for omcli_candidate in "$omcli_snapshot_dir"/*.ncdu; do
      omcli_ncdu_snapshot_valid "$omcli_candidate" || continue
      omcli_key="$(basename -- "$omcli_candidate" .ncdu)"
      omcli_created="$(omcli_ncdu_created_display "$omcli_candidate")"
      omcli_size="$(/usr/bin/du -h "$omcli_candidate" | /usr/bin/awk '{print $1}')"
      printf '%s\t%s\t%s\t%s\t%s\n' "$omcli_key" "$omcli_created" "$omcli_size" "$omcli_target" "$omcli_candidate" >> "$omcli_rows"
    done
  done

  if [ ! -s "$omcli_rows" ]; then
    printf 'no managed ncdu snapshots found in %s\n' "$omcli_state_dir"
    return
  fi

  printf 'CREATED\tSIZE\tTARGET\tSNAPSHOT\n'
  LC_ALL=C /usr/bin/sort -r "$omcli_rows" | while IFS="$(printf '\t')" read -r omcli_key omcli_created omcli_size omcli_target omcli_candidate; do
    printf '%s\t%s\t%s\t%s\n' "$omcli_created" "$omcli_size" "$omcli_target" "$omcli_candidate"
  done
)

omcli_ncdu_prune() (
  LC_ALL=C
  export LC_ALL
  omcli_keep=3
  omcli_dry_run=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --keep)
        shift
        [ "$#" -gt 0 ] || omcli_fail "ncdu prune --keep requires a number" || return
        omcli_keep="$1"
        ;;
      --dry-run) omcli_dry_run=1 ;;
      *) omcli_fail "unknown ncdu prune argument: $1" || return ;;
    esac
    shift
  done
  case "$omcli_keep" in
    ''|*[!0-9]*) omcli_fail "ncdu prune --keep must be a positive integer" || return ;;
  esac
  omcli_keep="$(printf '%s' "$omcli_keep" | /usr/bin/sed 's/^0*//')"
  [ -n "$omcli_keep" ] || omcli_fail "ncdu prune --keep must be a positive integer" || return

  omcli_state_dir="$(omcli_ncdu_state_dir)"
  omcli_removed=0
  for omcli_snapshot_dir in "$omcli_state_dir"/*; do
    [ -d "$omcli_snapshot_dir" ] || continue
    [ -f "$omcli_snapshot_dir/target" ] || continue
    omcli_count=0
    for omcli_candidate in "$omcli_snapshot_dir"/*.ncdu; do
      omcli_ncdu_snapshot_valid "$omcli_candidate" || continue
      omcli_count=$((omcli_count + 1))
    done
    omcli_remove_count=$((omcli_count - omcli_keep))
    [ "$omcli_remove_count" -gt 0 ] || continue

    for omcli_candidate in "$omcli_snapshot_dir"/*.ncdu; do
      omcli_ncdu_snapshot_valid "$omcli_candidate" || continue
      [ "$omcli_remove_count" -gt 0 ] || break
      if [ "$omcli_dry_run" -eq 1 ]; then
        printf 'would remove: %s\n' "$omcli_candidate"
      else
        /bin/rm -f "$omcli_candidate" || return
        printf 'removed: %s\n' "$omcli_candidate"
      fi
      omcli_removed=$((omcli_removed + 1))
      omcli_remove_count=$((omcli_remove_count - 1))
    done
  done

  if [ "$omcli_dry_run" -eq 1 ]; then
    printf 'would remove %s snapshot(s); keep latest %s per target\n' "$omcli_removed" "$omcli_keep"
  else
    printf 'removed %s snapshot(s); kept latest %s per target\n' "$omcli_removed" "$omcli_keep"
  fi
)

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
    list) omcli_ncdu_list "$@" ;;
    prune) omcli_ncdu_prune "$@" ;;
    *) omcli_ncdu_usage >&2; omcli_fail "unknown ncdu command: $omcli_ncdu_command" ;;
  esac
}

omcli_iphone_usage() {
  cat <<'EOF'
Usage: omcli iphone ssh [COMMAND [ARGUMENT...]]

Connect to the SSH server on a USB-connected iPhone. The command creates a
temporary localhost:2222 -> iPhone:22 tunnel, runs ssh iphone.jb, and removes
the tunnel when SSH exits.

Commands:
  ssh [COMMAND...]       Open an interactive shell or run a remote command
  help                   Show this help

Options:
  -h, --help             Show this help
EOF
}

omcli_iphone_iproxy_path() {
  command -v iproxy 2>/dev/null
}

omcli_iphone_ssh_path() {
  command -v ssh 2>/dev/null
}

omcli_iphone_port_ready() {
  /usr/bin/nc -z 127.0.0.1 2222 >/dev/null 2>&1
}

omcli_iphone_cleanup() {
  if [ -n "${omcli_iphone_proxy_pid:-}" ]; then
    /bin/kill -TERM "$omcli_iphone_proxy_pid" >/dev/null 2>&1 || :
    wait "$omcli_iphone_proxy_pid" 2>/dev/null || :
  fi
  [ -n "${omcli_iphone_log:-}" ] && /bin/rm -f "$omcli_iphone_log" 2>/dev/null || :
  omcli_iphone_proxy_pid=''
  omcli_iphone_log=''
}

omcli_iphone_ssh() (
  omcli_iphone_iproxy="$(omcli_iphone_iproxy_path)" || \
    omcli_fail "iproxy is required; install libusbmuxd" || return
  [ -x "$omcli_iphone_iproxy" ] || \
    omcli_fail "iproxy is not executable: $omcli_iphone_iproxy" || return
  omcli_iphone_ssh_binary="$(omcli_iphone_ssh_path)" || \
    omcli_fail "ssh is required" || return
  [ -x "$omcli_iphone_ssh_binary" ] || \
    omcli_fail "ssh is not executable: $omcli_iphone_ssh_binary" || return

  if omcli_iphone_port_ready; then
    omcli_fail "local port 2222 is already in use" || return
  fi

  omcli_iphone_log="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/omcli-iphone-iproxy.XXXXXX")" || \
    omcli_fail "cannot create the iproxy log" || return
  omcli_iphone_proxy_pid=''
  trap 'omcli_iphone_cleanup' EXIT
  trap 'omcli_iphone_cleanup; exit 130' HUP INT TERM

  "$omcli_iphone_iproxy" 2222:22 >"$omcli_iphone_log" 2>&1 &
  omcli_iphone_proxy_pid=$!
  omcli_iphone_wait_count=0
  while [ "$omcli_iphone_wait_count" -lt 60 ]; do
    omcli_iphone_port_ready && break
    if ! /bin/kill -0 "$omcli_iphone_proxy_pid" 2>/dev/null; then
      [ ! -s "$omcli_iphone_log" ] || /bin/cat "$omcli_iphone_log" >&2
      omcli_fail "iproxy exited before localhost:2222 became available" || return
    fi
    /bin/sleep 0.05
    omcli_iphone_wait_count=$((omcli_iphone_wait_count + 1))
  done
  omcli_iphone_port_ready || \
    omcli_fail "timed out waiting for localhost:2222 -> iPhone:22" || return

  printf 'USB SSH tunnel: localhost:2222 -> iPhone:22\n'
  "$omcli_iphone_ssh_binary" iphone.jb "$@"
  omcli_iphone_ssh_status=$?
  omcli_iphone_cleanup
  trap - EXIT HUP INT TERM
  return "$omcli_iphone_ssh_status"
)

omcli_iphone() {
  omcli_iphone_command="${1:-help}"
  if [ "$#" -gt 0 ]; then shift; fi
  case "$omcli_iphone_command" in
    help|-h|--help)
      [ "$#" -eq 0 ] || omcli_fail "iphone help does not accept arguments" || return
      omcli_iphone_usage
      ;;
    ssh) omcli_iphone_ssh "$@" ;;
    *) omcli_iphone_usage >&2; omcli_fail "unknown iphone command: $omcli_iphone_command" ;;
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
    iphone) omcli_iphone "$@" ;;
    codex) omcli_codex "$@" ;;
    *) omcli_usage >&2; omcli_fail "unknown command: $omcli_command" ;;
  esac
}

if [ "${OMCLI_SOURCE_ONLY:-0}" != "1" ]; then
  omcli_main "$@"
fi
