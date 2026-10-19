omcli_update_root() {
  printf '%s/.local/share/omcli\n' "$HOME"
}

omcli_version_is_valid() {
  printf '%s\n' "$1" | /usr/bin/grep -Eq '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]*$'
}

omcli_version_is_greater() {
  omcli_version_left="$1"
  omcli_version_right="$2"
  omcli_version_is_valid "$omcli_version_left" || return 1
  omcli_version_is_valid "$omcli_version_right" || return 1
  /usr/bin/awk -v left="$omcli_version_left" -v right="$omcli_version_right" '
    BEGIN {
      split(left, lhs, "."); split(right, rhs, ".")
      for (i = 1; i <= 4; i++) {
        if ((lhs[i] + 0) > (rhs[i] + 0)) exit 0
        if ((lhs[i] + 0) < (rhs[i] + 0)) exit 1
      }
      exit 1
    }
  '
}

omcli_version_from_executable() {
  "$1" --version 2>/dev/null | /usr/bin/awk '$1 == "omcli" && NF == 2 { print $2 }'
}

omcli_maybe_delegate() {
  [ "${OMCLI_USE_BUNDLED:-0}" != "1" ] || return 0
  omcli_update_current="$(omcli_update_root)/current/bin/omcli"
  [ -x "$omcli_update_current" ] || return 0
  omcli_update_current_resolved="$(omcli_resolve_self "$omcli_update_current" 2>/dev/null || true)"
  omcli_update_running_resolved="$(omcli_resolve_self "$0" 2>/dev/null || true)"
  [ -z "$omcli_update_current_resolved" ] ||
    [ "$omcli_update_current_resolved" != "$omcli_update_running_resolved" ] || return 0
  omcli_update_current_version="$(OMCLI_USE_BUNDLED=1 omcli_version_from_executable "$omcli_update_current")"
  omcli_update_current_tag="$(cat "$(omcli_update_root)/current/.release-tag" 2>/dev/null || true)"
  if omcli_version_is_greater "$omcli_update_current_version" "$OMCLI_VERSION" ||
     { [ "$omcli_update_current_version" = "$OMCLI_VERSION" ] &&
       printf '%s\n' "$omcli_update_current_tag" | /usr/bin/grep -Eq -- '-beta\.[1-9][0-9]*$'; }; then
    exec "$omcli_update_current" "$@"
  fi
}

omcli_update_latest_stable() {
  omcli_update_url="$(/usr/bin/curl -fsSLI -o /dev/null -w '%{url_effective}' \
    https://github.com/oh-my-brew/omcli/releases/latest)" || return 1
  omcli_update_tag="${omcli_update_url##*/}"
  case "$omcli_update_tag" in
    v*) omcli_update_tag="${omcli_update_tag#v}" ;;
  esac
  omcli_version_is_valid "$omcli_update_tag" || return 1
  printf '%s\n%s\n' "$omcli_update_tag" "v$omcli_update_tag"
}

omcli_update_latest_beta() {
  omcli_update_metadata="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/omcli-beta-releases.XXXXXX")" || return 1
  if ! /usr/bin/curl -fsSL -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/repos/oh-my-brew/omcli/releases?per_page=20' \
    -o "$omcli_update_metadata"; then
    /bin/rm -f -- "$omcli_update_metadata"
    return 1
  fi
  omcli_update_index=0
  while [ "$omcli_update_index" -lt 20 ]; do
    omcli_update_prerelease="$(/usr/bin/plutil -extract "$omcli_update_index.prerelease" raw -o - "$omcli_update_metadata" 2>/dev/null || true)"
    omcli_update_tag="$(/usr/bin/plutil -extract "$omcli_update_index.tag_name" raw -o - "$omcli_update_metadata" 2>/dev/null || true)"
    if [ "$omcli_update_prerelease" = true ] &&
       printf '%s\n' "$omcli_update_tag" | /usr/bin/grep -Eq '^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]*-beta\.[1-9][0-9]*$'; then
      omcli_update_version="${omcli_update_tag#v}"
      omcli_update_version="${omcli_update_version%%-beta.*}"
      /bin/rm -f -- "$omcli_update_metadata"
      printf '%s\n%s\n' "$omcli_update_version" "$omcli_update_tag"
      return 0
    fi
    omcli_update_index=$((omcli_update_index + 1))
  done
  /bin/rm -f -- "$omcli_update_metadata"
  return 1
}

