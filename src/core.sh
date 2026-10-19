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
  codex [command]        Recover from Codex thread-writer lock conflicts
  update [--check]       Check for or install the latest stable release
  update --beta          Install the latest published beta candidate
  update --reset         Remove the user-level update override
  help                   Show this help

Options:
  -h, --help             Show this help
  -v, --version          Show the installed version

Run "omcli ncdu help" for ncdu snapshot commands.
Run "omcli sidecar help" for Sidecar commands.
Run "omcli iphone help" for iPhone USB commands.
Run "omcli codex help" for Codex recovery commands.
Run "omcli update --help" for self-update commands.
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
