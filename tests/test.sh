#!/bin/sh

set -eu

REPOSITORY_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPOSITORY_DIR"

# Only parse source and built scripts. The functional subcommands are never run.
sh -n src/omcli.sh
sh -n bin/omcli

expected_version="$(tr -d '\n' < VERSION)"
[ "$expected_version" = "2026.09.25.2" ]
grep -F 'OMCLI_VERSION="@VERSION@"' src/omcli.sh >/dev/null
if grep -F '@VERSION@' bin/omcli >/dev/null; then
  echo "unexpanded version placeholder" >&2
  exit 1
fi

# Source-only mode prevents dispatch. All external execution is replaced before
# any router behavior is exercised, so this test cannot reach the real helpers.
OMCLI_SOURCE_ONLY=1
export OMCLI_SOURCE_ONLY
. ./bin/omcli

[ "$(omcli_main --version)" = "omcli $expected_version" ]
help_output="$(omcli_main)"
for command_name in lockscreen ncdu sidecar codex; do
  printf '%s\n' "$help_output" | grep -F "$command_name" >/dev/null
done

omcli_external() {
  for argument in "$@"; do printf '%s\n' "$argument"; done
}
omcli_run() {
  for argument in "$@"; do printf '%s\n' "$argument"; done
}
omcli_lockscreen_path() { printf '/mock/omcli-lockscreen\n'; }
omcli_helper_is_executable() { [ "$1" = /mock/omcli-lockscreen ]; }
lock_output="$(omcli_main lockscreen)"
[ "$lock_output" = "/mock/omcli-lockscreen" ]

sidecar_help_output="$(omcli_main sidecar)"
[ "$sidecar_help_output" = "$(omcli_main sidecar help)" ]
[ "$sidecar_help_output" = "$(omcli_main sidecar -h)" ]
[ "$sidecar_help_output" = "$(omcli_main sidecar --help)" ]
for sidecar_command_name in list connect disconnect; do
  printf '%s\n' "$sidecar_help_output" | grep -F "$sidecar_command_name" >/dev/null
done

omcli_sidecar_path() { printf '/mock/omcli-sidecar\n'; }
omcli_helper_is_executable() { [ "$1" = /mock/omcli-sidecar ]; }
[ "$(omcli_main sidecar list)" = "$(printf '%s\n' /mock/omcli-sidecar list)" ]
[ "$(omcli_main sidecar connect)" = "$(printf '%s\n' /mock/omcli-sidecar connect)" ]
[ "$(omcli_main sidecar connect 'Desk iPad')" = "$(printf '%s\n' /mock/omcli-sidecar connect 'Desk iPad')" ]
[ "$(omcli_main sidecar disconnect)" = "$(printf '%s\n' /mock/omcli-sidecar disconnect)" ]
[ "$(omcli_main sidecar disconnect 'Desk iPad')" = "$(printf '%s\n' /mock/omcli-sidecar disconnect 'Desk iPad')" ]

omcli_has_ncdu() { return 0; }
omcli_epoch() { printf '1234567890\n'; }
omcli_ncdu_threads() { printf '10\n'; }
ncdu_test_home="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omcli-ncdu-test.XXXXXX")"
trap 'rm -rf "$ncdu_test_home"' EXIT HUP INT TERM
HOME="$ncdu_test_home"
export HOME
ncdu_help_output="$(omcli_main ncdu)"
[ "$ncdu_help_output" = "$(omcli_main ncdu help)" ]
[ "$ncdu_help_output" = "$(omcli_main ncdu -h)" ]
[ "$ncdu_help_output" = "$(omcli_main ncdu --help)" ]
for ncdu_command_name in dump read; do
  printf '%s\n' "$ncdu_help_output" | grep -F "$ncdu_command_name" >/dev/null
done

ncdu_output="$(omcli_main ncdu dump)"
expected_ncdu_output="$(printf '%s\n' \
  ncdu -0 -x -t 10 -O "$HOME/.ncdu.1234567890" / \
  --exclude System --exclude Volumes --exclude "$HOME/.Trash" \
  "snapshot: $HOME/.ncdu.1234567890" \
  'expect:90s, actual: 0s')"
