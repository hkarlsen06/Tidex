# iOS async delay audit

The initial scan at `35f038c6be72f1cc0d982f10ce9b361383e29385` found 91 executable delay sites. The table uses the original line numbers so each audit finding remains identifiable after edits. Paths start at `ios/TidexApp/` unless they start with `ios/`. Comments that mention `asyncAfter` are excluded.

The inventory command was `rg -n 'asyncAfter|Task\.sleep' ios/TidexApp ios/Shared ios/TidexShareExtension ios/TidexShiftWidget ios/TidexNotificationService`.

## Delay decisions

| Original site | Decision |
| --- | --- |
| `App/MainTabView.swift:366` | Keep the cancellable unread-count debounce for bursts of repository notifications. |
| `App/AppCoordinator.swift:278` | Keep the launch deadline. Convert to Task.sleep(for:). |
| `App/AppCoordinator.swift:408` | Keep the legacy session exchange retry backoff. |
| `App/AppCoordinator.swift:468` | Keep the authentication deadline. Convert to Task.sleep(for:). |
| `App/AppCoordinator.swift:811` | Keep the cancellable foreground debounce. |
| `App/RootView.swift:199` | Keep periodic maintenance configuration refresh while the app stays open. The server supplies no subscription for this configuration. |
| `App/RootView.swift:247` | Keep the accessible toast display duration, with longer time for assistive technology. |
| `App/AppLifecycleHandler.swift:66` | Keep the cancellable active-state debounce. iOS can post didBecomeActive during device locking. The existing cancellation and active-state check reject that transient notification. |
| `App/AppDelegate.swift:141` | Replace list polling with activityStateUpdates and a bounded timeout for an unresponsive system service. |
| `App/AppDelegate.swift:263` | Remove the delayed maintenance pass. Await terminal activity state after ending each stale activity. |
| `App/AppDelegate.swift:359` | Remove the second delayed pass. Await terminal activity state before the immediate maintenance pass. |
| `App/AppDelegate.swift:439` | Keep request retry backoff. ActivityKit has no event that announces when a rejected request can succeed. Convert to cancellable Task.sleep(for:). |
| `App/AppDelegate.swift:568` | Keep the background lease budget. Use an owned cancellable task so an old lease cannot end a newer lease. |
| `Features/Settings/SettingsView.swift:485` | Replace the tab-switch timer with a pending chooser task gated by the settings view appearing. |
| `Features/Settings/Admin/AdminSettingsView.swift:333` | Keep the cancellable search debounce. |
| `Features/Settings/Admin/AdminUsersView.swift:162` | Keep the cancellable search debounce. |
| `Features/Settings/Admin/AdminUsersView.swift:347` | Keep the menu-dismissal workaround. SwiftUI Menu supplies no dismissal completion callback. The delay prevents its closing animation from targeting a chip whose frame has changed. |
| `Features/Settings/Admin/AdminSharesView.swift:74` | Keep the cancellable search debounce. |
| `Features/Settings/Pay/PaySettingsViewModel.swift:734` | Keep the preview debounce. Convert to Task.sleep(for:). |
| `Features/Settings/Pay/Components/AddJobPayDetailsCard.swift:99` | Replace the focus timer with onAppear on the conditional text field. |
| `Features/Schedule/ShiftsView+Actions.swift` | Remove the stabilization timer. The existing committed-month guard and data-change handler determine when the linked shift can open. |
| `Features/Schedule/ShiftsView+Actions.swift` | Keep the cancellable highlight display duration. Convert to Task.sleep(for:). |
| `Features/Schedule/Components/EventDetailsSheet.swift:684` | Keep the inline reminder-save debounce. Convert to Task.sleep(for:). |
| `Features/Schedule/Components/SupplementRuleCard.swift:609` | Replace the focus timer with onAppear on the conditional text field. |
| `Features/AddShift/AddShiftViewModel+Draft.swift` | Keep the cancellable draft-save debounce. Convert to Task.sleep(for:). |
| `Features/AddShift/AddShiftViewModel+Preview.swift` | Keep the adaptive input-preview debounce. Convert to Task.sleep(for:). |
| `Features/Dashboard/DashboardView.swift` | Keep periodic clock-state refresh while Home is visible, and stop on cancellation. Time passing has no repository change event. |
| `Features/Dashboard/DashboardViewModel+Loading.swift` | Remove the launch-animation guess. Start the existing background prefetch after the local load finishes. |
| `Features/Dashboard/DashboardViewModel+Loading.swift` | Remove settings polling. Existing initial-sync and successful-sync handlers reload the saved local read model. |
| `Features/Dashboard/Components/FeaturedShiftCard.swift:374` | Keep the dot animation cadence in the view task. |
| `Features/Dashboard/Components/FeaturedShiftCard.swift:378` | Keep the intentional pause between dot animation waves. |
| `Features/Celebration/CelebrationOverlay.swift:108` | Keep the staged count-up reveal in the view task, and return when it is cancelled. |
| `Features/Celebration/CelebrationOverlay.swift:114` | Keep the staged card reveal after the count-up and intentional pause, and return when the view task is cancelled. |
| `Features/Celebration/ShiftCompletionCelebrationManager.swift:109` | Keep the deadline for a shift ending, including its five-second grace period. |
| `Features/Celebration/ShiftCompletionCelebrationManager.swift:401` | Replace settings-availability polling with the running sync completion event and a local reload. |
| `Features/Friends/FriendsViewModel.swift:314` | Replace sharer polling with the shared initial-load task. Empty results and failures complete the wait. |
| `Features/Friends/FriendsViewModel.swift:612` | Keep the minimum shimmer duration inside the existing independent refresh task. Replace the dispatch continuation with Task.sleep(for:). |
| `Features/Friends/FriendsView.swift:420` | Keep the cancellable highlight display duration. Convert to Task.sleep(for:). |
| `Features/Friends/FriendsView.swift:873` | Keep the cancellable metadata refresh debounce for notification bursts. |
| `Features/Friends/FriendsView.swift:965` | Keep remote typing expiry when no stop event arrives. |
| `Features/Friends/FriendsView.swift:974` | Keep the typing-stop grace period to avoid flicker. |
| `Features/Friends/Messages/FriendsThreadComposerView.swift:659` | Replace repeated focus attempts with picker dismissal callbacks. PhotosPicker uses its presentation binding change because it has no onDismiss callback. |
| `Features/Friends/Messages/FriendsThreadExyteChat.swift` | Keep the UIKit reply-scroll settling workaround. Self-sizing rows and table reloads can interrupt animated scrolling. The bridge observes content offset and size, but those changes do not mark the end of interrupted scrolling or row sizing. UIList owns the table delegate. There is no single reliable completion event. |
| `Features/Friends/Messages/FriendsThreadExyteChat.swift` | Keep the UIKit deferred-scroll workaround. Retry after the fork has applied its pending table layout. Request identity checks reject superseded work. |
| `Features/Friends/Messages/FriendsChatMessageRowContent.swift:1079` | Replace the reset timer with the swipe-reset animation completion. |
| `Features/Friends/Messages/FriendsChatMessageRowContent.swift:1090` | Replace the reply handoff timer with the same animation completion. |
| `Features/Friends/Messages/FriendsThreadViewModel.swift:411` | Keep the cancellable visible-read debounce. |
| `Features/Friends/Messages/FriendsThreadViewModel.swift:681` | Keep remote typing expiry when no stop event arrives. |
| `Features/Friends/Messages/FriendsThreadViewModel.swift:691` | Keep the remote typing-stop grace period. |
| `Features/Friends/Messages/FriendsThreadViewModel.swift:1077` | Keep periodic active-thread reconciliation as recovery for missed realtime events. |
| `Features/Friends/Messages/FriendsThreadViewModel.swift:1406` | Keep the idle typing-stop deadline. |
| `Features/Friends/Messages/FriendsThreadViewModel.swift:1426` | Keep the typing-push escalation deadline. |
| `Features/Friends/Messages/FriendsThreadView.swift:1397` | Keep the reply highlight display duration. Convert to a cancellable view task and Task.sleep(for:). |
| `Features/Friends/Messages/FriendsThreadView.swift:1456` | Keep the staged screenshot success haptic and bell animation. |
| `Features/Friends/Messages/FriendsThreadView.swift:1472` | Replace the screenshot bubble cleanup timer with its dismissal animation completion. |
| `Features/Onboarding/OnboardingView.swift:99` | Keep the staged signup transition. Move its delay to task(id:) so leaving the view cancels the handoff. |
| `Features/Onboarding/Screens/WageScreen.swift:212` | Replace the keyboard-layout timer with keyboardDidShowNotification. |
| `Features/Onboarding/Screens/SettingsAccordionScreen.swift:340` | Replace the focus timer with onAppear on the conditional text field. |
| `Features/Onboarding/Screens/SettingsAccordionScreen.swift:497` | Replace the focus timer with onAppear on the conditional text field. |
| `Features/Onboarding/Screens/PreAuthAddShiftSimulatorComponents.swift:104` | Keep the shimmer duration and cleanup pause in task(id: trigger). |
| `Features/Onboarding/Screens/PreAuthAddShiftSimulatorComponents.swift:205` | Keep the totals animation start delay in task(id: isActive). |
| `Features/Onboarding/Screens/PreAuthAddShiftSimulatorComponents.swift:218` | Keep the expansion stage duration in the same cancellable task. |
| `Features/Onboarding/Screens/PreAuthAddShiftSimulatorComponents.swift:225` | Keep the collapse stage duration in the same cancellable task. |
| `Features/Onboarding/Screens/PreAuthAddShiftSimulatorScreen.swift:114` | Keep the delayed hint shimmer in the view task. |
| `Features/Onboarding/Screens/PreAuthAddShiftSimulatorScreen.swift:192` | Keep the deliberate focus-emphasis duration in task(id: focusRelaxToken). |
| `Features/Onboarding/Screens/SuccessScreen.swift:351` | Keep the success haptic timing in task(id: saveStatus). |
| `Features/Onboarding/Components/SupplementValueSection.swift:161` | Replace the focus timer with onAppear on the conditional text field. |
| `Features/Onboarding/Components/OnboardingRateSlider.swift:326` | Replace the focus timer with onAppear on the conditional text field. |
| `Features/Onboarding/Components/OnboardingRateSlider.swift:350` | Replace the focus timer with onAppear on the conditional text field. |
| `Shared/Components/ScreenshotSharePromptOverlay.swift:129` | Replace the share handoff timer with the overlay dismissal animation completion. |
| `Shared/Components/ScreenshotSharePromptOverlay.swift:209` | Replace the overlay removal timer with its animation completion. |
| `Shared/Components/PullToRefreshView.swift:98` | Keep simulated network latency in the preview only. Convert to Task.sleep(for:). |
| `Shared/Components/ScreenshotNotificationFeedback.swift:32` | Keep the staged success bell animation. |
| `Shared/Components/ScreenshotNotificationFeedback.swift:44` | Replace cleanup timing with the bubble dismissal animation completion. |
| `Shared/Animations/MonthTransition.swift:610` | Replace the bounce timer with the animation completion before presenting the month picker. |
| `Shared/Animations/MonthTransition.swift:634` | Replace the bounce timer with the animation completion before navigating to today. |
| `Storage/Sync/SyncRevisionWatcher.swift:63` | Keep the cancellable subscription retry backoff. |
| `Storage/Sync/SyncCoordinator.swift` | Replace manual-refresh polling with the state actor idle stream. Account generation and cancellation stop obsolete waits. |
| `Storage/Sync/SyncCoordinator.swift` | Keep the overall sync deadline. Convert to Task.sleep(for:). |
| `Storage/Sync/SyncCoordinator.swift` | Keep the pull-phase deadline. Convert to Task.sleep(for:). |
| `Services/Auth/ImpersonationManager.swift:211` | Keep the server session-expiry deadline and one-second clock tolerance. |
| `Services/Auth/AuthSessionManager.swift:416` | Keep the authentication operation deadline. |
| `Services/Auth/OAuthProviders/AppleAuthProvider.swift:76` | Keep the authorization request deadline. Convert to Task.sleep(for:). |
| `Services/Network/View+ReloadOnChange.swift:22` | Keep the cancellable realtime subscription retry backoff. |
| `Services/Network/ConnectivityMonitor.swift:59` | Keep the cancellable connection-restoration debounce. |
| `Services/Network/ConvexRealtime.swift:44` | Keep periodic token refresh before expiry. |
| `Services/Network/ConvexRealtime.swift:214` | Keep the cancellable reconnect debounce. |
| `Services/Data/FriendsMessagingRealtimeCoordinator.swift:716` | Keep the cancellable thread-list subscription retry backoff. |
| `Services/Data/FriendsMessagingRealtimeCoordinator.swift:729` | Keep the cancellable thread-detail subscription retry backoff. |
| `ios/TidexNotificationService/NotificationService.swift:302` | Keep the avatar-fetch deadline so the extension can deliver its notification. |
| `ios/TidexNotificationService/NotificationService.swift:323` | Keep the interaction-donation deadline and diagnostic warning. |

