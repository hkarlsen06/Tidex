# iOS verification

Run from the repository root. Complete focused verification and fix failures caused by the change. Ask the user for final device/Xcode checks only when tooling is unavailable, a device-only check is needed, or the user is already validating interactively. Lint alone does not establish compilation correctness.

**iOS Builds:**
- For fast Swift lint checks, run `swiftlint --quiet`.
- Prefer not to run full iOS builds for small, focused changes. Use `swiftlint --quiet` and targeted inspection by default, then report when a build was intentionally skipped.
- Run the build wrapper when the user explicitly asks for a build, when the change is broad or risky enough that lint is insufficient, or when you know you are working autonomously on a longer task and should verify end-to-end before handing back.
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
