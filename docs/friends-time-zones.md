# Friends time zones

## Problem

At 00:30 for a viewer in Norway, a friend's 05:00 shift in Britain is five and a half hours away. Tidex currently reports four and a half because it interprets the friend's clock time in the viewer's zone. Build 20261109.2324 was withdrawn from review before publication.

The fix must compare named source and viewer zones. It must not assume Norway or add a fixed one-hour offset.

## Research

Viewer-local time is the strongest convention for availability displays. It is not a universally proven winner in a controlled comparison.

| Product | Documented behavior |
| --- | --- |
| [Apple Calendar](https://support.apple.com/en-gb/guide/iphone/iph69525c028/ios) | Events normally appear in the viewer's current zone. An override is optional. |
| [Google Calendar](https://support.google.com/calendar/answer/37064?hl=en) | Each invitee sees the event in their local zone. Additional zones are optional. |
| [Outlook](https://support.microsoft.com/en-us/outlook/getstarted/manage-time-zone-settings-in-outlook) | Meeting and free/busy times are adjusted to the viewer's zone. |
| [Calendly](https://calendly.com/help/time-zones-overview) | Availability normally uses the invitee's detected zone. Venue-based events can retain the venue's zone. |
| [Deputy](https://help.deputy.com/hc/en-au/articles/10883412235791-Managing-preferences-for-viewing-shift-times-on-mobile-across-different-time-zones) | Mobile Home defaults to device-local shift times and details show both zones. Its Schedule view also has location-based behavior. |
| [When I Work](https://help.wheniwork.com/articles/setting-the-time-zone-computer/) | Supports personal-local display while workplace time defines workday, workweek and pay-period boundaries. |

[NN/G's usability research](https://www.nngroup.com/articles/time-zone-selectors/) included 13 moderated participants and 83 unmoderated participants. It supports automatic zone selection and understandable place-based labels. Offsets alone were poorly understood. This research concerned selectors, not viewer-first versus friend-first shift cards.

## Decision

Use one fixed schedule time zone per account, editable by its owner. Prefer that over continually following the latest phone zone.

Following the phone requires less setup and immediately uses existing telemetry, but opening the app during travel would reinterpret every existing and future shift. Two devices can alternate the value. A fixed zone adds a setting and cannot infer every user's original intent, but keeps an established schedule stable.

Run a previewable, repeatable one-time backfill from valid existing activity zones before shipping the client. New activity reports only initialize an absent fixed zone from a valid incoming named zone. Once established, ordinary activity reports never change it. Never use the push-device fallback, which can be an Oslo default. The owner can explicitly correct the zone in Profile settings. A mismatch with the phone appears inline with an update action.

The account-level choice assumes the shared schedule uses one zone. Different work locations in different zones may need a later per-job model. Do not pretend that phone telemetry proves where historical work happened.

## Behavior

The November 10 UI review replaced the first presentation. The rules below are the current ones. [UI review](#ui-review) lists what changed and why.

- Friend cards, statuses, progress and widgets use the actual shift instant and the viewer's current zone. For the reported example, show 06:00 and a five-and-a-half-hour countdown. A small globe beside the status marks clocks converted from another zone. Cards and widgets carry no time labels and no second time. VoiceOver reads "Your time" before the range.
- Keep the existing 24-hour HH:mm clock convention. Keep overnight widget ranges compact. Keep the weekday in the chat header.
- Decide whether two clocks differ by comparing offsets at the shift's start and end, not zone identifiers or today's offset. A friend on the viewer's clock gets no globe, no picker and no extra text.
- A friend's schedule has a Your time / Their time picker directly above Hours/Earnings, shown only when the clocks differ. It applies to the month calendar, the list and the details sheet. The choice is stored on the device and starts on Your time, which matches the cards.
- Your time moves each shift to the day it starts on for the viewer and shows the viewer's clocks. A shift recorded up to two days outside the visible days is loaded too, because it can start on a visible day for the viewer. A shift that leaves the month appears on the dimmed day of the next or previous month. No shift appears twice.
- Their time shows the recorded dates and clocks.
- The month total always sums the shifts recorded in the friend's month, in either mode. Day amounts follow the shift to the day it is shown on. Payroll inputs, shift snapshots sent to chat and shared images use the recorded shift.
- The details sheet leads with the clock the schedule shows. One row in the same card gives the other clock, with its dates when they differ. The row is part of the card, not an inset above the navigation bar.
- The chat header shows the viewer's date and range, with one "Their time" line beneath it.
- Keep the calendar today highlight on the viewer's day. Superimpose lays the friend's shifts over the viewer's own, so it always uses Your time and hides the picker. Overlap markers compare times on the viewer's clock. Their time omits them when the clocks differ, and so does an unknown zone.
- Without a valid source zone, show a route to the recorded schedule rather than choose an arbitrary active or next shift. Do not show countdowns, progress or working-now claims. The schedule shows the recorded dates and clocks with a one-line unknown-zone note where the picker would be. There is no picker, because there is nothing to convert.
- The labels are Your time and Their time. Their time means the schedule's fixed zone, not where the friend's phone is. The Norwegian label is "Vennens tid", and languages without a gender-neutral singular "their" say "Friend's time". No label names a city or an offset.

## Data and implementation constraints

- Add an optional fixed schedule-zone field to the account's backend profile and an owner-only validated setting operation. Use reported zones only for the one-time backfill and set-if-absent initialization.
- Return `owner_time_zone` from the authorized `sharedSchedule` payload. Do not add tracked-zone data to `profileOf`, outgoing-only friends or blocked friends.
- Validate named zone identifiers at the server and client boundaries. Construct an instant from date and time components in one source-zone calendar. Never parse the date at viewer midnight before applying source-zone clock components.
- Use one timing helper shared by the app and widgets. Add overnight days in the source calendar and handle 24:00, DST boundaries and invalid input explicitly.
- Keep the metadata cache keyed by viewer and owner. Reuse the existing UserDefaults approach for derived metadata rather than alter the SwiftData schema for a cache field. Views consume joined preview data. Clear it on sign-out and reconcile removed shares.
- Preserve the zone through both App Group cache writers. Optional JSON fields must decode older caches safely. Unknown zones remain unknown.
- Leave stored shift dates, clock times, recurring anchors and payroll inputs unchanged. Payroll keeps its existing parser. The owner's own app, widgets, reminders and Live Activities retain device-local behavior. The fixed zone controls how other people see the owner's shifts. Keep compatibility with existing app versions.
- Deploy the additive backend change before shipping a client that relies on it. Production deployment requires Hjalmar's approval after the change and checks are concrete.

## Verification

Cover the reported London-to-Oslo case, an eastern and a western viewer, cross-midnight dates, source-zone DST, 24:00 and malformed or missing zones. Check source/viewer offset differences on the actual shift date. Test travel and multi-device activity updates without moving an established schedule zone, owner changes, share authorization, both widget cache writers, cached metadata and sign-out isolation. Keep payroll date totals unchanged.

Fable 5.2 reviewed the existing code and initial proposal, then agreed with the fixed-zone decision in a second review. The implementation adopts its mandatory corrections. The implementation review found display formatting, widget layout, VoiceOver and failed-setting-load defects. Those findings have been addressed. Production deployment and the one-time backfill remain pending approval.

The privacy copy describes sharing this fixed zone with authorized schedule viewers. On November 10, Hjalmar chose to update only the displayed privacy-policy date. Keep the canonical acceptance manifests unchanged. Production publication still requires deployment approval.

Backend checks passed five handler tests with 35 assertions and TypeScript checking. A real local Convex backfill preview found 37 eligible records out of 38. Applying it initialized those records; a repeat preview found zero eligible records. This was the development deployment at 127.0.0.1:3210. Production has not changed.

The iOS wrapper passed all 49 requested checks on Shared iPhone: 48 focused tests and the expanded Friends UI journey. A further UI rerun passed after moving the source-time caption into a full-width footer. The rendered card and its maximum-text-size variant were checked, including the spoken label. Both friend widget layouts were rendered with a cross-midnight shift. The small widget initially clipped its source caption; allowing it to wrap fixed that, and the final wrapper build passed without warnings or errors. Depressed Harbor was locked, so no physical test was possible. The generated metadata validates with zero issues in all 32 App Store locales.

Historical chat shift attachments retain recorded clock times. Friend Siri clock responses remain a deferred limitation. The one-zone-per-account choice can be extended with per-job overrides later.

## UI review

On November 10, Hjalmar reported that the details sheet's title collided with the Your time text and that he was unhappy with the presentation. He proposed a Your time / Their time picker above Hours/Earnings. Fable 5.2 reviewed the rendered screens and made these changes.

| Flaw found | Change |
| --- | --- |
| The sheet's time text was a safe-area inset outside its navigation stack, so it drew over the title at every text size. | The other clock is a row inside the header card. |
| "Your time" inside the card tile pushed the status off the name's line and the clocks off the avatar row. A "Shift time" footer added a fourth row. | The tile has its standard layout again. A globe beside the status marks converted clocks. |
| Every schedule with a known zone showed a caption about time zones, including friends on the viewer's own clock. | The schedule shows a control only when the clocks differ or the zone is unknown. |
| The calendar stayed in the friend's zone while cards showed the viewer's, so the same shift had two clocks with no way to reconcile them. | The picker switches the calendar, list and sheet, and starts on the clock the cards use. |
| Overlap markers disappeared for every friend in another zone. | Your time compares both people's shifts on the viewer's clock, so the markers are back in that mode. |
| Widget rows carried a "Your time" label and a "Shift time" line, and the layout needed fallbacks to fit them. | Widgets show the globe mark and their original row layout. |
| The segmented picker truncated "Vennens tid" at large text sizes. | The two options become full-width rows when the titles don't fit. |

Deep-link highlights for a deleted shift carry only a recorded date. In Your time they can mark the day before or after the one the shift was shown on. Highlights for added and changed shifts use the shift's ID and are exact.

Checks on Shared iPhone, iOS 27.0, on November 10. The wrapper passed 40 tests: the date and zone tests, list ordering, the Friends UI journey, which now switches the picker and opens the details, and the shared calendar journey. The unit tests did not run on Cold Harbor, where the run lost its connection to the device before any test started. Calendar, list, details sheet, cards, chat header and both widgets were rendered at the default text size, and the calendar, list, sheet and cards at the largest accessibility size. The screenshots are in `~/Library/Developer/TidexReleases/3.1.2-20261109/friends-time-zones/ui-review/`. No small-screen simulator exists on this Mac, so a 4.7-inch layout was not rendered. The picker adds less height than the superimpose legend, which hides it.
