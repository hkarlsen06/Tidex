# App Store Connect and local Chat package workflow

Read this guide before uploading App Store assets or editing the forked `../Chat` Swift package.

## App Store Connect access

Tidex uses the pinned `asc` CLI for metadata, screenshot and creative-asset uploads.
Read [the workflow](../../ios/app-store/README.md) before changing or uploading App Store
assets. `bun run app-store` provides read-only plans by default. Apply with `--apply`
only when uploading is authorized. Native commands use `bun run asc <command>` and
accept `--read-only` for diagnostics. Build and test through the shared Xcode wrappers.

The ignored `ios/app-store/.env` symlink points to
`/Users/hkarlsen06/Documents/Privat/Utviklernøkler/Secrets/Tidex/asc.env`, with
`ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_PATH`. Recreate it or load the
existing credentials before asking for keys. Keep credentials outside Git.

Screenshot sets can all report `COMPLETE` while individual images are stuck.
Inspect image delivery states as well as set summaries before submitting.

## Local Chat Package Workflow

The Exyte `Chat` dependency is forked at `hkarlsen06/Chat` and is also cloned locally at `../Chat` for day-to-day development.

- The committed project is usually in `remote` mode. Check the current mode with `./scripts/check-chat-package-source.sh` before you rely on `../Chat`. Edits in `../Chat` only reach a Tidex build in `local` mode.
- Switch package source with:

```bash
./scripts/set-chat-package-source.sh local
./scripts/set-chat-package-source.sh remote
```

- `local` mode points Xcode at `../../Chat` as a local Swift package.
- `remote` mode points Xcode back at `https://github.com/hkarlsen06/Chat.git` for a portable committed state.
- When editing the package, make code changes in the sibling `../Chat` repo and commit them there, not inside `tidex`.
- Treat this as a hard rule: do not edit a resolved SwiftPM package checkout, build artifact, or any `Chat` source copy that lives under `tidex`.
- If a change should persist, it must land in `../Chat`, because that is the sustained fork repo and the source of truth for local package development.

**Release / shipping reminder:**

- If the user asks for work that implies a release or shared portable state, treat that as a reminder to check the `Chat` fork workflow.
- Examples: release, ship, App Store submission, TestFlight build, tagging a version, cutting a release, handing work off, or preparing CI-safe commits.
- Before those steps, if `../Chat` has relevant changes, remember to commit, tag, and push the `hkarlsen06/Chat` fork.
- Before committing release-oriented Tidex project changes, run `./scripts/set-chat-package-source.sh remote`.
- After release work, switch back with `./scripts/set-chat-package-source.sh local` if continuing local package development.

