# App Store Connect

Tidex uses the Rork App Store Connect CLI, `asc`, for metadata, screenshots and creative assets. The version in `config.json` is checked before every command. Ruby and Fastlane are no longer required.

## Setup

Install asc 6.5.3 and keep Homebrew from upgrading it independently of the repository:

```sh
brew install asc
brew pin asc
bun run asc version
```

For another machine or an exact older version, download the matching binary from the [asc releases](https://github.com/rorkai/App-Store-Connect-CLI/releases) and verify it against that release's checksums. Set `ASC_BIN` to its executable path if it is outside `PATH`. Upgrade `config.json` only after checking the replacement CLI against the commands below.

The ignored `ios/app-store/.env` symlink points to `/Users/hkarlsen06/Documents/Privat/Utviklernøkler/Secrets/Tidex/asc.env`. It contains `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_PATH`. Recreate the symlink in a fresh checkout. Environment variables override the file. The original API key is reused through a temporary private copy with mode 0600, which is removed when the command finishes. Credentials and private keys stay outside Git.

## Metadata

Run these commands from the repository root:

```sh
bun run --cwd ios generate-metadata
bun run app-store:validate
bun run app-store metadata
bun run app-store metadata --apply
```

`generate-metadata` keeps `ios/Scripts/appstore-metadata-source.json` as the English and Norwegian source and writes native asc JSON. A new version inherits the most recent earlier version's translated fields and URLs before generation. Existing translations are preserved unless `--force` is supplied to the generator. Source-only generation updates English and Norwegian. Support and marketing URLs in the JSON are preserved during generation.

`metadata/app-info/<locale>.json` holds app names and subtitles. `metadata/version/<version>/<locale>.json` holds descriptions, keywords, promotional text, release notes and URLs. The version comes from `ios/Version.xcconfig`. Generate metadata for each new version before planning its upload. Review notes live in `metadata/review-information.json`, and copyright lives in `config.json`.

To update only promotional text and review notes:

```sh
bun run app-store review-metadata
bun run app-store review-metadata --apply
```

These commands manage only the review notes field. Existing demo credentials and contact information remain unchanged. Local review-information files with additional fields are rejected. Neither metadata command deletes remote locales or manages screenshots, categories, age ratings, privacy declarations, builds or release settings.

## Screenshots

The capture and 3D rendering commands are unchanged. The uploader reads the finished artwork, validates opaque PNGs and dimensions, and stages only the selected device family:

```sh
bun run app-store screenshots --device duo
bun run app-store screenshots --device duo --locales en-US,no --apply
bun run app-store screenshots --device iphone
bun run app-store screenshots --device ipad
bun run app-store screenshots
```

The last command checks all three families. Each family must have artwork. iPhone images come from `ASConnectScreenshots/<version>/3d/<locale>/iPhone-*.png`, iPad images from `<version>/<locale>/iPad-*.png`, and Duo images from `<version>/3d-duo/<locale>/Duo-*.png`. Each current gallery has five images. Duo requires the ordered story `Duo-01.png` through `Duo-05.png`, all at 2853 x 2007, with closed and open devices inside the same canvas shape. Contact sheets and raw captures are excluded. The story length is an editorial choice; Apple allows up to ten Duo images.

By default, uploads skip existing matching files. Add `--replace` to replace only the selected device sets in the selected languages. Other device sets and languages remain untouched. Every selected set is planned before the first write. A multi-set upload is not atomic, so keep partial receipts after a failure and rerun or inspect them before replacing again.

Use `--version 3.1.2` to select an explicit version and `--assets-dir <directory>` to select a different version's artwork directory. These flags never create a version or rebuild images. The default directory follows the selected version.

## Creative assets

```sh
bun run screenshots:creative
bun run screenshots:creative:upload
bun run screenshots:creative:upload --apply
```

The creative uploader uses asc to upload Asset Library images, wait for processing and place the header and search assets. It preserves existing placements and reuses completed uploads with the same content hash after an interruption. Unfinished or failed uploads are reported for inspection rather than deleted. Pass an artwork directory as the final argument, or select languages with `--locales en-US,no`.

## Applying changes

All Tidex upload commands default to read-only dry runs with `ASC_READ_ONLY=1`, which makes asc reject mutating API requests. `--dry-run` is also accepted explicitly. `--apply` enables writes after preflight and requires the exact requested iOS version to be editable. A dry run can inspect a live version but does not prove that Apple will accept an upload there.

The commands never upload a binary, create a version, submit for review or release the app. Apple still controls processing and approval. Read [RELEASE_CHECKS.md](../../RELEASE_CHECKS.md) before a requested release.

Use `bun run asc <command> ...` for native asc operations with the same pinned binary and credentials. This is a direct CLI entry point and does not add the upload commands' dry-run default. Pass `--read-only` for read-only diagnostics. Continue using the repository's Xcode wrappers for builds and tests because they hold the shared Mac locks.

Local verification:

```sh
node --test scripts/test-app-store.mjs
python3 scripts/test-capture-app-store-screenshots.py
bun run app-store:validate
```
