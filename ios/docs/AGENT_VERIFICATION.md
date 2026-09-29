# iOS verification

**The user runs builds and tests himself.** Do not run the build or test wrapper unless the user asks for a build or test in this conversation; see "Builds and tests" in the root [AGENTS.md](../../AGENTS.md), including its exception for when no other agent needs the Mac. This guide covers how to run them when asked. Run from the repository root.

**iOS Builds:**
- For fast Swift lint checks, run `swiftlint --quiet`.
- Run the build wrapper only when the user asks for a build. Otherwise use `swiftlint --quiet` and reading the code, and say in the handoff that you did not build.
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
- During active debugging sessions where the user is already rebuilding in Xcode or on device/simulator after each turn, do not auto-run the build wrapper for every small change.
- In that mode, skip build execution when the change is narrow and you are confident it does not introduce compile failures; report that you intentionally skipped the build so the user can validate in their normal loop.

**iOS Tests:**
- When running iOS tests from the terminal, always run:

```bash
./scripts/xcode-test-agent.sh
```

- Do NOT run `xcodebuild test` directly.
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
- During active debugging sessions where the user is already rebuilding/rerunning manually after each turn, do not auto-run tests for every small change.
- In that mode, skip test execution when the change is narrow and low-risk, and state that tests were intentionally skipped because the user is validating interactively.

UI test, simulator and machine-load rules are in the root [AGENTS.md](../../AGENTS.md).
