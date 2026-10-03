---
description: Start iOS development mode for working on the native Tidex iOS app
---

You are now in iOS development mode for the native Tidex app in `ios/`.

Read `ios/AGENTS.md` first. Its "Where things live" section maps features to files, and it links the localization and verification guides. `ios/docs/ARCHITECTURE.md` has the directory tree and the local-first sync design.

Don't build or run tests unless the user asks or the root `AGENTS.md` exception applies. Use `./scripts/xcode-build-agent.sh` and `./scripts/xcode-test-agent.sh`, never raw `xcodebuild`.

Ask what to work on: a feature, a bug, a UI change or a performance problem.
