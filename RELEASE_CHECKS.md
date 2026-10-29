# Checks before the next release

Things to try on a device before the next App Store or TestFlight release. Go through every item before you ship. Once the release is out, delete the items and keep the empty file.

Hjalmar confirmed the first three checks passed on Cold Harbor on 2026-10-28.

On 2026-10-28, Hjalmar accepted manual help for the recently active phone-only account. Its recovery is not a cutover blocker, and was not tested.

Clerk's email requirement is off in production and development as requested on 2026-10-28. Public API readbacks confirmed that supplied email addresses still require verification. A fresh email-less Clerk session passed the deployed account-linking and shift-access checks after a synthetic Apple identity was supplied at the trusted server step. The real account's retained Apple subject matches exactly. This verifies the server steps, not the person's Apple authentication.

On 2026-10-29, Hjalmar accepted the remaining unverified Apple authentication step for this release. It remains untested on that account holder's device and does not hold up release.

On 2026-10-29, the phone test confirmed matching-account sender, message and Reply, and a replay after sign-out showed only a neutral Tidex alert. Hjalmar also accepted the startup routing issue documented in `docs/convex-release-readiness.md`, where reopening recovered his dashboard and data.

- [x] Install the App Store version, sign in, turn on flight mode, update to N+1 and open it. The sign-in screen shows. Turn flight mode off and wait up to 15 seconds. The app signs you in to the same account by itself.
- [x] Repeat that, but sign in by hand to a different account before the 15 seconds pass. You stay in the account you chose, and the old account doesn't take over.
- [x] While the app on the phone syncs a shift you just added offline, start or end an impersonation as admin. The shift stays with the account that made it, on the phone and on the server.
- [x] On a phone, check that a matching-account push shows its sender, message, badge and reply action. Switch accounts or sign out while a push for the old account is in flight. It may show a neutral Tidex alert, but no old-account content or reply action.
- [ ] On a device, complete fresh Apple authentication with an account that supplies no email. The email requirement and server linking have been checked. This remaining step needs that Apple account holder. Details are in `/tmp/tidex-n1-readiness/fresh-apple-verification.md`.
