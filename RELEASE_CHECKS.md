# Checks before the next release

Things to try on a device before the next App Store or TestFlight release. Go through every item before you ship. Once the release is out, delete the items and keep the empty file.

## Swift 6 runtime isolation

Swift 6 mode checks actor isolation at runtime. A callback that a framework calls off the main thread now crashes instead of racing.

- [x] Sign in with Apple, Google and a passkey.
- [x] Receive a chat push, both in the foreground and when tapped.
- [x] Send a message via Siri.
- [x] Start and end a Live Activity.
- [x] Sync now reads unmanaged copies of local rows. Edit a shift in airplane mode, go back online, and check that the change reaches another device. Then edit the same shift on both devices and check the merge.

## Minimum-version gate

This release is the first version that reads `https://tidex.no/app-config.json`. Without the file the app opens normally, so the gate only works once the marketing site with that file is deployed.

- [x] Deploy the marketing site and open `https://tidex.no/app-config.json` in a browser.
- [x] With `maintenance` set to true, the app shows the maintenance screen when it comes to the foreground, and Try again opens the app once it's set back to false.
- [x] With `minimumVersion` above the installed version, the app shows the update screen and its button opens Tidex in the App Store. Set it back to `3.0.0` afterwards.
