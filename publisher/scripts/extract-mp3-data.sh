#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./publisher/scripts/extract-mp3-data.sh [-r] [--out DIR] [--cover-out DIR] <file_or_dir>...
# Examples:
#   ./publisher/scripts/extract-mp3-data.sh song.mp3
#   ./publisher/scripts/extract-mp3-data.sh -r ./Music
#   ./publisher/scripts/extract-mp3-data.sh -r --out ./out ./Music
#   ./publisher/scripts/extract-mp3-data.sh -r --out ./tags --cover-out ./covers ./Music

recursive=0
out_dir=""
cover_out=""

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--recursive) recursive=1; shift ;;
    --out) out_dir="${2:-}"; shift 2 ;;
    --cover-out) cover_out="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./publisher/scripts/extract-mp3-data.sh [-r] [--out DIR] [--cover-out DIR] <file_or_dir>...
EOF
      exit 0
      ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
args+=("$@")

if [[ ${#args[@]} -eq 0 ]]; then
  echo "Provide at least one mp3 file or directory." >&2
  exit 2
fi

dump_one() {
  local mp3="$1"
  local name stem dest cover_dest json outpattern
  local cover_file cover_matches
  local cover_path cover_ext cover_hash hashed_name hashed_path
  local exif_args

  name="$(basename "$mp3")"
  stem="${name%.[mM][pP]3}"

  # Default: alongside each MP3; otherwise put everything in --out
  if [[ -n "$out_dir" ]]; then
    dest="$out_dir"
  else
    dest="$(dirname "$mp3")"
  fi
  mkdir -p "$dest"

  if [[ -n "$cover_out" ]]; then
    cover_dest="$cover_out"
  else
    cover_dest="$dest"
  fi
  mkdir -p "$cover_dest"

  json="$dest/$stem.json"
  outpattern="$cover_dest/${stem}_cover%c.%s"
  file_size_bytes="$(wc -c < "$mp3" | tr -d ' ')"

  # 1) Pictures -> files (try common tag names)
  if ! exiftool -b -Picture -W "$outpattern" "$mp3" >/dev/null 2>&1; then
    if ! exiftool -b -CoverArt -W "$outpattern" "$mp3" >/dev/null 2>&1; then
      exiftool -b -APIC -W "$outpattern" "$mp3" >/dev/null 2>&1 || true
    fi
  fi

  cover_file=""
  cover_matches=()
  shopt -s nullglob
  cover_matches=("$cover_dest/${stem}_cover"*)
  shopt -u nullglob
  if (( ${#cover_matches[@]} > 0 )); then
    cover_file="$(basename "${cover_matches[0]}")"
    if (( ${#cover_matches[@]} > 1 )); then
      for ((i=1; i<${#cover_matches[@]}; i++)); do
        rm -f "${cover_matches[$i]}"
      done
    fi
  fi

  if [[ -n "$cover_file" ]]; then
    cover_path="$cover_dest/$cover_file"
    cover_ext="${cover_file##*.}"
    if [[ "$cover_ext" == "$cover_file" ]]; then
      cover_ext=""
    fi

    if command -v sha256sum >/dev/null 2>&1; then
      cover_hash="$(sha256sum "$cover_path" | cut -d' ' -f1)"
    elif command -v shasum >/dev/null 2>&1; then
      cover_hash="$(shasum -a 256 "$cover_path" | cut -d' ' -f1)"
    else
      echo "WARN: sha256sum/shasum not found; leaving cover filename as-is" >&2
      cover_hash=""
    fi

    if [[ -n "$cover_hash" ]]; then
      if [[ -n "$cover_ext" ]]; then
        hashed_name="${cover_hash}.${cover_ext}"
      else
        hashed_name="${cover_hash}"
      fi
      hashed_path="$cover_dest/$hashed_name"
      if [[ "$cover_path" != "$hashed_path" ]]; then
        if [[ -e "$hashed_path" ]]; then
          rm -f "$cover_path"
        else
          mv "$cover_path" "$hashed_path"
        fi
      fi
      cover_file="$hashed_name"
    fi
  else
    cover_file="default_cover.jpg"
  fi

  # 2) Tags -> JSON (convert exiftool's single-item array to an object)
  exif_args=(-j)
  exif_args+=(-userParam "PictureName#=$cover_file")
  exif_args+=(-userParam "FileSizeBytes#=$file_size_bytes")
  exiftool "${exif_args[@]}" "$mp3" \
    | sed '1s/^[[:space:]]*\[//; $s/\][[:space:]]*$//' \
    > "$json"

  echo "OK: $mp3 -> $(basename "$json")"
}

collect_mp3s() {
  local p
  for p in "${args[@]}"; do
    if [[ -f "$p" && "$p" =~ \.[mM][pP]3$ ]]; then
      printf '%s\0' "$p"
    elif [[ -d "$p" ]]; then
      if [[ $recursive -eq 1 ]]; then
        find "$p" -type f \( -iname '*.mp3' \) -print0
      else
        find "$p" -maxdepth 1 -type f \( -iname '*.mp3' \) -print0
      fi
    fi
  done
}

# Process safely with NUL delimiters (handles spaces/newlines in filenames)
while IFS= read -r -d '' mp3; do
  dump_one "$mp3"
done < <(collect_mp3s)
