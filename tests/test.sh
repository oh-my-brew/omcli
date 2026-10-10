#!/bin/sh

set -eu

REPOSITORY_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPOSITORY_DIR"

# Only parse source and built scripts. The functional subcommands are never run.
sh -n src/omcli.sh
sh -n bin/omcli

expected_version="$(tr -d '\n' < VERSION)"
[ "$expected_version" = "2026.10.10.1" ]
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
omcli_lockscreen_is_locked() { return 1; }
omcli_lockscreen_auto() { printf '%s\n' "auto:$1"; }
omcli_lockscreen_try_method() { printf '%s\n' "$2:$1"; }
omcli_lockscreen_doctor() { printf '%s\n' "doctor:$1"; }
[ "$(omcli_main lockscreen)" = "auto:/mock/omcli-lockscreen" ]
[ "$(omcli_main lockscreen lock)" = "auto:/mock/omcli-lockscreen" ]
[ "$(omcli_main lockscreen lock --method direct)" = "direct:/mock/omcli-lockscreen" ]
[ "$(omcli_main lockscreen --method direct)" = "direct:/mock/omcli-lockscreen" ]
[ "$(omcli_main lockscreen lock --method agent)" = "agent:/mock/omcli-lockscreen" ]
[ "$(omcli_main lockscreen lock --method display-sleep)" = "display-sleep:/mock/omcli-lockscreen" ]
[ "$(omcli_main lockscreen lock --method hotkey)" = "hotkey:/mock/omcli-lockscreen" ]
[ "$(omcli_main lockscreen status)" = "$(printf '%s\n' /mock/omcli-lockscreen status)" ]
[ "$(omcli_main lockscreen doctor)" = "doctor:/mock/omcli-lockscreen" ]

omcli_lockscreen_is_locked() { return 0; }
[ "$(omcli_main lockscreen lock --method direct)" = "screen is already locked" ]
omcli_lockscreen_is_locked() { return 1; }

lockscreen_help_output="$(omcli_main lockscreen help)"
[ "$lockscreen_help_output" = "$(omcli_main lockscreen -h)" ]
[ "$lockscreen_help_output" = "$(omcli_main lockscreen --help)" ]
for lockscreen_command_name in lock status doctor auto direct agent display-sleep hotkey; do
  printf '%s\n' "$lockscreen_help_output" | grep -F "$lockscreen_command_name" >/dev/null
done

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
omcli_ncdu_timestamp() { printf '20261010-143015\n'; }
omcli_ncdu_threads() { printf '10\n'; }
ncdu_test_home="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omcli-ncdu-test.XXXXXX")"
trap 'rm -rf "$ncdu_test_home"' EXIT HUP INT TERM
HOME="$ncdu_test_home"
XDG_STATE_HOME="$HOME/state with spaces"
export HOME
export XDG_STATE_HOME
mkdir -p "$HOME/Code folder"

omcli_run() {
  omcli_mock_output=""
  omcli_mock_previous=""
  for argument in "$@"; do
    printf '%s\n' "$argument"
    if [ "$omcli_mock_previous" = -O ]; then omcli_mock_output="$argument"; fi
    omcli_mock_previous="$argument"
  done
  [ -z "$omcli_mock_output" ] || : > "$omcli_mock_output"
}

ncdu_help_output="$(omcli_main ncdu)"
[ "$ncdu_help_output" = "$(omcli_main ncdu help)" ]
[ "$ncdu_help_output" = "$(omcli_main ncdu -h)" ]
[ "$ncdu_help_output" = "$(omcli_main ncdu --help)" ]
for ncdu_command_name in dump read list prune; do
  printf '%s\n' "$ncdu_help_output" | grep -F "$ncdu_command_name" >/dev/null
done

root_target_dir="$(omcli_ncdu_target_dir /)"
root_snapshot="$root_target_dir/20261010-143015-001.ncdu"
ncdu_output="$(omcli_main ncdu dump)"
expected_ncdu_output="$(printf '%s\n' \
  ncdu -0 -x -t 10 -O "$root_target_dir/.20261010-143015-001.ncdu.partial.$$" \
  --exclude System --exclude Volumes --exclude "$HOME/.Trash" -- / \
  'target: /' \
  "snapshot: $root_snapshot" \
  'actual: 0s')"
[ "$ncdu_output" = "$expected_ncdu_output" ]
[ -f "$root_snapshot" ]
[ "$(cat "$root_target_dir/target")" = / ]

code_target="$(CDPATH='' cd -- "$HOME/Code folder" && pwd -P)"
code_target_dir="$(omcli_ncdu_target_dir "$code_target")"
code_snapshot="$code_target_dir/20261010-143015-001.ncdu"
ncdu_output="$(omcli_main ncdu dump "$HOME/Code folder")"
expected_ncdu_output="$(printf '%s\n' \
  ncdu -0 -x -t 10 -O "$code_target_dir/.20261010-143015-001.ncdu.partial.$$" -- "$code_target" \
  "target: $code_target" \
  "snapshot: $code_snapshot" \
  'actual: 0s')"
[ "$ncdu_output" = "$expected_ncdu_output" ]
[ -f "$code_snapshot" ]
[ "$(cat "$code_target_dir/target")" = "$code_target" ]

explicit_snapshot="$HOME/snapshot with spaces"
: > "$explicit_snapshot"
expected_read_output="$(printf '%s\n' \
  ncdu -f "$explicit_snapshot" --show-itemcount --show-percent)"
[ "$(omcli_main ncdu read "$explicit_snapshot")" = "$expected_read_output" ]

