# Decision-trail audit follow-up

Checked 7 November 2026 against the retained artifacts and current Git history. This follow-up changes documentation and evidence retention. Production inspection was read-only. No app code, deployed functions or user wage snapshots changed.

The original Claude audit hit its usage limit on 6 November. T3 automatically resumed the same task on 7 November, and Claude Sonnet 5.5 completed it. The [original report](evidence/decision-trail-review.md) and [artifact manifest](evidence/manifest.json) are retained.

## Deployment authorization and receipts

The initial task stayed on a branch and did not authorize deployment. The later user instruction, "boot the backend it uses or whtvr", followed installation of a production-connected phone build and the explanation that its matching backend was missing. That later request was treated as approval to deploy the compatible backend. The old review brief's "no proddeploy" statement preceded this request.

The grouping deployment relied on that continuing authorization while implementing the requested UI improvement. There was no second explicit production-approval message. Its scope was additive presentation metadata, with no changes to existing rates, rules or snapshots. This was an authorization judgment and should have been recorded when made.

The first deployment's log and receipt refer to `095ebaa3`. The separate grouping log names backend commit `d0c7bf9e` and UI commit `2cd85fa4`. Both logs and both backup results are now retained under [evidence](evidence/README.md). The grouping receipt is reconstructed, with no invented exact deployment time. A fresh public probe confirms 48 configurations, 21 families and the five-entry legacy response.

## Node runtime warning

The warning is real, but its heading alone does not establish a Node upgrade. The fresh authenticated configuration read returns `nodeVersion: null`. Local configuration leaves the value absent. The installed Convex CLI compares these values with strict inequality and prints the heading, then prints version numbers only for truthy values. This reproduces the blank version diff in both retained dry-run logs.

No user-authored `"use node"` modules exist in either deployment commit or the inspected current source. The runtime read and source scans are in [receipts.json](evidence/receipts.json). Current inspection cannot reconstruct every historical server setting, because no pre-deployment runtime-config receipt was captured. No new runtime change was made in this follow-up.

## Counts and chronology

The audit missed the retained grouping logs. They prove the reported 55 backend tests and 27 Swift tests. The original review brief also incorrectly said 34 backend tests; the referenced log shows 37. Later phases show 48 and 55, and the current post-merge suite shows 61. These are separate checkpoints, not conflicting results from one run.

The early 50-Swift checkpoint combines a 49-test run with one additional calendar journey. It was not one 50-test run. The decision log is append-only, so historical rows remain and this clarification supersedes any reading of them as current totals. Six screenshots existed at the early checkpoint; the later UI pass retained ten. Verification documentation now labels the pre-deployment phase explicitly.

## Post-merge history

The audit correctly found missing records for subsequent work. Backfill rows cite the commits and distinguish them from contemporaneous decisions:

- `0462f143` introduced a separate development app identity and storage.
- `36db7ebf` routed development-device connections through Tailscale.
- `54489103` replaced that separation with shared production services and identity for Debug and Release.
- `09c26a47` integrated that final configuration. The [environment guide](../ios-environments.md) describes the current behavior. The earlier isolation and Tailscale arrangements are superseded.
- `4b97e4d9` preserved Friends and schedules for older payroll clients while withholding earnings they cannot calculate safely. It does not permit old clients to overwrite rich payroll rules.

These entries are reconstructed from commits and current documentation. This follow-up did not audit those other workstreams' original authorization transcripts or rerun their iOS journeys. It did run the current backend suite, which passed all 61 tests.

## Device and review evidence

The filtered historical readback confirms Tidex 3.1.1 build `20261106.1337`; the install outcome is successful. The receipt deliberately excludes other installed apps and device identifiers. The task used in-place installation without an uninstall or data-clear command. No content-level before/after integrity comparison was performed, so that stronger claim is not made.

The resumed audit is now recorded as completed rather than still unavailable. The two design-agent proposals and agreement remain recorded in [selection-design.md](selection-design.md); the delayed audit did not evaluate that design record. The decision log now points directly to retained deployment, test and device evidence rather than only to narrative summaries.
