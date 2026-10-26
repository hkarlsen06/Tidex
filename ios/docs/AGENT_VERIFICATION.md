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
- The wrapper runs in two phases. It builds for testing under the machine-wide xcodebuild lock and releases it. Then it tests under one shared simulator's lock: the one your worktree holds, else the first free one. Set `XCODE_TEST_AGENT_DESTINATION` only for a connected device, as the root [AGENTS.md](../../AGENTS.md#devices-and-simulators) describes.
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
  - The last line is a summary, for example `SUMMARY: SUCCESS queued=312s compiled=95s tested=140s simulator="Shared iPhone 2"`. `queued` is the time spent waiting for the xcodebuild lock, a simulator and its boot. `--json` puts the same fields in the JSON.

UI test, simulator and machine-load rules are in the root [AGENTS.md](../../AGENTS.md).

## Screens without signing in

`ios/TidexApp/Storage/Testing/DesignReviewView.swift` renders real components with fixture data, so a screen can be checked in the simulator without an account. Take a simulator first, as the root [AGENTS.md](../../AGENTS.md#devices-and-simulators) describes, and find the screen names in the `case` labels of that file (`login`, `settings`, `money`, `calendar`, `shift-editor` and others).

- Launch a screen with `SIMCTL_CHILD_TIDEX_UI_TEST_SCENARIO=design-review SIMCTL_CHILD_TIDEX_DESIGN_SCREEN=<screen> xcrun simctl launch <udid> no.tidex.app -ui-testing`.
- The app ignores `simctl ui appearance`, because `AppearanceManager` applies the cached `cachedTheme` value. Add the launch arguments `-cachedTheme dark` or `-cachedTheme light` to force a theme.
- Set the text size with `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`, and reset it with `large`.
- To dump the accessibility tree with the T3 `agent-device snapshot` command, open the app with `agent-device open no.tidex.app --relaunch --launch-args -ui-testing`. That command can't pass environment variables, so set them first with `xcrun simctl spawn <udid> launchctl setenv TIDEX_UI_TEST_SCENARIO design-review` (and the same for `TIDEX_DESIGN_SCREEN`), and unset them afterwards. In zsh, split a flags variable with `${=F}`, or the tool reports "Call device_open first".
- The build wrapper puts the app in `~/Library/Developer/Xcode/DerivedData/Tidex-<hash>/Build/Products/Debug-iphonesimulator/Tidex.app`. Match the hash to your worktree with `plutil -extract WorkspacePath raw <dir>/info.plist`.
