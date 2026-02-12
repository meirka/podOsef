#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./publisher/scripts/prune-orphan-json.sh --mp3-dir DIR --json-dir DIR

mp3_dir=""
json_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mp3-dir) mp3_dir="${2:-}"; shift 2 ;;
    --json-dir) json_dir="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --mp3-dir DIR --json-dir DIR"
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) echo "Unexpected argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$mp3_dir" || -z "$json_dir" ]]; then
  echo "Missing required arguments." >&2
  echo "Usage: $0 --mp3-dir DIR --json-dir DIR" >&2
  exit 2
fi

if [[ ! -d "$json_dir" ]]; then
  echo "JSON directory not found: $json_dir" >&2
  exit 2
fi

if [[ ! -d "$mp3_dir" ]]; then
  echo "MP3 directory not found: $mp3_dir" >&2
  exit 2
fi

extract_field() {
  local file="$1"
  local key="$2"
  awk -v k="$key" -F'"' '
    $0 ~ "\"" k "\"" { print $4; exit }
  ' "$file"
}

removed=0
while IFS= read -r -d '' json; do
  base="$(basename "$json")"
  stem="${base%.json}"
  file_name="$(extract_field "$json" "FileName")"
  if [[ -z "$file_name" ]]; then
    file_name="$(extract_field "$json" "SourceFile")"
  fi
  if [[ -z "$file_name" ]]; then
    file_name="${stem}.mp3"
  fi

  mp3_path="$mp3_dir/$file_name"
  if [[ ! -f "$mp3_path" ]]; then
    rm -f "$json"
    echo "Removed: $json (missing $file_name)"
    removed=$((removed + 1))
  fi
done < <(find "$json_dir" -type f -name '*.json' -print0)

echo "Done. Removed $removed orphan JSON file(s)."
