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

