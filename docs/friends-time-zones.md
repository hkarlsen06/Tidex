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

- Friend cards, statuses, progress and widgets use the actual shift instant and the viewer's current zone. For the reported example, show 06:00 your time, 05:00 shift time and a five-and-a-half-hour countdown.
- Keep the existing 24-hour HH:mm clock convention. Keep overnight widget ranges compact, and put cross-date context in the secondary description. Keep the weekday in the chat header.
- Show secondary source-local time only when the clock time or date differs. Compare offsets at the shift's start and end, not zone identifiers or today's offset.
- Keep the detailed month calendar and its list in the friend's schedule zone, with a visible zone label. Keep original dates and payroll totals intact. Selected-shift details show both times and both dates when necessary.
- Keep the calendar today highlight on the viewer's day, because superimpose also shows their own shifts. Omit raw wall-clock overlap markers when source and viewer offsets differ at either boundary or the source zone is unknown.
- Without a valid source zone, show a route to the recorded schedule rather than choose an arbitrary active or next shift. Do not show countdowns, progress or working-now claims. Raw recorded dates and clock times remain available with an unknown-zone indication.
- Use your time and shift time labels, not their time. Calendar labels describe the current offset difference without naming a city.

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