: > "$code_target_dir/20261010-153015-001.ncdu"
expected_read_output="$(printf '%s\n' \
  ncdu -f "$code_target_dir/20261010-153015-001.ncdu" --show-itemcount --show-percent)"
[ "$(omcli_main ncdu read "$HOME/Code folder")" = "$expected_read_output" ]
[ "$(omcli_main ncdu read)" = "$expected_read_output" ]

list_output="$(omcli_main ncdu list)"
printf '%s\n' "$list_output" | grep -F 'CREATED' >/dev/null
printf '%s\n' "$list_output" | grep -F "$code_target" >/dev/null
printf '%s\n' "$list_output" | grep -F "$code_target_dir/20261010-153015-001.ncdu" >/dev/null

# Pruning is per target, ignores unknown files, and defaults to keeping three.
for stamp in 20261008-100000-001 20261009-100000-001 20261011-100000-001; do
  : > "$root_target_dir/$stamp.ncdu"
done
for stamp in 20261008-110000-001 20261009-110000-001; do
  : > "$code_target_dir/$stamp.ncdu"
done
: > "$root_target_dir/not-managed.ncdu"
prune_preview="$(omcli_main ncdu prune --dry-run)"
printf '%s\n' "$prune_preview" | grep -F 'would remove 2 snapshot(s)' >/dev/null
[ -f "$root_target_dir/20261008-100000-001.ncdu" ]
[ -f "$code_target_dir/20261008-110000-001.ncdu" ]

prune_output="$(omcli_main ncdu prune)"
printf '%s\n' "$prune_output" | grep -F 'removed 2 snapshot(s)' >/dev/null
[ ! -e "$root_target_dir/20261008-100000-001.ncdu" ]
[ ! -e "$code_target_dir/20261008-110000-001.ncdu" ]
[ -f "$root_target_dir/not-managed.ncdu" ]
[ "$(find "$root_target_dir" -type f -name '*.ncdu' ! -name 'not-managed.ncdu' | wc -l | tr -d ' ')" = 3 ]
[ "$(find "$code_target_dir" -type f -name '*.ncdu' | wc -l | tr -d ' ')" = 3 ]
printf '%s\n' "$(omcli_main ncdu prune --keep 10)" | grep -F 'removed 0 snapshot(s)' >/dev/null
if omcli_main ncdu prune --keep 0 >/dev/null 2>&1; then
  echo "accepted zero ncdu retention" >&2
  exit 1
fi
if omcli_main ncdu prune --keep 00 >/dev/null 2>&1; then
  echo "accepted zero-padded zero ncdu retention" >&2
  exit 1
fi

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
if omcli_main ncdu dump "$HOME" "$HOME/Code folder" >/dev/null 2>&1; then
  echo "accepted too many ncdu dump arguments" >&2
  exit 1
fi
if omcli_main ncdu list extra >/dev/null 2>&1; then
  echo "accepted ncdu list arguments" >&2
  exit 1
fi

# Legacy ~/.ncdu.* files are deliberately ignored.
legacy_state_home="$XDG_STATE_HOME"
XDG_STATE_HOME="$HOME/empty-state"
export XDG_STATE_HOME
: > "$HOME/.ncdu.9999999999"
if omcli_main ncdu read >/dev/null 2>&1; then
  echo "read a legacy ncdu snapshot" >&2
  exit 1
fi
XDG_STATE_HOME="$legacy_state_home"
export XDG_STATE_HOME

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
if find "$root_target_dir" -type f -name '*.partial.*' | grep . >/dev/null; then
  echo "left an incomplete ncdu snapshot" >&2
  exit 1
fi

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

for rejected in 'lockscreen extra' 'lockscreen bogus' 'lockscreen lock direct' 'lockscreen lock --method' 'lockscreen lock --method bogus' 'lockscreen lock --method direct extra' 'lockscreen status extra' 'lockscreen doctor extra' 'lockscreen help extra' 'ncdu unknown' 'sidecar list extra' 'sidecar connect one two' 'sidecar disconnect one two' 'codex extra'; do
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
if otool -L bin/omcli-lockscreen | grep -F '/System/Library/PrivateFrameworks/' >/dev/null; then
  echo "lockscreen helper links a private framework" >&2
  exit 1
fi
file bin/omcli-sidecar | grep -F 'Mach-O' >/dev/null

# Exercises the read-only path of the helper; the lock itself is never requested.
lockscreen_status_output="$(bin/omcli-lockscreen status 2>/dev/null)" && lockscreen_status_code=0 || lockscreen_status_code=$?
case "$lockscreen_status_code" in
  0)
    [ "$lockscreen_status_output" = "locked" ] || { echo "lockscreen status reported locked with unexpected output" >&2; exit 1; }
    ;;
  1)
    [ "$lockscreen_status_output" = "unlocked" ] || { echo "lockscreen status reported unlocked with unexpected output" >&2; exit 1; }
    ;;
  3)
    # No console lock state to read in this environment; the helper reported that.
    ;;
  *)
    echo "lockscreen status exited with status $lockscreen_status_code" >&2
    exit 1
    ;;
esac

lockscreen_capabilities_output="$(bin/omcli-lockscreen capabilities)"
printf '%s\n' "$lockscreen_capabilities_output" | grep -E '^direct\.symbol=(available|unavailable)$' >/dev/null
printf '%s\n' "$lockscreen_capabilities_output" | grep -E '^hotkey\.accessibility=(authorized|unauthorized)$' >/dev/null

echo "tests passed"