## Isolation

`SyncCoordinator` has checked `Sendable` conformance. Its nested observable status object is main-actor isolated. The public status properties forward to that object on the main actor, which preserves observation through existing callers. The sync entry points and worker use `@concurrent` to keep processing off the main actor under approachable concurrency.

`Mutex` protects the locale-send flag and running work task. The existing state actor owns the idle stream and account generation. The pull phase is an actor, so completed table results survive a timeout without unchecked shared mutation. Main-actor-only reset and tracking-load methods no longer wrap their own UI changes in `MainActor.run`. Worker UI updates still cross that boundary explicitly.

`FriendsVisibilityStore` is main-actor isolated. Its UserDefaults read-modify-write runs without suspension, so two callers cannot lose one another's visibility changes. The other audited unsafe sendability declarations remain unchanged.

All `SyncCoordinator` callers were searched across the app, shared code, extensions, and tests. Existing reads of status are on the main actor. Extensions have no coordinator calls.

## ActivityKit

Apple documents `activityStateUpdates` as the sequence for activity lifecycle changes. Ended and dismissed activities are terminal even if they remain in the activity list. The replacement waits on that state with a bounded timeout, then checks the actual state before starting another temporary activity. Request rejection still uses backoff because Apple supplies no request-ready event. See [ActivityState](https://developer.apple.com/documentation/activitykit/activitystate) and [Meet ActivityKit](https://developer.apple.com/videos/play/wwdc2023/10184/).

## Verification

The focused wrapper selection includes `SyncOfflineBehaviorTests`, `SyncPushMergeTests`, `SyncConflictRowTests`, `SyncServerSnapshotDiffTests`, `FriendsMessageOutboxTests`, `FriendsListOrderingTests`, `FriendsThreadExyteChatTests`, `FriendsThreadComposerBridgeTests`, `HomeScheduleLoadingHelperTests`, `ScheduleListMonthTests`, and `OnboardingSaveManagerTests`. All 110 tests passed before integration with the concurrent payroll-engine changes.

The sync policy requires regression tests for changed coordination logic. Four tests were added to the existing, registered `SyncOfflineBehaviorTests` file. They cover waiting for completion, completion before registration, account reset, and cancellation. Other screen changes use existing tests under the repository test policy.

The initial build attempts caught the nested Observation type access and ActivityKit isolation problems. No tests ran in these attempts. Each failure was corrected before the passing run.

```text
SUMMARY: FAILURE queued=6s compiled=87s tested=0s
SUMMARY: FAILURE queued=347s compiled=90s tested=0s
SUMMARY: FAILURE queued=68s compiled=52s tested=0s
SUMMARY: SUCCESS queued=23s compiled=93s tested=28s simulator="Shared iPhone 3"
SUMMARY: FAILURE queued=0s compiled=115s tested=1050s simulator="Shared iPhone 3"
SUMMARY: FAILURE queued=1s compiled=93s tested=1385s simulator="Shared iPhone 3"
SUMMARY: SUCCESS queued=0s compiled=33s tested=162s simulator="Shared iPhone 3"
```

After rebasing onto local main, the combined wrapper selection included the same focused tests plus `ShiftJourneyUITests`, `CalendarSemanticsUITests`, and `TidexAppUITests`. That run passed 151 of 154 tests. The three failures were two process crashes in `testAddScreenNamesItsModesAndSaveAction` and `testAppStoreScreenshots`, plus the money-screen assertion in `testMoneyAmountsSayWhatTheyAre`. The failed cases were rerun with preserved artifacts after integration with the subsequent localization and SwiftData versioning commits. That replay passed 113 of 114 tests, including both earlier crash cases and the complete configured screenshot locale matrix. The result bundle identifies the remaining failure as the fixed September label assertion on line 528. The wrapper reported line 527, the preceding successful amount assertion.

`swiftlint --quiet` ran from the repository root before and after the rebase. It reports no errors or new warnings on changed lines. Existing length and complexity warnings remain.

No physical iPhone was connected. ActivityKit replacement requires a physical-device check, recorded in `RELEASE_CHECKS.md`.

The final focused run passed all 115 tests on the latest integrated source. It reran the eleven focused unit and integration test classes, including the new outbox cancellation regression from main, plus the three earlier failing UI cases and the Schedule retap journey. `TEST_RUNNER_TIDEX_SCREENSHOT_LOCALES=en-US` used the screenshot test's existing locale selector for this final run. The prior preserved replay already exercised the complete locale matrix.

The repository guidance and fixture use the current month, while `testMoneyAmountsSayWhatTheyAre` expected September. The expectation now derives the English month from the current date. The amount and comparison assertions remain intact. The stale September comment beside the screenshot fixture calculation was corrected as well.

Manual verification used the same shared simulator and the in-memory fixtures through the T3 Device panel. Navigating from October to a November shift by deep link opened the correct Shift Details sheet, with its date, hours, and pay. The generic pay-settings deep link opened Manage jobs with the seeded job.

The onboarding setup flow received focus and showed the keyboard when the hourly-rate, tax, and custom-payday fields appeared. The hourly rate retained 250 after Done. The custom payday retained 17 and displayed its summary. The flow reached the complete success screen. Fixture launch environment variables were cleared and the Device panel session and simulator lock were released afterward.

## Implementation commits

- `db610276652d1362618f00a1fc8134ebe184d110` fix(ios): enforce sync isolation and await idle events.
- `d131b8fe419aa947978e2b64f122550c7cd878e9` fix(ios): replace timing guesses with lifecycle events.
- `ec55f750aa6129c31e9d2fa7e3c0a0817bc4911d` fix(ios): cancel view timers and use the current fixture month.
