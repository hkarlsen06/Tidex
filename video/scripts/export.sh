#!/bin/bash
# Renders every cut and encodes the delivery files into out/.
# App Store previews: 886x1920, 30 fps, H.264 High@4.0 at 11 Mbps, AAC 256 kbps, 48 kHz stereo.
# Social cuts: 1080x1920, 30 fps, H.264 High, AAC 320 kbps, -15 LUFS (platforms normalize to about -14).
# Usage: scripts/export.sh [composition ...]   (defaults to all four cuts)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out/master

cuts=("$@")
[ ${#cuts[@]} -gt 0 ] || cuts=(Social-en Social-no AppStore-en AppStore-no)
for cut in "${cuts[@]}"; do
  npx remotion render "$cut" "out/master/$cut.mp4" --codec=h264 --crf=12 \
    --audio-codec=aac --audio-bitrate=320k --color-space=bt709
  case $cut in
    Social-*) lufs=-15 abr=320k video=(-crf 16 -maxrate 20M -bufsize 40M -level:v 4.1) ;;
    # Calm footage undershoots any VBR target, so pad to a constant 11 Mbps inside Apple's 10-12 Mbps range.
    AppStore-*) lufs=-16 abr=256k video=(-b:v 11M -minrate 11M -maxrate 11M -bufsize 11M -x264-params nal-hrd=cbr -level:v 4.0) ;;
  esac
  # Two-pass loudnorm: measure, then apply linearly so the mix dynamics stay intact.
  measured=$(ffmpeg -hide_banner -nostats -i "out/master/$cut.mp4" \
    -af "loudnorm=I=$lufs:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 |
    python3 -c 'import json,re,sys; d=json.loads(re.search(r"\{[^}]*\}", sys.stdin.read()).group()); print(":".join(f"measured_{k}={d["input_"+k]}" for k in ("i","tp","lra","thresh")) + f":offset={d["target_offset"]}")')
  ffmpeg -hide_banner -loglevel error -y -i "out/master/$cut.mp4" \
    -c:v libx264 -preset slow -profile:v high "${video[@]}" -pix_fmt yuv420p -r 30 -g 60 \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
    -af "loudnorm=I=$lufs:TP=-1.5:LRA=11:$measured:linear=true,aresample=48000" \
    -c:a aac -b:a "$abr" -ar 48000 -ac 2 -movflags +faststart "out/Tidex-$cut.mp4"
  echo "wrote out/Tidex-$cut.mp4"
done
