# Tidex showcase video

Remotion project that renders the Tidex showcase in four cuts.

| Composition | Size | Length | Use |
| --- | --- | --- | --- |
| `Social-en`, `Social-no` | 1080 x 1920 | 28 s | Reels, TikTok, Shorts |
| `AppStore-en`, `AppStore-no` | 886 x 1920 | 24 s | App Store app preview for 6.1" to 6.9" iPhones |

## Commands

Run these from `video/`.

- `npm i` installs dependencies.
- `npm run dev` opens Remotion Studio.
- `npm run export` renders every cut to `out/Tidex-<composition>.mp4`. Pass ids to render a subset, for example `npm run export -- AppStore-en`.
- `npm run audio` regenerates the music bed and sound effects in `public/audio/`. The script synthesizes all audio, so there is nothing to license.

## Showreel

`reel/` holds a separate 15-second 1080 x 1920 showreel at 60 fps that does not use Remotion. `reel/reel.py` draws every frame with skia-python, synthesizes the soundtrack with numpy and writes `out/Tidex-Reel.mp4`. It needs `uv` and `ffmpeg`, and it downloads Manrope and JetBrains Mono into `out/reel/fonts/` on the first run. Run these from the repository root:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python video/reel/icon3d.py
uv run video/reel/reel.py
```

`icon3d.py` renders the glass icon for the end card into `out/reel/icon/`. It takes about 12 minutes on an M3 Pro, plus about 7 minutes of one-time Metal shader compilation on the first run. Without those frames the reel uses the flat app icon. `uv run video/reel/reel.py --still 1.5 6.2` writes single frames and a contact sheet, and `--check` runs the self-checks.

## Footage

The app footage is a screen recording of the `testAppStoreScreenshots` UI test running on the offline App Store fixture, on an iPhone 17 Pro Max simulator. `public/footage/en.mp4` and `public/footage/no.mp4` are the English and Norwegian halves of that recording at 30 fps. `public/stills/` holds full-resolution frames from the same recording for the lift-out crops.

`SCENES` in `src/config.ts` refers to frame numbers in those clips. After a new recording, check each scene's `pieces`, `taps` and lift timings against the new clips before rendering.

To record again, from the repository root:

```bash
UDID=<simulator udid>
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl io "$UDID" recordVideo --codec=h264 walkthrough.mp4 &
XCODE_TEST_AGENT_DESTINATION="platform=iOS Simulator,id=$UDID" ./scripts/xcode-test-agent.sh -- \
  -only-testing:TidexAppUITests/TidexAppUITests/testAppStoreScreenshots
kill -INT %1
```

Cut each language out of the recording with `setpts=PTS-STARTPTS`. Without it the clip starts at a non-zero timestamp and every trim lands on the wrong frame.

```bash
ffmpeg -ss <start> -to <end> -i walkthrough.mp4 -vf "fps=30,setpts=PTS-STARTPTS,scale=900:-2" \
  -c:v libx264 -crf 14 -bf 0 -g 15 -an video/public/footage/en.mp4
```

## App Store notes

- The App Store cuts show only app screen captures, captions, touch indicators and crossfades. They end with the account and purchase disclaimer that Apple asks previews to show.
- Export writes H.264 High@4.0 at 11 Mbps with 256 kbps AAC stereo at 48 kHz, which is Apple's app preview specification.
- All data comes from the fictional fixture account. Dates in the footage follow the day it was recorded.
