#!/bin/bash
# Bounded capability check against the real Navidrome server: can a server-transcoded MP3 be
# trimmed for gapless, and is the Opus transcode frame-exact?
#
# Reads the server URL from the app's own preferences and the password straight from your Keychain,
# so no credential is ever passed on the command line or printed. Output is deliberately
# non-sensitive: NO auth tokens, NO salts, NO full media URLs -- only status codes, header shapes,
# and decoded audio facts.
#
# Usage: spike/gapless-formats/probe-server-transcode.sh
set -uo pipefail

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 2; }; }
need curl; need md5; need ffprobe

SERVER="$(defaults read com.vibrdrome.app serverURL 2>/dev/null)"
USERNAME="$(defaults read com.vibrdrome.app username 2>/dev/null)"
if [ -z "${SERVER:-}" ] || [ -z "${USERNAME:-}" ]; then
  echo "Could not read serverURL/username from com.vibrdrome.app preferences." >&2
  echo "Run the macOS app once, or set SERVER/USERNAME manually in this script." >&2
  exit 2
fi

PASSWORD="$(security find-generic-password -s com.vibrdrome -a serverPassword -w 2>/dev/null)"
if [ -z "${PASSWORD:-}" ]; then
  ACTIVE="$(defaults read com.vibrdrome.app activeServerId 2>/dev/null || true)"
  [ -n "${ACTIVE:-}" ] && PASSWORD="$(security find-generic-password -s com.vibrdrome -a "server_$ACTIVE" -w 2>/dev/null)"
fi
if [ -z "${PASSWORD:-}" ]; then
  echo "Could not read the server password from the Keychain (service com.vibrdrome)." >&2
  echo "macOS may have shown an access prompt -- approve it and re-run." >&2
  exit 2
fi

# Subsonic token auth: t = md5(password + salt). Salt is regenerated per request and never printed.
auth_params() {
  local salt token
  salt="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 12)"
  token="$(printf '%s%s' "$PASSWORD" "$salt" | md5 -q)"
  printf 'u=%s&t=%s&s=%s&v=1.16.1&c=vibrdrome&f=json' "$USERNAME" "$token" "$salt"
}

echo "=== Navidrome transcode capability probe ==="
echo "server: ${SERVER%%\?*}  (host only; no URLs with credentials are printed)"
echo ""

# ---------------------------------------------------------------- pick a track
echo "-- locating a test track"
SEARCH="$WORK/search.json"
curl -sS --max-time 30 "$SERVER/rest/search3?$(auth_params)&query=&songCount=1&artistCount=0&albumCount=0" -o "$SEARCH"
SONG_ID="$(/usr/bin/python3 -c '
import json,sys
try:
    d=json.load(open(sys.argv[1]))["subsonic-response"]
    print(d.get("searchResult3",{}).get("song",[{}])[0].get("id",""))
except Exception:
    print("")
' "$SEARCH")"
if [ -z "$SONG_ID" ]; then
  curl -sS --max-time 30 "$SERVER/rest/getRandomSongs?$(auth_params)&size=1" -o "$SEARCH"
  SONG_ID="$(/usr/bin/python3 -c '
import json,sys
try:
    d=json.load(open(sys.argv[1]))["subsonic-response"]
    print(d.get("randomSongs",{}).get("song",[{}])[0].get("id",""))
except Exception:
    print("")
' "$SEARCH")"
fi
if [ -z "$SONG_ID" ]; then
  echo "   FAILED to find a track (check server reachability / credentials)"
  exit 1
fi
echo "   using a track (id withheld)"
echo ""

