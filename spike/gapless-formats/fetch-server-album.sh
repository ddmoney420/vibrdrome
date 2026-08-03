#!/bin/bash
# Fetch the gapless test album AS THE SERVER DELIVERS IT, so boundary continuity can be measured on
# real server-transcoded bytes rather than on a local re-encode that only imitates them.
#
# Writes to ~/vibrdrome-test-media/Server MP3 Transcode/ and Server Opus Transcode/.
# Credentials come from the app's preferences and your Keychain; nothing sensitive is printed.
#
# Usage: spike/gapless-formats/fetch-server-album.sh ["Album Name"]
set -uo pipefail

ALBUM_NAME="${1:-Gapless 4-Track Test}"
MEDIA="${VIBRDROME_TEST_MEDIA:-$HOME/vibrdrome-test-media}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 2; }; }
need curl; need md5

SERVER="$(defaults read com.vibrdrome.app serverURL 2>/dev/null)"
USERNAME="$(defaults read com.vibrdrome.app username 2>/dev/null)"
PASSWORD="$(security find-generic-password -s com.vibrdrome -a serverPassword -w 2>/dev/null)"
if [ -z "${PASSWORD:-}" ]; then
  ACTIVE="$(defaults read com.vibrdrome.app activeServerId 2>/dev/null || true)"
  [ -n "${ACTIVE:-}" ] && PASSWORD="$(security find-generic-password -s com.vibrdrome -a "server_$ACTIVE" -w 2>/dev/null)"
fi
if [ -z "${SERVER:-}" ] || [ -z "${USERNAME:-}" ] || [ -z "${PASSWORD:-}" ]; then
  echo "Could not read server settings / Keychain password." >&2
  exit 2
fi

auth_params() {
  local salt token
  salt="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 12)"
  token="$(printf '%s%s' "$PASSWORD" "$salt" | md5 -q)"
  printf 'u=%s&t=%s&s=%s&v=1.16.1&c=vibrdrome&f=json' "$USERNAME" "$token" "$salt"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "locating album: $ALBUM_NAME"
curl -sS --max-time 30 --get \
  --data-urlencode "query=$ALBUM_NAME" \
  "$SERVER/rest/search3?$(auth_params)&albumCount=5&artistCount=0&songCount=0" -o "$WORK/album.json"

ALBUM_ID="$(/usr/bin/python3 -c '
import json,sys
name=sys.argv[2].lower()
try:
    albums=json.load(open(sys.argv[1]))["subsonic-response"]["searchResult3"]["album"]
except Exception:
    albums=[]
for a in albums:
    if a.get("name","").lower()==name: print(a["id"]); break
else:
    print(albums[0]["id"] if albums else "")
' "$WORK/album.json" "$ALBUM_NAME")"

if [ -z "$ALBUM_ID" ]; then
  echo "album not found on server: $ALBUM_NAME" >&2
  exit 1
fi

curl -sS --max-time 30 "$SERVER/rest/getAlbum?$(auth_params)&id=$ALBUM_ID" -o "$WORK/tracks.json"
# macOS ships bash 3.2, which has no `mapfile` — read the ids with a portable loop.
TRACK_IDS=()
while IFS= read -r line; do
  [ -n "$line" ] && TRACK_IDS+=("$line")
done < <(/usr/bin/python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))["subsonic-response"]["album"]
for s in sorted(d.get("song",[]), key=lambda s: s.get("track",0)):
    print(s["id"])
' "$WORK/tracks.json")

if [ "${#TRACK_IDS[@]}" -eq 0 ]; then
  echo "no tracks found in album" >&2
  exit 1
fi
echo "found ${#TRACK_IDS[@]} tracks (ids withheld)"

fetch_format() {
  local fmt="$1" ext="$2" dir="$MEDIA/Server $3"
  mkdir -p "$dir"
  local i=1
  for id in "${TRACK_IDS[@]}"; do
    local out
    out="$(printf '%s/%02d - Part %d.%s' "$dir" "$i" "$i" "$ext")"
    curl -sS --max-time 180 \
      "$SERVER/rest/stream?$(auth_params)&id=$id&maxBitRate=192&format=$fmt" -o "$out"
    echo "  $(basename "$out")  $(stat -f%z "$out") bytes"
    i=$((i + 1))
  done
  echo "  -> $dir"
}

echo "fetching MP3 transcodes"
fetch_format mp3 mp3 "MP3 Transcode"
echo "fetching Opus transcodes"
fetch_format opus opus "Opus Transcode"
echo "done."
