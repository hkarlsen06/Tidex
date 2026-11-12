# iOS verification

Agents run builds and tests themselves through the wrappers below. "Builds and tests" in the root [AGENTS.md](../../AGENTS.md) says when and where. Run from the repository root.

**iOS Builds:**
- For fast Swift lint checks, run `swiftlint --quiet`.
- When building the iOS app, always run:

```bash
./scripts/xcode-build-agent.sh
```

- Do NOT run `xcodebuild` directly.
- JSON output is available with:

```bash
./scripts/xcode-build-agent.sh --json
```

- Interpretation rules:
  - Exit code `0` + `STATUS: SUCCESS` -> build succeeded
  - Non-zero exit code or `STATUS: FAILURE` -> build failed
  - If present, read the `WARNINGS` and `ERRORS` sections for diagnostics

**iOS Tests:**
- When running iOS tests from the terminal, always run:

```bash
./scripts/xcode-test-agent.sh
```

- Do NOT run `xcodebuild test` directly.
- The wrapper runs in two phases. It builds for the destination platform in the machine-wide build queue that `ios-agent` owns. Then it tests under one shared simulator's lock: the one your worktree holds, else the first free one. A physical destination builds iOS device products and takes no simulator lock. Test runs on the same phone wait for each other in `ios-agent`. Normally set `XCODE_TEST_AGENT_DESTINATION` for a connected device, as the root [AGENTS.md](../../AGENTS.md#devices-and-simulators) describes. The wrapper also accepts explicit simulator IDs. Use that path for a user-authorized target outside the shared pool, such as Duo, and keep exclusive ownership of it during the run. The wrapper does not lock simulators outside the pool.
- UI journeys that use `app-store-screenshots` require a shared simulator. `AppStoreScreenshotFixture` is disabled on physical devices, where those journeys remain at their fixture's startup spinner. Run the unit tests on the connected device and these UI journeys separately with `XCODE_TEST_AGENT_DESTINATION` unset.
- Before each run on a simulator, the wrapper uninstalls Tidex there, because a leftover Live Activity makes the system relaunch the app right after install. xcodebuild then attaches to that launch without the test bundle, and the run fails with "test runner hung before establishing connection" or "failed to launch no.tidex.app". On a shared simulator the reset runs under that simulator's lock. If a run fails that way, run it again through the wrapper. To uninstall the app with `xcrun simctl` yourself, take a simulator first, as the root [AGENTS.md](../../AGENTS.md#devices-and-simulators) describes.
- On a physical device, the wrapper skips the reset, because uninstalling there deletes the user's data.
- JSON output is available with:

```bash
./scripts/xcode-test-agent.sh --json
```

- Pass focused test flags through to `xcodebuild test`, for example:

```bash
./scripts/xcode-test-agent.sh -- -only-testing:TidexAppTests/FriendsMessagesRepositoryTests
```

- Interpretation rules:
  - Exit code `0` + `STATUS: SUCCESS` -> tests passed
  - Non-zero exit code or `STATUS: FAILURE` -> tests failed
  - If present, read the `TESTS`, `WARNINGS`, `ERRORS`, and `test_failures` diagnostics
  - The last line is a summary, for example `SUMMARY: SUCCESS queued=312s compiled=95s tested=140s simulator="Shared iPhone 2"`. `queued` is the time spent waiting in the build queue, for a simulator or phone, and for a simulator to boot. `--json` puts the same fields in the JSON.

UI test, simulator and machine-load rules are in the root [AGENTS.md](../../AGENTS.md).

## Screens without signing in

