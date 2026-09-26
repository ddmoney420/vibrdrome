#!/bin/bash
# Build the per-format gapless test albums used by GaplessRealAlbumTests.
#
# Source of truth is the existing FLAC album (~/vibrdrome-test-media/Gapless 4-Track Test): one
# continuous tone split into 4 sample-exact 441000-frame parts. Each part is re-encoded
# INDEPENDENTLY into every delivery format, which is how a server stores tracks and how Navidrome
# transcodes them -- so codec priming/padding lands on every join, exactly as in production.
#
# Usage: spike/gapless-formats/make-test-albums.sh
set -euo pipefail

MEDIA="${VIBRDROME_TEST_MEDIA:-$HOME/vibrdrome-test-media}"
SOURCE="$MEDIA/Gapless 4-Track Test"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found (brew install ffmpeg)" >&2
  exit 2
fi
if [ ! -d "$SOURCE" ]; then
  echo "source album not found: $SOURCE" >&2
  exit 2
fi

encode_album() {
  local name="$1"; shift
  local ext="$1"; shift
  local dir="$MEDIA/$name"
  mkdir -p "$dir"
  local i=1
  for src in "$SOURCE"/*.flac; do
    ffmpeg -y -hide_banner -loglevel error -i "$src" "$@" \
      "$dir/$(printf '%02d' $i) - Part $i.$ext"
    i=$((i + 1))
  done
  echo "  wrote $dir"
}

echo "building gapless test albums from: $SOURCE"
encode_album "Gapless 4-Track MP3" mp3 -c:a libmp3lame -b:a 320k
encode_album "Gapless 4-Track AAC" m4a -c:a aac -b:a 256k
encode_album "Gapless 4-Track Opus" opus -c:a libopus -b:a 192k

# A live server-side transcode writes to a non-seekable stream, so the encoder can never go back and
# fill in its Xing/LAME gapless header. Reproduced here with a pipe -- this album is the
# worst-case source, and is expected to be the one format that cannot be trimmed exactly.
dir="$MEDIA/Gapless 4-Track Transcoded MP3"
mkdir -p "$dir"
i=1
for src in "$SOURCE"/*.flac; do
  ffmpeg -y -hide_banner -loglevel error -i "$src" -c:a libmp3lame -b:a 320k -f mp3 pipe:1 \
    > "$dir/$(printf '%02d' $i) - Part $i.mp3"
  i=$((i + 1))
done
echo "  wrote $dir"

echo "done."
