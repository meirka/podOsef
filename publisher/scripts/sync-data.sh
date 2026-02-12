#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./publisher/scripts/sync-data.sh --mp3-dir DIR --json-dir DIR --cover-dir DIR --hugo-src DIR --hugo-dest DIR
#
# Runs:
#   1) Extract missing JSON/cover data from MP3s.
#   2) Prune orphan JSON files.
#   3) Build Hugo output.

mp3_dir=""
json_dir=""
cover_dir=""
hugo_src=""
hugo_dest=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract_script="$script_dir/extract-mp3-data.sh"
prune_script="$script_dir/prune-orphan-json.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mp3-dir) mp3_dir="${2:-}"; shift 2 ;;
    --json-dir) json_dir="${2:-}"; shift 2 ;;
    --cover-dir) cover_dir="${2:-}"; shift 2 ;;
    --hugo-src) hugo_src="${2:-}"; shift 2 ;;
    --hugo-dest) hugo_dest="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --mp3-dir DIR --json-dir DIR --cover-dir DIR --hugo-src DIR --hugo-dest DIR"
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) echo "Unexpected argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$mp3_dir" || -z "$json_dir" || -z "$cover_dir" || -z "$hugo_src" || -z "$hugo_dest" ]]; then
  echo "Missing required arguments." >&2
  echo "Usage: $0 --mp3-dir DIR --json-dir DIR --cover-dir DIR --hugo-src DIR --hugo-dest DIR" >&2
  exit 2
fi

if [[ ! -x "$extract_script" ]]; then
  echo "Missing or non-executable: $extract_script" >&2
  exit 2
fi

if [[ ! -x "$prune_script" ]]; then
  echo "Missing or non-executable: $prune_script" >&2
  exit 2
fi

if [[ ! -d "$mp3_dir" ]]; then
  echo "MP3 directory not found: $mp3_dir" >&2
  exit 2
fi

if [[ ! -d "$hugo_src" ]]; then
  echo "Hugo source directory not found: $hugo_src" >&2
  exit 2
fi

if ! command -v hugo >/dev/null 2>&1; then
  echo "hugo command not found." >&2
  exit 2
fi

mkdir -p "$json_dir" "$cover_dir"
mkdir -p "$hugo_dest"

missing=()
while IFS= read -r -d '' mp3; do
  base="$(basename "$mp3")"
  stem="${base%.[mM][pP]3}"
  json_path="$json_dir/$stem.json"
  if [[ ! -f "$json_path" ]]; then
    missing+=("$mp3")
  fi
done < <(find "$mp3_dir" -type f -iname '*.mp3' -print0)

if (( ${#missing[@]} == 0 )); then
  echo "All MP3 files have JSON metadata."
else
  bash "$extract_script" --out "$json_dir" --cover-out "$cover_dir" "${missing[@]}"
  echo "Generated metadata for ${#missing[@]} MP3 file(s)."
fi

bash "$prune_script" --mp3-dir "$mp3_dir" --json-dir "$json_dir"

hugo --source "$hugo_src" --destination "$hugo_dest" --minify
echo "Built Hugo site into: $hugo_dest"
