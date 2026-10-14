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

