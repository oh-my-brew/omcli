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