`ios/TidexApp/Storage/Testing/DesignReviewView.swift` renders real components with fixture data, so a screen can be checked in the simulator without an account. Take a simulator first, as the root [AGENTS.md](../../AGENTS.md#devices-and-simulators) describes, and find the screen names in the `case` labels of that file (`login`, `settings`, `money`, `calendar`, `shift-editor` and others).

- Launch a screen with `SIMCTL_CHILD_TIDEX_UI_TEST_SCENARIO=design-review SIMCTL_CHILD_TIDEX_DESIGN_SCREEN=<screen> xcrun simctl launch <udid> no.tidex.app -ui-testing`.
- The app ignores `simctl ui appearance`, because `AppearanceManager` applies the cached `cachedTheme` value. Add the launch arguments `-cachedTheme dark` or `-cachedTheme light` to force a theme.
- Set the text size with `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`, and reset it with `large`.
- To dump the accessibility tree with the T3 `agent-device snapshot` command, open the app with `agent-device open no.tidex.app --relaunch --launch-args -ui-testing`. That command can't pass environment variables, so set them first with `xcrun simctl spawn <udid> launchctl setenv TIDEX_UI_TEST_SCENARIO design-review` (and the same for `TIDEX_DESIGN_SCREEN`), and unset them afterwards. In zsh, split a flags variable with `${=F}`, or the tool reports "Call device_open first".
- The build wrapper puts the app in `~/Library/Developer/Xcode/DerivedData/Tidex-<hash>/Build/Products/Debug-iphonesimulator/Tidex.app`. Match the hash to your worktree with `plutil -extract WorkspacePath raw <dir>/info.plist`.

## Motion

An agent cannot watch an animation, so `scripts/motion-check` turns one into numbers and a still image. Use it after you change an animation, a transition or a gesture hand-off, such as a drag that ends in a spring.

1. Add `.motionProbe("name", value)` beside the modifier that the value drives, for example next to `.offset(x: offset)`. Each moving thing needs its own name. The app already has four probes: `payroll-progress` (the payroll card's progress bar), `month-card` (the calendar's month slide), `reply-swipe` (the chat reply swipe) and `stats-playhead` (the band that marks the focus month in the Stats year rows). The probe records only in Debug builds launched with `-motion-probe`, and Release builds compile it to nothing.
2. Build with `./scripts/xcode-build-agent.sh`, take a simulator with `SIM="$(scripts/lock acquire simulator)"`, and install the app with `xcrun simctl install "$SIM" <path to Tidex.app>`. "Screens without signing in" above says where the build puts the app.
3. Set the scenario with `xcrun simctl spawn "$SIM" launchctl setenv TIDEX_UI_TEST_SCENARIO <scenario>`, as "Screens without signing in" describes. `app-store-screenshots` shows the dashboard and calendar with fixture data, and `friends-chat-reply` opens a chat thread. Then call the T3 `device_open` tool and run `agent-device open no.tidex.app --relaunch --launch-args -ui-testing --launch-args -motion-probe`. The flag `--launch-args` takes one argument, so repeat it. Each launch starts a new log.
4. Start a recording with `agent-device record start --hide-touches <file>.mp4`, trigger the animation, and stop with `agent-device record stop`. `agent-device press 'label="<label>"' --count 2 --interval-ms 150` taps twice to interrupt an animation, and `agent-device gesture pan <x> <y> <dx> <dy> <ms>` drags.
5. Run `scripts/motion-check report`. It reads the log from the simulator your worktree holds and prints one line per animation. Add `--name <prefix>` to see one probe.
6. Read the result. The last line is `SUMMARY: PASS` or `SUMMARY: FAIL`, and the exit code is 0, 1, or 2 for a usage or tool error.
   - `SNAP` means the value moved far in one frame, or was set with no animation.
   - `JUMP` means the speed changed in one frame. "When the animation took over from the finger" means a release animation ignored the finger's speed.
   - `JITTER` means the speed went up and down on consecutive frames.
   - `STALL` means frames with no new value, and `PACING` means uneven frames right after one. Both depend on machine load and never fail the report. A stall on a simulator does not predict a phone.
   - `settled` is when the value came within 1% of its end, which is when the eye sees it stop. `duration` includes a spring's long tail.
   - Spring overshoot is normal up to about 0.6% at damping 0.85, 1.5% at 0.8 and 16% at 0.5.
7. Fix each snap, jump or jitter run, or declare it. Some are by design: the month slide sets its cards to an offset of 60 with no animation and then slides them in. Pass `--allow <name>=<count>` for the breaks each episode may have, `--end <name>=<value>` for where the value must end, and `--max-duration <name>=<seconds>` for how long it may take to settle. Name every allowed break in the handoff and say why it is intended.
8. For motion the probe cannot see, add `--video <file>.mp4 --row 0.5` for horizontal motion or `--column 0.5` for vertical motion, and open the PNG it prints with the Read tool. The image stacks one pixel row or column per frame, so a sliding edge draws its own curve. The script picks the stretch of the recording where the screen changed.

The probe logs the values SwiftUI computed for one number. It cannot see navigation pushes, sheets, tab switches, or views that a transition inserts or removes, so use the image for those. It does not judge whether a curve feels right.

When you are done, close the device session with `device_close`, release the simulator with `scripts/lock release simulator`, and unset the scenario variables. `python3 scripts/test-motion-check.py` checks the script itself.
