# Convex runtime packaging

The November 7, 2026 deployment uses official release
[`precompiled-2026-11-06-a7376b7`](https://github.com/convex/convex-backend/releases/tag/precompiled-2026-11-06-a7376b7),
revision `a7376b736164c8366c601ec97a02dec27d3370ec`.
Upstream marks this newest published precompiled build as a prerelease. GitHub’s
`releases/latest` endpoint selects the older October 22 stable build, so it is not
the selector for the user-requested newest precompiled runtime.
The Docker `latest` tag lagged this release when checked. `release.json` pins the
release assets, startup scripts, license, official base image, and Ubuntu jemalloc
package by SHA-256. `build.py` verifies downloads before using them.

The backend image retains the official image's startup behavior and Node runtime,
replaces its executable and scripts with the newer official release, and packages
Ubuntu 24.04 `libjemalloc2` 5.3.0-2build1. Its allocator settings are:

```text
LD_PRELOAD=/usr/local/lib/libjemalloc.so.2
MALLOC_CONF=background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:1000
```

jemalloc reuses allocations and returns unused pages to the operating system.
It reduces allocator retention; it does not eliminate live application state,
query work, or real memory leaks. The existing 2560 MiB Paeonia and 2048 MiB Tidex
caps remain. Paeonia's expensive badge query is a separate application bottleneck.

The dashboard image serves the official release's static export with a small native
Node HTTP server running as UID 1001. It supplies only the public deployment URL
through the export's `__NEXT_DATA__`; admin credentials remain in the dashboard's
existing sign-in flow. This avoids pairing the newest backend with an older dashboard
image or compiling a separate dashboard release. The server supports the exported
HTML routes, static assets, HEAD requests and the existing credential form.

`/version` returns `unknown` in the official precompiled binary. Release verification
therefore hashes `/proc/<pid>/exe`, checks its source-revision label, and checks the
process's actual mapped jemalloc library. A successful HTTP health endpoint alone
is insufficient.

The amd64 release was exercised on `one-s`. The release lock also contains arm64
assets for a future Mac build; that build and the Mac development database were not
changed or tested in this deployment. Tidex's dev Compose images are separately
pinned. Paeonia's native local development backend remains managed by its CLI.

The newest backend upgrades Tidex's internal database from 133 to 134; Paeonia was
already on 134. Downgrading an upgraded database in place is not a recovery strategy.
Rehearsals restore the pristine old data before starting the old engine.

The production Paeonia storage mode remains S3/R2, including
`STORAGE_MAX_INTERMEDIATE_PART_SIZE=5242880`. A physical database copy cannot switch
its persisted S3 prefixes to local storage. The rehearsal copies all modules, files
and search objects into a private S3 adapter, retains the original bucket names and
prefixes, and substitutes test-only credentials. Production recovery checkpoints all
five buckets while the backend is stopped, including exports and snapshot imports.
