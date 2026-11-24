# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Builds and tests (read this first)

Every change is built and run before it reaches the user. Reading the code is not proof. Never hand the user a check you could run yourself.

In a thread that runs helpers (subagents or delegates), one agent builds and runs for all of them: the main agent, or one verifier it names. Every Xcode build on this Mac waits in one queue, so a build per helper makes every agent wait. A helper checks its change with `swiftlint --quiet` and the backend tests, commits, and reports what it left unchecked. It runs no Xcode wrapper or simulator unless its brief says so. The main agent brings the helpers' commits together one helper at a time, builds and tests once, drives the simulator, and sends each finding to the helper that owns that code.

- Use the wrappers only, never raw `xcodebuild`. They compile through one machine-wide queue that `ios-agent`, the controller for this Mac, owns for every repo. It is first come, first served, so parallel agents wait their turn instead of colliding. A test run does not wait in that queue, so one agent tests while another compiles. `ios-agent status` lists who is building, who waits and who holds each simulator. If a run prints `queued for build: position 2 of 3; running now: Paeonia/t3-1a2b3c build since 14:02:10` or `[lock] waiting.`, wait. Do not kill the other run. If a tool timeout ends your waiting run, start it again within 15 minutes and it rejoins the queue at its old place. A build or phone test run that holds its queue for more than 30 minutes while others wait is stopped and exits 124.
- Before a wrapper run, run `scripts/app-typecheck`. It checks the app files your worktree changed against the whole app in about 15 seconds, outside the queue, so a compile error costs seconds instead of a trip through the queue. It needs one earlier wrapper run in the worktree. `--all` checks every app file in about 75 seconds, which a changed signature needs, because the default reports errors only in the files you changed.
- Run a wrapper in the foreground with a 600000 ms timeout. That is how you wait for a long run, so do not write `sleep` loops to poll one. The wrapper's last line is a summary such as `SUMMARY: SUCCESS queued=312s compiled=95s tested=140s simulator="Shared iPhone 2"`, where `queued` is the time it waited for other agents and for a simulator to boot.
- Run the smallest set of tests that proves the change, filtered with `-only-testing:<Target>/<Class>` where possible. The test wrapper builds the app itself, so do not run the build wrapper first.
- Run UI tests (`TidexAppUITests`) when the change alters a journey they walk. Unfiltered runs skip them, so name the class with `-only-testing:TidexAppUITests/<Class>`.
- A test that runs for more than five minutes fails, so a hung test cannot hold a simulator. Give a test that needs longer its own `executionTimeAllowance`, as `testAppStoreScreenshots` has.
- UI journeys using the `app-store-screenshots` fixture require a shared simulator because the fixture is disabled on physical devices. Run them separately from device unit tests with `XCODE_TEST_AGENT_DESTINATION` unset.
- Let the wrapper select the approved spare for audited device-safe test selections, with a shared simulator as fallback. [docs/agent-guides/simulators-and-locks.md](docs/agent-guides/simulators-and-locks.md) says how (always acquire simulators through `scripts/lock`, close T3 `device_close` before release, and never download simulator runtimes). Do not open Simulator.app.
- The lock does not see the Xcode app. If a run fails with `build.db: database is locked`, Hjalmar is probably building in Xcode. Wait a minute and retry.
- Compiles queue machine-wide with six jobs and lower CPU priority by default. `XCODE_AGENT_NICE`, `XCODE_AGENT_JOBS` and `IOS_AGENT_SIMULATORS` are for the user to set.
- Write a test only when [Tests](#tests) calls for one, and run it.
- **Handoff.** Name the builds and tests you ran and their results. List only the checks you could not run, such as a feature the simulator lacks, and say why.

## Topic guides

Read the relevant guide before changing code or infrastructure in these areas:

| Area | Guide |
|---|---|
| Shared simulators, `scripts/lock`, spare device eligibility, simulator rules | [docs/agent-guides/simulators-and-locks.md](docs/agent-guides/simulators-and-locks.md) |
| `one-s` SSH/Docker access, production/dev Convex, APNs, retained Supabase Edge Functions, SQL migrations & cron jobs | [docs/agent-guides/backend-and-supabase-ops.md](docs/agent-guides/backend-and-supabase-ops.md) |
| App Store Connect (`asc` CLI, credentials) and forked `../Chat` Swift package local/remote switching | [docs/agent-guides/chat-and-asc.md](docs/agent-guides/chat-and-asc.md) |
| Prose rules for docs, comments, release notes, and user-facing copy | [docs/agent-guides/writing-style.md](docs/agent-guides/writing-style.md) |

## Tests

Most of the test weight sits on end-to-end and integration tests that walk real user journeys and the backend contract. Unit tests are a thin layer for pure logic. Tests an agent writes for its own change mostly restate its own reading of the task, so they cost time and catch little.

**When to add a test.** Add or extend a test when the user asks for one, or when a change touches one of the unit-test areas listed below and no existing test would go red if the change were reverted. A bug fix in those areas gets a test that reproduces the bug. Every other change ships with the tests that already exist, and the handoff says so in one line.

**Which kind.** Pick the first kind that can see the behavior:

1. An end-to-end UI test in `ios/TidexAppUITests/` that walks a journey through the real app, such as `ShiftJourneyUITests`.
2. An integration test in `ios/TidexAppTests/` that drives real collaborators together: the in-memory `LocalStore`, repositories, the sync merge, view models with only the network edge faked. `SyncOfflineBehaviorTests` and `FriendsMessageOutboxTests` are examples.
3. A backend test next to the edge function in `supabase/functions/` for handlers and payload contracts, or a SQL script in `supabase/tests/` for RLS.
4. A unit test, for pure logic where a bug costs money, data or privacy and is hard to see on screen:
   - parsers and decoders for server, calendar (ICS) and file formats
   - date, time zone, pay period, cross-midnight and DST math
   - pay, overtime, tax, supplement and currency rules
   - security and authorization checks: who sees whose shifts, earnings and messages, user isolation, admin gating, auth routing
   - sync, merge, conflict, outbox and dedup logic

A test earns its place by checking an outcome a user would notice. Assertions on constants, enum raw values, mapping tables copied from the code, localized copy, mock call counts, layout, focus, gesture thresholds or animation restate the implementation, so leave those out.

**Failing tests.** A red test means the code or the test has a bug. Fix the code, or stop and report the failure with its output. Never delete, skip or loosen a failing test to get a green run, and never add `XCTSkip` or `XCTExpectFailure` for that purpose. Delete a test only when the user asks, or when the behavior it checks was removed on purpose.

## Project Overview

A monorepo for the Tidex iOS app and its supporting infrastructure.

Tidex is now an iOS-only product, and it has been free since 2026-09-28. The paywall and the Apple subscriptions are gone, so don't add purchase, entitlement or StoreKit code. The repository still includes supporting public/legal web surfaces and the shared backend. The `app.tidex.no` compatibility host was retired on 2026-11-08.

- **marketing/** - Next.js 16 public website for `tidex.no`
- **ios/** - Native iOS application

The iOS app uses Convex in `backend/` and Clerk authentication. The production cutover and manual release of 3.1.0 took place on 2026-10-29. Before migration or retirement work, read the [live cutover checkpoint](docs/convex-cutover-checklist.md#current-checkpoint-2026-10-29).

Supabase retains only Postgres, GoTrue and Envoy on `one-s` for source data and legacy session refresh. The other nine services were removed on 2026-10-29. Before changing that bridge, read [the aftercare record](docs/convex-aftercare.md). Public API writes and Supabase cron jobs are disabled. Caddy routes saved calendar URLs on `api.tidex.no` and `identity.tidex.no` to Convex. The former `mdr` host and hosted Supabase project are retired.

## Repository Structure

```
tidex/
├── marketing/      # Marketing static site (tidex.no)
├── ios/            # Native iOS application (see ios/AGENTS.md)
├── backend/        # Production Convex backend
├── supabase/       # Retained source data and legacy GoTrue refresh
└── docs/           # Shared documentation
```

## Developer Info

- **Primary developer user ID**: `032d8c2a-9af6-4777-99f0-24e2c4058bf3` (Hjalmar's account for testing/debugging)

## Available Skills

Use these skills for specialized tasks:

- `ios-whats-new` - App Store release notes and metadata updates
- `supabase-postgres-best-practices` - Postgres performance and RLS guidance

## iOS guidance

For native work, follow [ios/AGENTS.md](ios/AGENTS.md). Read [localization](ios/docs/AGENT_LOCALIZATION.md) when changing UI strings or catalogs and [verification](ios/docs/AGENT_VERIFICATION.md) when building or testing.

## Release checks

[RELEASE_CHECKS.md](RELEASE_CHECKS.md) lists things to try on a device before the next App Store or TestFlight release. When the user asks for release work (App Store submission, TestFlight build, version tag), show them the open items first and ask whether they have checked them. After the release ships, delete the items and keep the empty file. When a change needs a manual device check that the tests can't cover, add it there.

## Agent Behavior Guidelines

**Parallel agent safety:**

- The developer often runs multiple agents in parallel in the same worktree.
- If you see unrelated changes, do not touch, revert, reformat, or "clean up" them.
- Treat unrelated diffs as owned by the user or another agent, even if they appeared after your work began.
- Only modify files and hunks required for your task. If unrelated changes block you, start a fresh worktree off `main` and do the task there.
- Never run `git stash`, `git reset`, `git checkout -- <path>` or `git clean` in the shared worktree. Other agents stage whole files, so check your own hunks with `git diff -- <file>` and `git diff --cached -- <file>`.
- A warning or compile error the user pastes may come from another agent's edit. Check `git diff` for the file before you fix it.

**Shell notes (macOS, zsh):**

- Always give `rg` a path (`rg pattern ios`). Without one it can wait on stdin until the 120 s timeout.
- Quote globs (`rg -g '*.swift'`). zsh fails an unmatched `--include=*.ts` with "no matches found".
- Tools are BSD: `sed -i ''`, no `cat -A`. `fd`, PIL and ImageMagick are not installed.
- On `one-s`, add `</dev/null` or `-T` when `docker compose exec` should not read your stdin, and don't `pkill -f` a pattern that also matches your own ssh command.

**Commits.** Commit on your own branch in your own worktree off `main`. Deploys wait until Hjalmar asks for them. A push to `main` is a deploy: the Cloudflare Pages project `tidex` builds `tidex.no` from committed `main` (root dir `marketing`) and overwrites any direct upload made with `bun run pages:deploy:marketing`. Keep the root `prepare` script as `husky || true`, because Pages runs its own `npm install` at the repo root and fails without husky.

**Old app builds.** Endpoints that regular users call must keep working for older iOS builds still in use. Admin functions and admin screens need no such compatibility, because the admins always run the latest build, so change or drop admin fields freely.

**App Review demo account.** The Apple App Review account has the jobs "Harbor Café" and "City Library" in `$` on a Norwegian device. That is demo data on purpose. Leave the account out of production data audits and cleanups, and change its data only when Hjalmar asks.

**Commits must always be signed** - never disable commit signing. If signing fails, stop and report the signing failure instead of creating an unsigned commit.

**Legal policy updates:**

- When changing the Terms of Service or Privacy Policy copy, always update the canonical client-facing version references in the same change.
- Bump the relevant dates/timestamps in:
  - `marketing/lib/i18n/dictionaries/legal.en.ts`
  - `marketing/lib/i18n/dictionaries/legal.no.ts`
  - `marketing/public/legal/version.json`
  - `marketing/public/en/version.json`
  - `marketing/public/no/version.json`
- Do not update `ios/TidexApp/App/TermsVersion.swift` fallback version reference as part of normal legal copy changes; it is only a placeholder for API failure scenarios and should not be treated as the canonical legal version.
- This is required so every client surface, including iOS re-acceptance checks and localized public pages, picks up the new legal version from the shared public manifests.
- A manifest bump makes every iOS user accept the policy again on next launch. For an edit that only discloses existing processing or follows a product change, ask Hjalmar whether to bump the manifests or only `lastUpdatedDate`. The Terms page date (2026-09-30) is newer than `termsVersionDate` (2026-05-30) on purpose, so leave that gap alone.

Run commands from the repository root unless explicitly stated otherwise.

When running verification or diagnostic commands, prefer flags that reduce non-actionable output and preserve useful diagnostics. Examples: use `swiftlint --quiet` for fast Swift checks, use `--json` on repository build/test wrappers when you need structured diagnostics, and use focused test filters where possible. Avoid verbose command modes unless the extra output is needed to debug the issue.

## Writing style

Before writing or editing docs, comments, release notes, or user-facing copy, read [docs/agent-guides/writing-style.md](docs/agent-guides/writing-style.md) and cut AI tells from all prose.
