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
- By default the wrapper runs tests on its own `Tidex Tests` simulator and creates it on first use. Agents must not use that default. Set `XCODE_TEST_AGENT_DESTINATION` to the connected device or the shared simulator, as the root [AGENTS.md](../../AGENTS.md#devices-and-simulators) describes.
- Before each run on a simulator, the wrapper uninstalls Tidex there, because a leftover Live Activity makes the system relaunch the app right after install. xcodebuild then attaches to that launch without the test bundle, and the run fails with "test runner hung before establishing connection" or "failed to launch no.tidex.app". The reset runs inside the machine-wide xcodebuild lock, for the default simulator and for a simulator that `XCODE_TEST_AGENT_DESTINATION` names. If a run fails that way, run it again through the wrapper. Do not uninstall the app with `xcrun simctl` yourself, because another agent's run may be using the simulator.
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

UI test, simulator and machine-load rules are in the root [AGENTS.md](../../AGENTS.md).