omcli_update_fetch_release() {
  omcli_update_version="$1"
  omcli_update_tag="$2"
  omcli_update_destination="$3"
  omcli_update_base="https://github.com/oh-my-brew/omcli/releases/download/$omcli_update_tag"
  /usr/bin/curl -fsSL \
    "$omcli_update_base/omcli-$omcli_update_version.tar.gz" \
    -o "$omcli_update_destination/omcli-$omcli_update_version.tar.gz"
  /usr/bin/curl -fsSL \
    "$omcli_update_base/omcli-$omcli_update_version.tar.gz.sha256" \
    -o "$omcli_update_destination/omcli-$omcli_update_version.tar.gz.sha256"
}

omcli_update_validate_archive_paths() {
  omcli_update_archive="$1"
  omcli_update_prefix="omcli-$2/"
  /usr/bin/tar -tzf "$omcli_update_archive" | /usr/bin/awk -v prefix="$omcli_update_prefix" '
    BEGIN { found = 0 }
    {
      found = 1
      if (index($0, prefix) != 1 || $0 ~ /(^|\/)\.\.($|\/)/ || $0 ~ /^\// || $0 ~ /\\/) exit 1
    }
    END { if (!found) exit 1 }
  '
}

omcli_update_keep_two_releases() {
  omcli_update_releases="$1"
  omcli_update_count=0
  omcli_update_old_ifs="$IFS"
  IFS='
'
  for omcli_update_release in $(/bin/ls -1dt "$omcli_update_releases"/* 2>/dev/null); do
    omcli_update_count=$((omcli_update_count + 1))
    if [ "$omcli_update_count" -gt 2 ]; then
      /bin/rm -rf -- "$omcli_update_release"
    fi
  done
  IFS="$omcli_update_old_ifs"
}

omcli_update_install() {
  omcli_update_version="$1"
  omcli_update_tag="$2"
  omcli_update_root_path="$(omcli_update_root)"
  omcli_update_releases="$omcli_update_root_path/releases"
  omcli_update_release_id="${omcli_update_tag#v}"
  omcli_update_target="$omcli_update_releases/$omcli_update_release_id"
  omcli_update_temporary="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omcli-update.XXXXXX")" || return 1

  if ! omcli_update_fetch_release "$omcli_update_version" "$omcli_update_tag" "$omcli_update_temporary"; then
    /bin/rm -rf -- "$omcli_update_temporary"
    return 1
  fi

  omcli_update_archive="$omcli_update_temporary/omcli-$omcli_update_version.tar.gz"
  omcli_update_checksum="$omcli_update_archive.sha256"
  if ! (cd "$omcli_update_temporary" && /usr/bin/shasum -a 256 -c "$(basename "$omcli_update_checksum")") >/dev/null 2>&1; then
    /bin/rm -rf -- "$omcli_update_temporary"
    omcli_fail "release checksum verification failed"
    return 1
  fi
  if ! omcli_update_validate_archive_paths "$omcli_update_archive" "$omcli_update_version"; then
    /bin/rm -rf -- "$omcli_update_temporary"
    omcli_fail "release archive contains an unsafe path"
    return 1
  fi
  if LC_ALL=C /usr/bin/tar -tvzf "$omcli_update_archive" | /usr/bin/awk '$1 ~ /^[lh]/ { found = 1 } END { exit found ? 0 : 1 }'; then
    /bin/rm -rf -- "$omcli_update_temporary"
    omcli_fail "release archive contains a link"
    return 1
  fi

  /usr/bin/tar -xzf "$omcli_update_archive" -C "$omcli_update_temporary"
  omcli_update_extracted="$omcli_update_temporary/omcli-$omcli_update_version"
  if [ "$(cat "$omcli_update_extracted/VERSION" 2>/dev/null)" != "$omcli_update_version" ] ||
     [ ! -x "$omcli_update_extracted/bin/omcli" ] ||
     [ ! -x "$omcli_update_extracted/bin/omcli-lockscreen" ] ||
     [ ! -x "$omcli_update_extracted/bin/omcli-sidecar" ] ||
     [ -n "$(find "$omcli_update_extracted" -type l -print -quit)" ]; then
    /bin/rm -rf -- "$omcli_update_temporary"
    omcli_fail "release payload validation failed"
    return 1
  fi
  omcli_update_payload_version="$(OMCLI_SOURCE_ONLY=0 OMCLI_USE_BUNDLED=1 "$omcli_update_extracted/bin/omcli" --version 2>/dev/null || true)"
  if [ "$omcli_update_payload_version" != "omcli $omcli_update_version" ]; then
    /bin/rm -rf -- "$omcli_update_temporary"
    omcli_fail "release executable version does not match: $omcli_update_payload_version"
    return 1
  fi

  /bin/mkdir -p "$omcli_update_releases"
  /bin/chmod 700 "$omcli_update_root_path" "$omcli_update_releases"
  if [ ! -d "$omcli_update_target" ]; then
    printf '%s\n' "$omcli_update_tag" > "$omcli_update_extracted/.release-tag"
    /bin/mv "$omcli_update_extracted" "$omcli_update_target"
  fi
  /bin/ln -s "releases/$omcli_update_release_id" "$omcli_update_root_path/.current.$$"
  /bin/mv -fh "$omcli_update_root_path/.current.$$" "$omcli_update_root_path/current"
  omcli_update_keep_two_releases "$omcli_update_releases"
  /bin/rm -rf -- "$omcli_update_temporary"
  printf 'updated omcli to %s (%s)\n' "$omcli_update_version" "$omcli_update_tag"
}

omcli_update_reset() {
  omcli_update_root_path="$(omcli_update_root)"
  /bin/rm -rf -- "$omcli_update_root_path/current" "$omcli_update_root_path/releases"
  printf 'removed user-level omcli updates; the Homebrew version will be used\n'
}

omcli_update_usage() {
  cat <<'EOF'
Usage: omcli update [--check|--beta|--check-beta|--reset]

Without options, downloads and activates the latest stable release under
~/.local/share/omcli. The Homebrew installation remains unchanged.

Options:
  --check  Report whether a newer stable release is available
  --beta   Download and activate the latest beta candidate
  --check-beta  Report whether a different beta candidate is available
  --reset  Remove user-level releases and use the Homebrew version
  -h, --help  Show this help

Set OMCLI_USE_BUNDLED=1 to bypass a user-level release for one command.
EOF
}

omcli_update() {
  omcli_update_action="${1:-install}"
  [ "$#" -le 1 ] || omcli_fail "update accepts at most one option" || return
  case "$omcli_update_action" in
    -h|--help|help) omcli_update_usage ;;
    --reset) omcli_update_reset ;;
    install|--check|--beta|--check-beta)
      omcli_update_channel=stable
      case "$omcli_update_action" in
        --beta|--check-beta) omcli_update_channel=beta ;;
      esac
      if [ "$omcli_update_channel" = beta ]; then
        omcli_update_metadata="$(omcli_update_latest_beta)" || {
          omcli_fail "could not determine the latest beta candidate"
          return 1
        }
      else
        omcli_update_metadata="$(omcli_update_latest_stable)" || {
          omcli_fail "could not determine the latest stable version"
          return 1
        }
      fi
      omcli_update_latest="$(printf '%s\n' "$omcli_update_metadata" | /usr/bin/sed -n '1p')"
      omcli_update_tag="$(printf '%s\n' "$omcli_update_metadata" | /usr/bin/sed -n '2p')"
      omcli_update_current_tag="$(cat "$(omcli_update_root)/current/.release-tag" 2>/dev/null || true)"
      omcli_update_available=false
      if omcli_version_is_greater "$omcli_update_latest" "$OMCLI_VERSION"; then
        omcli_update_available=true
      elif [ "$omcli_update_latest" = "$OMCLI_VERSION" ]; then
        if [ "$omcli_update_channel" = beta ] && [ "$omcli_update_current_tag" != "$omcli_update_tag" ]; then
          omcli_update_available=true
        elif [ "$omcli_update_channel" = stable ] &&
             printf '%s\n' "$omcli_update_current_tag" | /usr/bin/grep -Eq -- '-beta\.[1-9][0-9]*$'; then
          omcli_update_available=true
        fi
      fi
      if [ "$omcli_update_available" = true ]; then
        if [ "$omcli_update_action" = "--check" ] || [ "$omcli_update_action" = "--check-beta" ]; then
          printf 'update available: %s -> %s (%s)\n' "$OMCLI_VERSION" "$omcli_update_latest" "$omcli_update_tag"
        else
          omcli_update_install "$omcli_update_latest" "$omcli_update_tag"
        fi
      else
        printf 'omcli %s is up to date for the %s channel\n' "$OMCLI_VERSION" "$omcli_update_channel"
      fi
      ;;
    *) omcli_fail "unknown update option: $omcli_update_action" ;;
  esac
}
