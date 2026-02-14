#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./publisher/scripts/watch-data.sh [--quiet SEC]
#
# Watches for MP3/JSON changes and runs sync-data.sh on change.
# JSON write events are ignored to avoid loops from sync-data.sh writes.
# MP3 events are debounced: sync runs after a quiet period with no MP3 changes.
# If no Hugo config exists in the mounted source, defaults are copied in once.
# Default media assets are also seeded into /srv/media when missing.

mp3_dir="/srv/media/episodes"
json_dir="/work/publisher/hugo/data/generated/episodes"
quiet_seconds="10"
cover_dir="/srv/media/covers"
hugo_src="/work/publisher/hugo"
hugo_dest="/srv/www"
hugo_defaults="/opt/publisher-defaults"
media_defaults="/opt/publisher-media-defaults"
default_cover_src="$media_defaults/covers/default_cover.jpg"
rss_cover_src="$media_defaults/covers/rss_cover.jpg"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) quiet_seconds="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--quiet SEC]"
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) echo "Unexpected argument: $1" >&2; exit 2 ;;
  esac
done

if ! [[ "$quiet_seconds" =~ ^[0-9]+$ ]]; then
  echo "Quiet seconds must be a non-negative integer." >&2
  exit 2
fi

sync_args=(--mp3-dir "$mp3_dir" --json-dir "$json_dir" --cover-dir "$cover_dir" --hugo-src "$hugo_src" --hugo-dest "$hugo_dest")

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sync_script="$script_dir/sync-data.sh"

if [[ ! -x "$sync_script" ]]; then
  echo "Missing or non-executable: $sync_script" >&2
  exit 2
fi

if [[ ! -d "$mp3_dir" ]]; then
  mkdir -p "$mp3_dir"
fi

if [[ ! -d "$json_dir" ]]; then
  mkdir -p "$json_dir"
fi

if [[ ! -d "$cover_dir" ]]; then
  mkdir -p "$cover_dir"
fi

if [[ ! -d "$hugo_src" ]]; then
  mkdir -p "$hugo_src"
fi

if [[ ! -d "$hugo_defaults" ]]; then
  echo "Hugo defaults directory does not exist: $hugo_defaults" >&2
  exit 2
fi
if [[ ! -f "$hugo_src/hugo.yaml" ]]; then
  echo "Seeding Hugo defaults into $hugo_src"
  cp -a "$hugo_defaults/." "$hugo_src/"
fi

if [[ ! -d "$media_defaults" ]]; then
  echo "Media defaults directory does not exist: $media_defaults" >&2
  exit 2
fi
if [[ ! -f "$default_cover_src" ]]; then
  echo "Missing default cover source: $default_cover_src" >&2
  exit 2
fi
if [[ ! -f "$rss_cover_src" ]]; then
  echo "Missing RSS cover source: $rss_cover_src" >&2
  exit 2
fi
if [[ ! -f "$cover_dir/default_cover.jpg" ]]; then
  cp "$default_cover_src" "$cover_dir/default_cover.jpg"
fi
if [[ ! -f "$cover_dir/rss_cover.jpg" ]]; then
  cp "$rss_cover_src" "$cover_dir/rss_cover.jpg"
fi

lock_dir="${TMPDIR:-/tmp}/podosef-sync.lock"

run_sync() {
  if mkdir "$lock_dir" 2>/dev/null; then
    # Always release lock, even if sync-data.sh exits non-zero.
    local rc=0
    bash "$sync_script" "$@" || rc=$?
    rmdir "$lock_dir" 2>/dev/null || true
    return "$rc"
  fi
}

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "inotifywait not found; install inotify-tools in the container." >&2
  exit 2
fi

if [[ -d "$lock_dir" ]]; then
  echo "Removing stale lock: $lock_dir"
  rmdir "$lock_dir" 2>/dev/null || rm -rf "$lock_dir"
fi

echo "Run initial sync"
run_sync "${sync_args[@]}"

watch_json() {
  inotifywait -m -e delete,moved_from --format '%f' "$json_dir" | while read -r filename; do
    if [[ -n "$filename" && ! "$filename" =~ \.[jJ][sS][oO][nN]$ ]]; then
      continue
    fi
    run_sync "${sync_args[@]}"
  done
}

watch_json &
json_pid=$!

watch_mp3_deletes() {
  inotifywait -m -e delete,moved_from --format '%f' "$mp3_dir" | while read -r filename; do
    if [[ -n "$filename" && ! "$filename" =~ \.[mM][pP]3$ ]]; then
      continue
    fi
    run_sync "${sync_args[@]}"
  done
}

watch_mp3_deletes &
mp3_del_pid=$!
trap 'kill "$json_pid" "$mp3_del_pid" 2>/dev/null || true' EXIT

echo "Watching $mp3_dir and $json_dir with inotifywait..."
echo "Debounce quiet period: ${quiet_seconds}s"
while true; do
  inotifywait -q -e close_write,create,modify,moved_to "$mp3_dir" >/dev/null 2>&1
  while inotifywait -q -t "$quiet_seconds" -e close_write,create,modify,moved_to "$mp3_dir" >/dev/null 2>&1; do
    :
  done
  run_sync "${sync_args[@]}"
done
