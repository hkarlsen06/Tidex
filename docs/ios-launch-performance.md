# iOS launch performance

Status: complete. The measured Home load-completion milestone was about 22% sooner in both conditions. Local month reads finished 56% to 71% sooner. These results cover the small cached-account workload below.

The November 8, 2026 launch review used Cold Harbor, reported by Instruments as an iPhone 18 Pro running iOS 27.3 beta. The physical UDID used for every launch measurement was `00008160-0002228C36A0000A`.

A known normal account can read its existing local Home data before token and profile refresh finish. Remote rejection invalidates this presentation and retains unsynced data during sign-out. A persisted impersonation needs remote verification, and the coordinator restores its expiry timer after resolving it.

Home has one initial load task and an independent calendar metadata task. A successful launch sync without local changes does not reread Home. Failed sync still refreshes local data because some tables may have saved before the failure. Calendar operations reject results from an earlier account generation before saving tokens, publishing state, or opening a feed.

The initial app-config request has one owner. Later foreground activation and minute polling still refresh it. Successful APNs registration owns subsequent Live Activity registration. Token observations only register changed values, and identical in-flight registrations join. Keychain publication reuses the existing remembered token and retries failed writes.

Sync downloads two initial pages concurrently. It applies each table in the original order, saves each page before advancing its cursor, and consumes a completed leading page while the other download continues. Cancellation stops outstanding requests. This adds a bounded prefetched page, not a result cache.

## Measurement

| Condition | Milestone | Before median and range, ms | After median and range, ms | Median reduction |
| --- | --- | --- | --- | --- |
| Quick relaunch | Local month rows read | 292.7, 277.2 to 317.2 | 128.9, 127.8 to 141.7 | 56.0% |
| Quick relaunch | Home load completed | 323.7, 303.2 to 348.7 | 252.6, 224.1 to 284.4 | 22.0% |
| 70 seconds idle | Local month rows read | 505.0, 459.0 to 551.3 | 148.4, 131.2 to 161.2 | 70.6% |
| 70 seconds idle | Home load completed | 537.6, 490.5 to 570.7 | 416.6, 353.7 to 485.8 | 22.5% |

All twenty measured launches completed without errors and with matching workload counts. Baseline launches each performed two explicit dashboard reloads. The new build performed none on this unchanged dataset.

Each condition uses five alternating before/after pairs of development-signed Release builds without a debugger. Each in-place install preserves data and gets an untimed five-second priming launch. Timed captures last eight seconds. The second condition waits 70 seconds after terminating the priming process, based on the observed 60-second token lifetime.

All log intervals start at `AppDelegate.didFinishLaunching START`. The common early marker is `Loaded shifts for ...`, after the displayed month's raw rows have been read. The later `Loaded dashboard from local` marker follows data application and clock-state refresh. Neither measures tap-to-interactive time. The new `Local dashboard ready` Points of Interest event marks data application and has no equivalent in the old binary. Home can display the applied data while clock-state refresh continues. The later completion marker includes that additional wait.

The workload has five wage snapshots, two recurring entries and no shifts in the displayed month. It is a small existing-account workload. First install, post-reboot launch, large histories and an offline presentation journey are outside this measurement. Offline and expired-impersonation device checks remain in `RELEASE_CHECKS.md`.

Profiled runs are separate from unprofiled timings. Instruments lifecycle periods measure the initial render separately. Memory and network results are individual diagnostic runs, not latency distributions.

## Instruments observations

| Diagnostic | Before | After |
| --- | --- | --- |
| Live Activity device registrations | 5, identical arguments | 1 |
| App-config requests | 2 | 1 |
| Sync reads | 8 | 8 |
| Maximum overlapping sync requests | 1 | 2 |
| Sync request wall span | 644 ms | 392 ms |
| Sum of sync request durations | 579 ms | 740 ms |
| Peak sampled physical footprint | 35.17 MiB | 35.83 MiB |
| Final sampled physical footprint | 33.85 MiB | 34.13 MiB |

All eight sync responses had matching row counts, cursors and completion flags. No HTTP or application errors were observed. The smaller sync wall span came from overlap, even though summed request durations increased. Merges and cursor saves remain sequential.

The captures contained 31 Tidex HTTP requests before and 27 after. Inbox traffic varied. The baseline had two badge queries; the new capture had three badge queries and one full snapshot. These total counts are diagnostic observations rather than fixed request budgets. Clerk still made two client-refresh requests.

The new lifecycle trace recorded 89.8 ms from process initialization to the end of initial-frame rendering. The two original traces recorded 123.9 and 130.3 ms. These are individual profiled observations, not a repeated first-frame speedup result. They do not measure interaction readiness. The Time Profiler configuration warned about requested versus configured sampling periods, so sampled CPU weights are not used as precise durations or as a speedup claim.

Both memory captures contain nine samples. The new capture stayed in the nominal thermal state. The observed peak increase was 0.66 MiB. Large-page memory costs remain unmeasured.

## Verification and limits

All 619 device tests passed, including persisted identity rejection, expired impersonation cache rejection, stale calendar mutation responses, sync response ordering, cancellation and leading-page cursor persistence. The add-shift, pay and delete UI journey passed on Shared iPhone because its fixture is simulator-only. Release build and SwiftLint passed. SwiftLint reports size and complexity warnings, including the expanded identity-resolution function.

The shared Mac build queue and one transient out-of-space failure delayed verification. The tests were rerun after space recovered. The first incomplete comparison was excluded after independent review required source corrections. Both compared binaries and symbols are frozen with their hashes in the local `work/launch-implementation-20261108` artifacts. Raw traces and HAR files stay local because they contain account data and credentials.

Clerk still makes overlapping SDK startup and foreground client refresh requests. That was reproduced in the original HTTP trace and SDK call sites. Resolved package checkouts were not modified. A broad SwiftData executor rewrite was not justified by the observed storage cost. The payroll read helper now names its store actor without claiming off-main execution.

The earlier RootView comment incorrectly treated a SwiftUI task as proof that the first frame was displayed. That comment and the `onAppear` log now describe lifecycle behavior accurately. Instruments Profile now uses Release instead of Debug and does not inherit launch logging suppression.

## Revisions and evidence

The baseline is `901f90935a43299cd7a54eb14c738a521ec7e830`. The implementation is in signed local commits `7cdfb4f0` and `249b6bba`. The exact saved source patch for the measured new binary matches the committed source patch.

| Artifact | Version and build | Executable SHA-256 |
| --- | --- | --- |
| Before | 3.1.2, 20261108.0437 | `b0f7e188b6985d4a5116319f2aa315824f9f2b26e1a5f0b2aae0cda1a09b4dac` |
| After | 3.1.2, 20261108.0604 | `8372369848bfa5d5fc6df408501f9cb2a5c479c629773ed70d00cdeda1c2dd76` |

The local evidence directory contains `comparison.json`, each raw launch log, matching app symbols, `after-launch.trace`, `after-memory.trace`, sanitized summaries and reusable collection scripts. Raw HAR files are excluded from Git.

The research used [Apple's launch-time guidance](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time), [Uber's discussion of iOS performance measurement](https://www.uber.com/ch/en/blog/measuring-performance-for-ios-apps-at-uber-scale/) and [DoorDash's launch-time investigation](https://careersatdoordash.com/blog/how-we-reduced-our-ios-app-launch-time-by-60/). Their reported gains were not assumed to apply to Tidex. The physical-device measurements determined which changes were implemented.
