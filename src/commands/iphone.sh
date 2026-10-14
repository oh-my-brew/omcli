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

