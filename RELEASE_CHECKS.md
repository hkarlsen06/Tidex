# Checks before the next release

Things to try on a device before the next App Store or TestFlight release. Go through every item before you ship. Once the release is out, delete the items and keep the empty file.

Hjalmar confirmed the first three checks passed on Cold Harbor on 2026-10-28.

- [x] Install the App Store version, sign in, turn on flight mode, update to N+1 and open it. The sign-in screen shows. Turn flight mode off and wait up to 15 seconds. The app signs you in to the same account by itself.
- [x] Repeat that, but sign in by hand to a different account before the 15 seconds pass. You stay in the account you chose, and the old account doesn't take over.
- [x] While the app on the phone syncs a shift you just added offline, start or end an impersonation as admin. The shift stays with the account that made it, on the phone and on the server.
- [ ] On a phone, check that a matching-account push shows its sender, message, badge and reply action. Switch accounts or sign out while a push for the old account is in flight. It may show a neutral Tidex alert, but no old-account content or reply action.
