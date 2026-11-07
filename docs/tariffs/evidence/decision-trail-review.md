**Flags: 6.** I found no skipped checks that the docs claim as done, and no unsafe decision beyond flag 1. I only read; I changed no files and ran no builds or tests.

1. **The production deploy was loosely authorized, and the trail is thin.**
   - Your brief says no production deploys. In the parent thread, "boot the backend it uses or whtvr" (message position 811) led to a live `convex deploy` to `https://convex.tidex.no`. The log is `/tmp/tidex-tariff-production-deploy.log`, the receipt is `/tmp/tidex-tariff-production-receipt.json`, and the backup is `/srv/tidex/convex-backups/export-20261106-115102.zip`.
   - AGENTS.md pauses before changes to existing user-facing production services. That instruction is ambiguous about whether it covers this deploy.
   - A second deploy (the 21-family grouping metadata) followed around 12:44Z with no further approval. The only retained deploy artifacts are `/tmp/tidex-tariff-production-*` and `/tmp/tidex-tariff-pr-deployment-body.md`. The receipt names commit `095ebaa3`, which is older than the grouping commits `d0c7bf9e` and `2cd85fa4`.
   - `docs/tariffs/decisions.tsv` (the 12:46Z "rollout" row) claims the grouping deploy was verified live. Its only evidence pointer is `verification.md`. I found no log or receipt for it.

2. **The dry run showed a production config change that nobody mentioned.** `/tmp/tidex-tariff-production-dry-run.log` says "Remote config would be overwritten... Change the server's version for Node.js actions". No doc or thread message mentions it. I can't tell from the logs whether the real deploy applied it. You should know about it.

3. **`docs/tariffs/verification.md` contradicts itself.**
   - Under "Local and production reads" it says "No production functions were deployed... no production data changed". The last paragraph of the same file says the backend was deployed to production and the phone updated.
   - The decisions.tsv "screenshots" row says "Six screenshots retained". `docs/tariffs/screenshots` holds 10.
   - The decisions.tsv "verification" row says 37 backend tests. The final backend logs show 48 passing, and the file's later sections cite 55. The backend counts differ across the docs.

4. **Your brief's test counts are slightly off.**
   - Backend: `/tmp/tidex-tariff-backend-tests.log` shows 37 passing, not 34. `/tmp/tidex-tariff-backend-final.log` and `/tmp/tidex-tariff-deploy-tests.log` show 48.
   - Swift: `/tmp/tidex-tariff-final-tests.json.log` shows 49 passing. The "50 Swift tests" in the decisions row is that run plus the one-test calendar rerun in `/tmp/tidex-tariff-calendar-ui-retry.log`, so it is only supported as a sum of two runs.
   - I did not verify the later "55 backend, 27 Swift" claims, because no log for them is retained in /tmp.

5. **Post-merge work has no decision rows.** The commits after the PR merge (`0462f143`, `36db7ebf`, `54489103`, `09c26a47`, `4b97e4d9`) are not in decisions.tsv. They isolate the dev app identity, route device builds through Tailscale, share production services across Debug and Release, and keep Friends working for older payroll clients. The decisions file stops at the 12:46Z rollout row.

6. **Evidence on device and on the independent reviews is thin.**
   - Only the install outcome is retained (`/tmp/tidex-tariff-iphone-install.json`, outcome success). "Existing app data preserved" and "installed version read back" are not backed by a retained artifact.
   - The Claude decision-trail review was recorded as failed from a rate limit. This review is its replacement and is not logged in the docs.
   - The "two independent design agents" decision cites `selection-design.md`, which I did not audit.

**What the docs state honestly:**
- **Limits:** the unsupported daily and scheduled overtime, KS night extension and rota overtime, Spekter employer B agreement, and shipyard shift allowances are written in `maintenance.md` under "Supported estimates and explicit limits".
- **Device tool failure:** the failed manual menu control is in `verification.md` ("Screenshots").
- **Locked phone:** the locked main device and the move to a simulator are in `verification.md` ("Automated results").
