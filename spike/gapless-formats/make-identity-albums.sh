#!/bin/bash
# Build per-format albums whose parts are DISTINCT non-harmonic tones.
#
# The existing "Gapless 4-Track *" albums are one continuous tone split into parts: perfect for
# proving frame continuity, useless for proving audible ORDER, because every part sounds identical.
# These albums answer the other question — which track was actually heard, and in what order — by
# giving each part its own tone.
#
# Frequencies are deliberately non-harmonic (no ratio near an integer) so a harmonic of one part can
# never be misread as another part. That mistake produced a false result once already.
#
# Usage: spike/gapless-formats/make-identity-albums.sh
set -euo pipefail

MEDIA="${VIBRDROME_TEST_MEDIA:-$HOME/vibrdrome-test-media}"
TONES=(233 379 611 977)
DURATION=0.4          # seconds per part — long enough to identify, short enough for fast tests
RATE=44100

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 2; }

# $1 = album dir name, $2 = extension, rest = ffmpeg encode args
encode_album() {
  local name="$1"; shift
  local ext="$1"; shift
  local dir="$MEDIA/$name"
  rm -rf "$dir"; mkdir -p "$dir"
  local i=1
  for tone in "${TONES[@]}"; do
    ffmpeg -y -hide_banner -loglevel error \
      -f lavfi -i "sine=frequency=$tone:duration=$DURATION:sample_rate=$RATE" \
      -af "volume=0.5" "$@" "$(printf '%s/%02d - Tone %d.%s' "$dir" "$i" "$tone" "$ext")"
    i=$((i + 1))
  done
  echo "  $dir"
}

echo "building identity albums (distinct tone per part) in $MEDIA"
encode_album "Identity FLAC"  flac -c:a flac
encode_album "Identity ALAC"  m4a  -c:a alac
encode_album "Identity AAC"   m4a  -c:a aac -b:a 192k
encode_album "Identity Opus"  opus -c:a libopus -b:a 192k

# MP3 written to a seekable file keeps its Xing/LAME gapless header, so it is trimmable.
encode_album "Identity MP3 CBR"   mp3 -c:a libmp3lame -b:a 320k
encode_album "Identity MP3 VBR"   mp3 -c:a libmp3lame -q:a 2
encode_album "Identity MP3 Mono"  mp3 -c:a libmp3lame -b:a 192k -ac 1
# MPEG-2 layer III: half sample rate forces the MPEG-2 side-info layout, which is the case a
# single-layout header parser gets wrong.
dir="$MEDIA/Identity MP3 MPEG2"; rm -rf "$dir"; mkdir -p "$dir"
i=1
for tone in "${TONES[@]}"; do
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "sine=frequency=$tone:duration=$DURATION:sample_rate=22050" \
    -af "volume=0.5" -c:a libmp3lame -b:a 96k \
    "$(printf '%s/%02d - Tone %d.mp3' "$dir" "$i" "$tone")"
  i=$((i + 1))
done
echo "  $dir"

# MP3 through a pipe: the encoder cannot seek back to write its gapless header, so these are the
# not-trimmable case.
dir="$MEDIA/Identity MP3 NoMetadata"; rm -rf "$dir"; mkdir -p "$dir"
i=1
for tone in "${TONES[@]}"; do
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "sine=frequency=$tone:duration=$DURATION:sample_rate=$RATE" \
    -af "volume=0.5" -c:a libmp3lame -b:a 320k -f mp3 pipe:1 \
    > "$(printf '%s/%02d - Tone %d.mp3' "$dir" "$i" "$tone")"
  i=$((i + 1))
done
echo "  $dir"

echo "done."
