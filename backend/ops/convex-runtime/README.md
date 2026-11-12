# Upgrade the hosted Convex runtimes

These tools manage Paeonia and Tidex on `one-s`. Run them as root there.
The application SDKs and deployed functions stay compatible with released phones.
Read [runtime packaging](runtime.md) before changing the release lock.

1. Copy this directory to `/srv/convex-runtime/source` without secrets or build output.
2. Build the pinned official assets and packaged allocator:

   ```sh
   sudo python3 /srv/convex-runtime/source/build.py --directory /srv/convex-runtime/build/cc07c9e-amd64
   ```

   Keep its `images.json`. It records the locally built immutable image references.
   Never replace those with `latest` or raw image IDs.
3. Prepare private copies of both current deployments:

   ```sh
   sudo python3 /srv/convex-runtime/source/prepare.py
   ```

   Existing `prepared.json` checkpoints are reused. To test newer production data,
   preserve the old rehearsal directory under another name before preparing again.
   Copies contain secrets and user data; keep `/srv/convex-runtime` root-only.
4. Run each upgrade and rollback rehearsal in sequence:

   ```sh
   sudo python3 /srv/convex-runtime/source/rehearse.py paeonia --images /srv/convex-runtime/build/cc07c9e-amd64/images.json
   sudo python3 /srv/convex-runtime/source/rehearse.py tidex --images /srv/convex-runtime/build/cc07c9e-amd64/images.json
   ```

   Both `result.json` files must say `complete: true`. The internal Docker network
   `convex-rehearsal` must exist (`docker network create --internal convex-rehearsal`).
   Tests use copied data, a private S3 adapter for Paeonia, and blocked internet access.
   Writes, entitlement grants and subscription mutations happen only in those copies.
   The Node subscription checker uses the installed `/srv/paeonia/cli` Convex package.
5. Get approval for existing user-facing production services, then upgrade one app:

   ```sh
   sudo python3 /srv/convex-runtime/source/upgrade.py paeonia --images /srv/convex-runtime/build/cc07c9e-amd64/images.json
   ```

   The command takes a full logical export and recovery config, then verifies their
   offsite copies by downloading them. It temporarily gates only this app's Caddy
   upstreams and pauses its backup timers. After stopping the backend, it copies all
   persistent local data (excluding transient `tmp/` executor sockets) and all configured S3 buckets and verifies SQLite and object contents.
   It replaces only the backend/dashboard image references, preserving ports,
   instance secrets, storage settings, memory caps and application environment.
   It checks the actual executable hash, mapped jemalloc library, application reads,
   row counts, real Clerk JWT authentication, rejected anonymous queries, dashboard
   HTML and assets. An existing active operator Clerk session is required; no new
   sessions are created. No diagnostic command prints its token or secret.

   Before traffic reopens, a failure restores the old Compose file, local data and
   checkpointed S3 objects. Extra unreferenced S3 objects are retained. A failed
   restoration keeps traffic closed. Once traffic reopens, failures require diagnosis
   without restoring old data over accepted writes. A fresh full export and offsite
   check must then pass before `state.json` records `complete: true`.
6. Repeat the command for `tidex`. Run the existing integration health check:

   ```sh
   ssh one-s sudo /srv/tidex/auth-smoke.sh
   ```

   Check both APIs, HTTP actions, private dashboards, container health, cgroup
   `memory.events`, and logs. Backup timers must be active again.

## Recover an interrupted maintenance window

Check `/srv/convex-runtime/checkpoints/<timestamp>-<app>/state.json` first.
Never restore a cold snapshot after traffic has reopened: it loses later writes.
A live process holds `upgrade.lock`; recovery refuses to run concurrently.

If the checkpoint has `validated: true` or `rolled_back: true` and still has
`gated: true`, revalidate it and restore only its own Caddy upstreams:

```sh
sudo python3 /srv/convex-runtime/source/upgrade.py paeonia --recover-checkpoint /srv/convex-runtime/checkpoints/<timestamp>-paeonia
```

Otherwise keep traffic closed. Stop the backend, preserve its failed data, restore
`data/` and `docker-compose.yml` from the checkpoint, and copy its `objects/<bucket>`
contents back into each original bucket with `rclone copy` and `rclone check
--one-way --download`. Use the stack's original restricted credentials; never delete
extra remote objects. Start the original images, run application/authentication
verification against `baseline.json`, and only then record `rolled_back: true` and
use the recovery command. If the cold snapshot is incomplete, use the full logical
export and config under `before/`, also copied to the immutable offsite upgrade path.

The tracked `paeonia-backup.sh` and `tidex-convex-backup.sh` are deployed to
`/srv/backup/`. Regular nightly config archives include `/srv/convex-runtime/source` and the
active build's `images.json`. Keep the old images and upgrade checkpoints until the
new release has had a sufficient observation period. Checkpoints and offsite upgrade
copies have no automatic pruning.

## Check the tools locally

```sh
node --test backend/ops/convex-runtime/dashboard-server.test.mjs
PYTHONPATH=backend/ops/convex-runtime python3 backend/ops/convex-runtime/upgrade.test.py
PYTHONPATH=backend/ops/convex-runtime python3 backend/ops/convex-runtime/backup.test.py
```

On one-s, `sudo python3 /srv/convex-runtime/source/object-storage.test.py` verifies
that recovery restores deleted and modified objects across five private test
buckets while retaining extra objects. It uses only a temporary localhost S3 server.

Live verification is read-only by default. With explicit authorization,
`verify.real_auth(project, public_url, key, write_user_id=operator_id)` also verifies
a temporary job or reversible preference change for that specific operator/test
account. JWT subscriptions use the public URL; admin mutations remain on localhost.
The test removes its job or restores its preference before completing.

Runtime and storage compatibility are checked by the isolated rehearsals and actual
post-upgrade exports. These changes do not change iOS code or require an Xcode build.