[ "$ncdu_output" = "$expected_ncdu_output" ]

explicit_snapshot="$HOME/snapshot with spaces"
: > "$explicit_snapshot"
expected_read_output="$(printf '%s\n' \
  ncdu -f "$explicit_snapshot" --show-itemcount --show-percent)"
[ "$(omcli_main ncdu read "$explicit_snapshot")" = "$expected_read_output" ]

: > "$HOME/.ncdu.2"
: > "$HOME/.ncdu.10"
: > "$HOME/.ncdu.not-a-timestamp"
expected_read_output="$(printf '%s\n' \
  ncdu -f "$HOME/.ncdu.10" --show-itemcount --show-percent)"
[ "$(omcli_main ncdu read)" = "$expected_read_output" ]

if omcli_main ncdu read "$HOME/missing" >/dev/null 2>&1; then
  echo "accepted missing ncdu snapshot" >&2
  exit 1
fi
if omcli_main ncdu read "$explicit_snapshot" extra >/dev/null 2>&1; then
  echo "accepted too many ncdu read arguments" >&2
  exit 1
fi
if omcli_main ncdu help extra >/dev/null 2>&1; then
  echo "accepted too many ncdu help arguments" >&2
  exit 1
fi
if omcli_main ncdu dump extra >/dev/null 2>&1; then
  echo "accepted ncdu dump arguments" >&2
  exit 1
fi

rm -f "$HOME/.ncdu.2" "$HOME/.ncdu.10" "$HOME/.ncdu.not-a-timestamp"
if omcli_main ncdu read >/dev/null 2>&1; then
  echo "read ncdu snapshot when none existed" >&2
  exit 1
fi

: > "$HOME/.ncdu.1234567890"
if omcli_main ncdu dump >/dev/null 2>&1; then
  echo "overwrote existing ncdu snapshot" >&2
  exit 1
fi
rm -f "$HOME/.ncdu.1234567890"

omcli_run() {
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-O" ]; then
      shift
      : > "$1"
      return 23
    fi
    shift
  done
  return 23
}
if omcli_main ncdu dump >/dev/null 2>&1; then
  echo "accepted failed ncdu dump" >&2
  exit 1
fi
[ ! -e "$HOME/.ncdu.1234567890" ]

omcli_run() {
  for argument in "$@"; do printf '%s\n' "$argument"; done
}
omcli_thread_writer_lock_pids() {
  printf '%s\n' 101 202
}
expected_codex_output="$(printf '%s\n' \
  /bin/kill -TERM 101 202 \
  'sent SIGTERM to Codex thread-writer lock holders: 101 202')"
[ "$(omcli_main codex)" = "$expected_codex_output" ]

omcli_thread_writer_lock_pids() { return 0; }
[ "$(omcli_main codex)" = "no Codex thread-writer lock holders found" ]

omcli_thread_writer_lock_pids() { printf 'not-a-pid\n'; }
if omcli_main codex >/dev/null 2>&1; then
  echo "accepted invalid thread-writer lock holder PID" >&2
  exit 1
fi

for rejected in 'lockscreen extra' 'ncdu unknown' 'sidecar list extra' 'sidecar connect one two' 'sidecar disconnect one two' 'codex extra'; do
  set -- $rejected
  if omcli_main "$@" >/dev/null 2>&1; then
    echo "accepted unexpected arguments: $rejected" >&2
    exit 1
  fi
done
if omcli_main unknown >/dev/null 2>&1; then
  echo "accepted unknown command" >&2
  exit 1
fi

file bin/omcli-lockscreen | grep -F 'Mach-O' >/dev/null
otool -L bin/omcli-lockscreen | grep -F '/System/Library/PrivateFrameworks/login.framework' >/dev/null
file bin/omcli-sidecar | grep -F 'Mach-O' >/dev/null

echo "tests passed"