# ---------------------------------------------------------------- MP3 transcode
probe_mp3() {
  local label="$1" out="$2" hdr="$3"
  echo "-- MP3 transcode: $label"
  echo "   HTTP status:      $(awk 'tolower($0) ~ /^http\// {s=$2} END {print s}' "$hdr")"
  local clen te ctype
  clen="$(awk 'tolower($0) ~ /^content-length:/ {print $2}' "$hdr" | tr -d '\r')"
  te="$(awk 'tolower($0) ~ /^transfer-encoding:/ {print $2}' "$hdr" | tr -d '\r')"
  ctype="$(awk 'tolower($0) ~ /^content-type:/ {print $2}' "$hdr" | tr -d '\r')"
  echo "   content-type:     ${ctype:-<none>}"
  echo "   content-length:   ${clen:-<none>}"
  echo "   transfer-encoding:${te:-<none>}"
  if [ -n "${clen:-}" ]; then
    echo "   delivery:         known length (server produced a complete response)"
  else
    echo "   delivery:         chunked / streaming (length unknown up front)"
  fi
  echo "   bytes received:   $(stat -f%z "$out")"

  # Xing/Info + LAME presence in the leading bytes (after any ID3v2 tag).
  /usr/bin/python3 - "$out" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read(262144)
off = 0
if data[:3] == b'ID3':
    size = (data[6] << 21) | (data[7] << 14) | (data[8] << 7) | data[9]
    off = 10 + size
    if data[5] & 0x10: off += 10
    print(f"   ID3v2 tag:        present ({size} bytes)")
else:
    print("   ID3v2 tag:        absent")
head = data[off:off+2048]
has_xing = b'Xing' in head
has_info = b'Info' in head
has_lame = b'LAME' in head or b'Lavc' in head or b'Lavf' in head
print(f"   Xing tag:         {'present' if has_xing else 'absent'}")
print(f"   Info tag:         {'present' if has_info else 'absent'}")
print(f"   LAME/Lavc tag:    {'present' if has_lame else 'absent'}")

delay = padding = None
if (has_xing or has_info) and len(head) > 4 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0:
    mpeg1 = ((head[1] >> 3) & 0x03) == 0x03
    mono  = ((head[3] >> 6) & 0x03) == 0x03
    side  = 17 if (mpeg1 and mono) else 32 if mpeg1 else 9 if mono else 17
    p = 4 + side
    if head[p:p+4] in (b'Xing', b'Info'):
        p += 4
        flags = int.from_bytes(head[p:p+4], 'big'); p += 4
        if flags & 0x01: p += 4
        if flags & 0x02: p += 4
        if flags & 0x04: p += 100
        if flags & 0x08: p += 4
        if head[p:p+4] in (b'LAME', b'Lavc', b'Lavf') and len(head) >= p + 24:
            b0, b1, b2 = head[p+21], head[p+22], head[p+23]
            delay = (b0 << 4) | (b1 >> 4)
            padding = ((b1 & 0x0F) << 8) | b2
if delay is not None:
    print(f"   encoder delay:    {delay}")
    print(f"   end padding:      {padding}")
    print("   TRIM CAPABLE:     YES — client can schedule an exact gapless segment")
else:
    print("   encoder delay:    not recoverable")
    print("   end padding:      not recoverable")
    print("   TRIM CAPABLE:     NO — classify as mp3WithoutGaplessMetadata")
PY
  echo ""
}

PARAMS="$(auth_params)"
curl -sS --max-time 120 -D "$WORK/mp3a.hdr" \
  "$SERVER/rest/stream?$PARAMS&id=$SONG_ID&maxBitRate=192&format=mp3" -o "$WORK/mp3a.mp3"
probe_mp3 "request 1 (maxBitRate=192, format=mp3)" "$WORK/mp3a.mp3" "$WORK/mp3a.hdr"

curl -sS --max-time 120 -D "$WORK/mp3b.hdr" \
  "$SERVER/rest/stream?$(auth_params)&id=$SONG_ID&maxBitRate=192&format=mp3" -o "$WORK/mp3b.mp3"
probe_mp3 "request 2 (identical parameters — repeatability)" "$WORK/mp3b.mp3" "$WORK/mp3b.hdr"

echo "-- repeatability"
if cmp -s "$WORK/mp3a.mp3" "$WORK/mp3b.mp3"; then
  echo "   two identical requests returned BYTE-IDENTICAL responses"
else
  echo "   two identical requests DIFFER (sizes: $(stat -f%z "$WORK/mp3a.mp3") vs $(stat -f%z "$WORK/mp3b.mp3"))"
fi
echo ""

echo "-- cached completed response (the file the gapless cache would hold)"
echo "   decoded by ffprobe:"
ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels \
  -show_entries format=duration -of default=noprint_wrappers=1 "$WORK/mp3a.mp3" | sed 's/^/     /'
echo "   (trim capability of the completed file is the same as reported above —"
echo "    caching cannot add metadata the encoder never wrote)"
echo ""

# ---------------------------------------------------------------- Opus transcode
echo "-- Opus transcode"
curl -sS --max-time 120 -D "$WORK/opus.hdr" \
  "$SERVER/rest/stream?$(auth_params)&id=$SONG_ID&maxBitRate=192&format=opus" -o "$WORK/opus.bin"
echo "   HTTP status:      $(awk 'tolower($0) ~ /^http\// {s=$2} END {print s}' "$WORK/opus.hdr")"
echo "   content-type:     $(awk 'tolower($0) ~ /^content-type:/ {print $2}' "$WORK/opus.hdr" | tr -d '\r')"
echo "   bytes received:   $(stat -f%z "$WORK/opus.bin")"
ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels,duration_ts \
  -show_entries format=format_name,duration -of default=noprint_wrappers=1 "$WORK/opus.bin" | sed 's/^/     /'
echo ""
echo "   seek support (server-side): re-request with a Range header"
RANGE_STATUS="$(curl -sS --max-time 60 -o /dev/null -D - -H 'Range: bytes=1000-2000' \
  "$SERVER/rest/stream?$(auth_params)&id=$SONG_ID&maxBitRate=192&format=opus" \
  | awk 'tolower($0) ~ /^http\// {s=$2} END {print s}')"
echo "     Range request status: ${RANGE_STATUS:-<none>}  (206 = server supports byte ranges)"
echo ""
echo "=== probe complete — no credentials or media URLs were printed ==="
