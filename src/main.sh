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
