# iOS 3.1.2 release preparation

Version 3.1.2, build `20261109.2113`, has a signed Release archive and an App Store IPA. Apple binary validation passed without errors on 2026-11-09. Submission remains on hold while the non-Siri manual checks continue.

Hjalmar clarified that his earlier decision deferred further Siri checks only. The Admin offline-refresh and Schedule Copy checks passed during release preparation. [RELEASE_CHECKS.md](../RELEASE_CHECKS.md) records the remaining checks. Keep that file until the release ships.

## Metadata

- Uploaded the current release notes in all 32 App Store locales.
- Removed keywords that repeated subtitle terms in 15 locales.
- Updated App Review notes to include the calendar, Home, Spotlight and Live Activity changes.
- Read back all 32 listings and verified that every managed field matches the local JSON.
- Verified that App Review credentials and contact details remain unchanged.
- Confirmed that all 330 screenshots in 66 sets have individual delivery state `COMPLETE`.
- Inspected representative English and Norwegian iPhone, iPad and Duo artwork.

App Store validation with public URL checks reports no metadata warnings. The draft retains manual release after approval. App Privacy publication cannot be verified through the public API because no cached Apple web session is available.

The metadata source had a stale comment saying that the generator writes TXT files. It now describes the native asc JSON output.

## Binary and verification

The archive and export ran through `scripts/xcode-build-agent.sh` with actions `archive` and `exportArchive`. Both succeeded without warnings or errors. The export preserves the archive's version and build number.

The IPA and all four extensions passed strict signature checks. They use App Store provisioning profiles for team `48ZSLD4RMP`, with debugging disabled. The app uses production Convex and Clerk configuration and the production APNs environment. The minimum supported system is iOS 26.0, and the IPA supports iPhone and iPad.

The IPA SHA-256 is `264a693ae0a170f5eff0b26e1204e947b00935dfc668193287ea7758e63ed0a3`.

Existing tests ran through `scripts/xcode-test-agent.sh`:

- All 56 tests passed on Cold Harbor across `AssistantPrivacyTests`, `AssistantEarningsTests`, `AppGateTests`, `HomeScheduleLoadingHelperTests` and `SyncOfflineBehaviorTests`.
- All three UI tests passed on Shared iPhone. They cover adding and deleting a shift, the Add layout after selecting a date, and the Schedule tab's return-to-today behavior.
- Local metadata validation passed with no warnings or errors.
- The production `auth-smoke.sh` check passed.
- SwiftLint exited successfully with 272 existing warnings and no errors. This preparation changes no Swift code and adds no tests.

The archive uses app source at `aa09a692` and the pre-existing Xcode project and string-catalog edits in the main checkout. Those unrelated edits remain uncommitted. Release metadata is committed as `9eff64fb`.

Private artifacts and receipts are in `/Users/hkarlsen06/Library/Developer/TidexReleases/3.1.2-20261109/`. The archive is `Tidex-3.1.2.xcarchive`, and the IPA is `export/Tidex.ipa`.
