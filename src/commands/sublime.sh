omcli_sublime_path() {
  omcli_self="$(omcli_resolve_self "$0")" || omcli_fail "cannot resolve executable path" || return
  omcli_bin_dir="$(dirname -- "$omcli_self")"
  printf '%s/../libexec/omcli-sublime.app/Contents/MacOS/omcli-sublime\n' "$omcli_bin_dir"
}

omcli_sublime_usage() {
  cat <<'EOF'
Usage: omcli sublime setup

Commands:
  setup                  Ask macOS to use Sublime Text for plain-text files
  help                   Show this help

The setup command changes the parent public.plain-text association once. macOS
may require interactive consent. The command waits up to 180 seconds and then
verifies the effective default application.
EOF
}

omcli_sublime() {
  omcli_sublime_command="${1:-help}"
  if [ "$#" -gt 0 ]; then shift; fi
  case "$omcli_sublime_command" in
    help|-h|--help)
      [ "$#" -eq 0 ] || omcli_fail "sublime help does not accept arguments" || return
      omcli_sublime_usage
      ;;
    setup)
      [ "$#" -eq 0 ] || omcli_fail "sublime setup does not accept arguments" || return
      omcli_helper="$(omcli_sublime_path)" || return
      omcli_helper_is_executable "$omcli_helper" || omcli_fail "Sublime setup helper is not installed" || return
      omcli_external "$omcli_helper" setup
      ;;
    *) omcli_sublime_usage >&2; omcli_fail "unknown sublime command: $omcli_sublime_command" ;;
  esac
}
