# Checks before the next release

Things to try on a device before the next App Store or TestFlight release. Go through every item before you ship. Once the release is out, delete the items and keep the empty file.

## Swift 6 runtime isolation

Swift 6 mode checks actor isolation at runtime. A callback that a framework calls off the main thread now crashes instead of racing.

- [ ] Sign in with Apple, Google and a passkey.
- [ ] Receive a chat push, both in the foreground and when tapped.
- [ ] Send a message via Siri.
- [ ] Start and end a Live Activity.
