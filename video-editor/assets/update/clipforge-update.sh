#!/bin/sh
# ClipForge update helper for macOS (plain /bin/sh).
#
#   clipforge-update.sh <InstallDir> <NewDir> <WaitPid> <ResultFile> <Version> [restart command...]
#
# Started by the app, in the background, just before it closes. It waits
# until the app has gone, then swaps two folders that sit side by side:
#
#     <InstallDir> (ClipForge.app)   -> <InstallDir>.update-old
#     <NewDir> (the new ClipForge.app) -> <InstallDir>
#
# and starts the app again (default: open -n <InstallDir>). A rename
# either happens completely or not at all:
#   - if the old app cannot be moved aside, nothing has changed;
#   - if the new one cannot be moved in, the old one is moved back.
# The result goes to <ResultFile> as one line of JSON
# ({"status":"updated"|"failed"|"broken","message":"...","version":"..."}).
#
# It only ever touches <InstallDir>, <InstallDir>.update-old and <NewDir>;
# projects and media (Documents/ClipForge) are never touched.
#
# 1.14.1: every step is also written to the file named by
# $CLIPFORGE_UPDATE_LOG (update-log.txt, shared with the app); the first
# line, "started token=$CLIPFORGE_UPDATE_TOKEN", is what the app waits for
# before it closes. An app that has not closed after the wait is left
# alone (exit 6). Unlike on Windows the app is still swapped by renaming:
# macOS renames a folder whatever is open in it, so the Windows problem
# (a window or terminal holding the folder) does not exist here.

install="${1%/}"
new="${2%/}"
wait_pid="${3:-0}"
result="${4:-}"
version="${5:-}"
[ "$#" -ge 5 ] && shift 5 || shift "$#"
old="$install.update-old"

log="${CLIPFORGE_UPDATE_LOG:-}"
log() {
  [ -n "$log" ] || return 0
  printf '%s script(sh): %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$log" 2>/dev/null || true
}

write_result() {
  log "result: $1 $2"
  [ -n "$result" ] || return 0
  # $2 holds only fixed text and a path; quotes and backslashes are escaped.
  message=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"status":"%s","message":"%s","version":"%s"}\n' "$1" "$message" "$version" \
    > "$result" 2>/dev/null || true
}

start_app() {
  if [ "$#" -gt 1 ]; then
    dir="$1"; shift
    CLIPFORGE_APP_DIR="$dir" "$@" >/dev/null 2>&1 &
  elif [ -d "$1" ] && command -v open >/dev/null 2>&1; then
    open -n "$1" >/dev/null 2>&1 &
  fi
}

log "started token=${CLIPFORGE_UPDATE_TOKEN:-} pid=$$"
log "args: install=[$install] new=[$new] waitPid=$wait_pid version=$version result=[$result]"

# 1. Wait until the app has closed (at most a minute).
wait_steps=$(( ${CLIPFORGE_UPDATE_WAIT_SECONDS:-60} * 4 ))
if [ "$wait_pid" -gt 0 ] 2>/dev/null; then
  i=0
  while kill -0 "$wait_pid" 2>/dev/null && [ "$i" -lt "$wait_steps" ]; do
    sleep 0.25
    i=$((i + 1))
  done
  if kill -0 "$wait_pid" 2>/dev/null; then
    # Still there: it is not replaced under its feet, nor started twice.
    write_result failed "ClipForge did not close, so nothing was changed."
    exit 6
  fi
  log "the app (pid $wait_pid) has closed"
fi

# 2. Nothing to do without both.
if [ ! -d "$install" ]; then
  write_result failed "The ClipForge app was not found."
  exit 2
fi
if [ ! -d "$new" ]; then
  write_result failed "The downloaded update is not complete."
  start_app "$install" "$@"
  exit 2
fi
if [ -e "$old" ] && [ ! -e "$old.marker" ]; then
  write_result failed "Something called $(basename "$old") that ClipForge did not make is in the way. Move or rename it, then try again."
  start_app "$install" "$@"
  exit 2
fi
if [ -e "$old" ] && ! rm -rf "$old"; then
  write_result failed "An older copy of ClipForge next to the app could not be removed."
  start_app "$install" "$@"
  exit 2
fi

# 3. The old app steps aside. If this fails nothing has changed.
# The marker says "the updater made this" (kept next to the app, not in
# it: a file added inside a signed app would break its seal).
: > "$old.marker" 2>/dev/null || true
if ! mv "$install" "$old" 2>/dev/null; then
  log "mv [$install] -> [$old] failed"
  rm -f "$old.marker" 2>/dev/null || true
  write_result failed "The ClipForge app could not be moved (no permission to change this folder?)."
  start_app "$install" "$@"
  exit 3
fi

# 4. The new app takes its place; on failure the old one comes back.
if ! mv "$new" "$install" 2>/dev/null; then
  log "mv [$new] -> [$install] failed"
  if mv "$old" "$install" 2>/dev/null; then
    write_result failed "The new version could not be put in place; ClipForge is unchanged."
    start_app "$install" "$@"
    exit 4
  fi
  write_result broken "The update could not be finished. ClipForge still works from: $old"
  start_app "$old" "$@"
  exit 5
fi

write_result updated ""
start_app "$install" "$@"

# 5. Tidy up (the app also removes a leftover on its next start).
rm -rf "$old" 2>/dev/null && rm -f "$old.marker" 2>/dev/null
rm -f "$new.marker" 2>/dev/null || true
log "done"
exit 0
