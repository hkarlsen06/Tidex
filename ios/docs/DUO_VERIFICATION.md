# iPhone Duo verification

QA target: iPhone Duo simulator on iOS 27.1, built with the iOS 27.1 SDK.
Date: 2026-11-05.

## Layout coverage

The screen matrix covers 34 fixtures on the outer display at 466 × 678 points and the inner display at 951 × 669 points. It includes welcome and setup, authentication, account settings, calendar import, pay settings, shift and event details, calendars, statistics, friends and chat. Fixtures use production components. The connected journeys below check saving and delivery separately.

Reviewed captures include all 68 dark-mode cases, 24 light-mode cases and 16 cases at the largest accessibility text size. Welcome, calendar and chat also passed a partially open smoke check. Missing animation pixels were recaptured after settling and compared with Device Hub.

`scripts/verify-duo-screens.py` records a PNG, accessibility tree and manifest for each case. Captures start with `review: pending`; inspect the images before recording a pass. Entry animations can lag behind the accessibility tree, so recapture any missing pixels and compare with Device Hub.

Run it with the exact command returned by T3 `device_open`:

```sh
python3 scripts/verify-duo-screens.py \
  --agent-device /path/returned/by/device_open/agent-device \
  --device-id <Duo simulator UUID> \
  --output /tmp/tidex-duo-captures
```

Use `--themes light dark`, `--text-size accessibility-extra-extra-extra-large`, `--poses closed open half-open`, and `--screens` to select additional cases. The script restores normal text size and clears fixture selection when finished.

The simulator must already be available and opened in the Device panel. Do not download a runtime. Install the signed build through `simctl install`; the Device tool's install path stripped executable signatures during this run and caused launch-service rejection.

## Connected journeys

These used two temporary Clerk development identities and the local Convex backend. Production accounts and data were untouched.

- Email signup and verification, job creation, wage selection, supplement editing, break/tax/payday setup and onboarding completion.
- The job and wage settings were read back from Convex.
- A 09:00–17:00 shift created in the app was read back from Convex.
- Share back, conversation opening, text delivery and a two-photo message verified from the recipient's backend response.
- Four distinct staged photo previews retained their contents and fit after folding and unfolding.
- Editing shift times while folding retained 09:00 and 17:00. The focused input stayed above the keyboard, with Next/Done in a separate row.
- At the largest accessibility text size, both Start and End stayed visible when focused on the outer display after folding.
- Clearing and retyping End produced 02:00 while preserving Start at 09:00. Clearing the last digit no longer moves focus to Start.
- Changing text size while a time field was focused retained the field and keyboard.
- Single, Events and Fixed mode controls used the right-hand native toolbar on the outer display.

The two temporary development accounts and their data were deleted after verification. The original development account remained.

## Automated checks

`FriendsThreadExyteChatTests` and `FriendsMessageOutboxTests` passed on Cold Harbor: 31 tests, zero failures. Builds and tests ran through the repository wrappers.

The Duo journeys passed after focused reruns of the affected tests:

| Target | Journey checks passed |
| --- | --- |
| Duo outer display, iOS 27.1 | 19 |
| Duo inner display, iOS 27.1 | 6 |
| Shared iPhone, iOS 27.0 | 9 |

Coverage includes creating and deleting a shift, calendar selection, tab navigation, workplace and pay editing, large-text forms, invalid drafts, chat delivery and the attachment drawer. Existing journeys were used; no layout or focus unit tests were added.

The mode journey checks localized labels and selection on both toolbar axes. Its visible-name assertion remains for the horizontal toolbar. The event journey enters times through the visible number pad and retains its value, validation-hint and keyboard-dismissal assertions. Separate rapid-input tests still use `typeText`.

On this Duo runtime, batched XCTest event entry left a keyboard onscreen after the app had no active responder. Manual entry and number-pad taps dismissed it. Generic XCTest swipes also failed to scroll the inner pay review; that journey now drags within the rendered window. No keyboard-delay workaround was added to the app.

Some XCTest inner-display screenshot attachments were black. Visual approval uses the reviewed Device Hub and `agent-device` captures, including the live keyboard checks, rather than those attachments.

Use `-collect-test-diagnostics never` for focused wrapper runs on this runtime. Assertion results and xcresults remain available; the flag avoids a separate 600-second diagnostic-collection timeout observed during failures. SwiftLint and the capture script's syntax check passed. Reviews found no remaining concrete issues.

## Hardware follow-up

The physical Duo fold/keyboard check remains in `RELEASE_CHECKS.md`. The simulator fold command dispatched pose changes but could not read back the hinge angle. PNG dimensions confirm the active panel; they do not confirm a physical hinge angle. Siri, push delivery and Live Activities retain their separate device checks.
