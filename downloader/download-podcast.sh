#!/bin/bash

# The following script parses podcast feeds and downloads all podcast episodes listed in
# the feed if they don't exist within the target path. The target directory will be created
# if it does not exist.

if test -z "${MAIN_CDN_SERVER:-}"
then
      echo "MAIN_CDN_SERVER is required." >&2
      exit 1
fi

if test -z "${PODCAST_DIR:-}"
then
      echo "PODCAST_DIR is required." >&2
      exit 1
fi

if test -z "${CHECK_CDN_TIME:-}"
then
      CHECK_CDN_TIME=2700 # 45 minutes
fi

[ -x "$(command -v wget)" ] || (echo "wget is not installed" && exit 1)
[ -x "$(command -v sed)" ] || (echo "sed is not installed" && exit 1)
[ -x "$(command -v xargs)" ] || (echo "xargs is not installed" && exit 1)

download_and_verify_from_feed() {
  local feed_url="$1"
  local dest_dir="$2"

  mkdir -p "$dest_dir" || return 1
  cd "$dest_dir" || return 1

  # Decode URL-encoded filenames (e.g., %20 -> space). Also treats + as space.
  urldecode() {
    local s="${1//+/ }"
    printf '%b' "${s//%/\\x}"
  }

  # Fetch the feed quietly. If this fails, stop early.
  local xml
  if ! xml="$(wget -q -O - "$feed_url")"; then
    echo "ERROR: failed to fetch feed: $feed_url" >&2
    return 1
  fi

  # Process each enclosure line; extract url and length independently so order doesn't matter.
  printf '%s\n' "$xml" \
    | sed -n '/enclosure/p' \
    | while IFS= read -r line; do
        local url expected_len raw file tmp actual_len current_len

        url="$(printf '%s\n' "$line" | sed -n 's/.*url="\([^"]*\)".*/\1/p')"
        expected_len="$(printf '%s\n' "$line" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"

        # Skip if no URL was found on this line
        [ -n "$url" ] || continue

        # Choose local filename from URL path segment; decode %xx so %20 becomes spaces.
        raw="$(basename "${url%%\?*}")"
        file="$(urldecode "$raw")"

        # If file exists and length matches, skip download
        if [ -f "$file" ] && [ -n "$expected_len" ]; then
          current_len="$(stat -c%s "$file" 2>/dev/null || wc -c < "$file")"
          if [ "$current_len" -eq "$expected_len" ]; then
            echo "OK (existing): $file ($current_len bytes)"
            continue
          else
            echo "MISMATCH (existing): $file expected=$expected_len actual=$current_len; removing and re-downloading"
            rm -f "$file"
          fi
        fi

        # Download into a temporary file first (prevents leaving a truncated final file).
        tmp="${file}.part"
        rm -f "$tmp"

        # Quiet download: no progress meter / noisy output.
        if ! wget -q -O "$tmp" "$url"; then
          echo "ERROR: download failed: $url" >&2
          rm -f "$tmp"
          continue
        fi

        # Verify downloaded size in bytes
        actual_len="$(stat -c%s "$tmp" 2>/dev/null || wc -c < "$tmp")"

        if [ -n "$expected_len" ] && [ "$actual_len" -eq "$expected_len" ]; then
          mv -f "$tmp" "$file"
          echo "OK: $file ($actual_len bytes)"
        else
          echo "MISMATCH: $file expected=$expected_len actual=$actual_len"
          rm -f "$tmp"
        fi
      done
}


function echo_update_stats {
    PODCAST_UPDATE_LIST=$(find $1 -ctime -1 -type f)

    echo "All podcasts updated."

    if [ -n "$PODCAST_UPDATE_LIST" ]
    then
        echo -e "\nNew episodes within the last 24 hours:"
        echo $PODCAST_UPDATE_LIST | xargs basename | xargs printf "* %s\n"
    else
        echo "No new episodes are available."
    fi
}

# Download audio files from podcast feeds.
# Feed subscriptions are exemplified below.

while true
do
      download_and_verify_from_feed $MAIN_CDN_SERVER    $PODCAST_DIR/

      # This one's sending notifications to my phone but might not be useful for you
      #/root/send_notification.sh "$(echo_update_stats $PODCAST_DIR)"
      echo_update_stats $PODCAST_DIR

      sleep $CHECK_CDN_TIME;
done
