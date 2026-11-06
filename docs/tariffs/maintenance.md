# Maintain the reviewed tariff catalogue

The reviewed catalogue is checked in under `backend/convex/lib/tariffCatalogue/`. Its revision is `2026-11`. Public queries serve it only when a compatible client sends that revision. Calls without the argument retain the original database catalogue.

The 48 stored configurations are grouped into 21 selectable families by explicit presentation metadata. Each configuration keeps its existing tariff ID. Family, option tuples and category compatibility are validated; names are never parsed to infer an agreement.

The checked-in catalogue contains source URLs, legal effective dates, the app activation date, category labels, reviewed pay rules, the verification date, and the next review date. The November catalogue activates on 6 November 2026. Existing wage snapshots and earlier tariff versions remain unchanged. HK's earlier backpay must not be duplicated.

## Validate and export

Run these commands from the repository root:

```sh
bun backend/scripts/tariffs.ts validate
bun test backend/scripts/tariff-catalogue.test.ts backend/scripts/payroll-tariff-rules.test.ts
bun run --cwd backend typecheck
bun backend/scripts/tariffs.ts export --output ios/TidexApp/Storage/Testing/TariffCatalogueFixture.json
```

The fixture is the actual catalogue used by the debug UI journey. Its drift test fails when the export changes without regeneration. It contains public rates and sources, not user records.

`validate` rejects duplicate agreement or category IDs, missing labels, nonfinite or nonpositive wages, malformed dates, invalid rule windows, and missing source provenance. It does not certify an interpretation of an agreement. Review the final published table and protocol before changing monetary data.

## Review the official sources

Run the review command monthly, and weekly during active wage settlements:

```sh
bun backend/scripts/tariffs.ts review
bun backend/scripts/tariffs.ts review --as-of 2026-12-01
```

The command prints overdue agreements with their sources and exits with status 1 if any review is due. `--as-of` makes the check reproducible. The first review is due on 1 December 2026. A source change never writes rates automatically.

Open each agreement's `source_urls`, compare the final rate table and approved protocol with the data, then update `verified_on` and `review_on` only after completing that review. Do not infer approval from a proposal or a voting brochure. Some official URLs replace the document in place. For example, HK's Handelsoverenskomsten link now contains the 2026-2028 text.

Read dated legal decisions as well as summary pages. The fish-processing regulation effective 6 November 2026 is newer than the general minimum-pay page's August repeal notice.

Holiday dates are compiled for 2026-2028. The app refuses a new reviewed selection after `valid_through`. Extend the calendar and rerun boundary examples before extending that date. Do not use the validity date as a promise that future wage settlements have been reviewed.

## Compare production without writing

```sh
bun backend/scripts/tariffs.ts diff --output /tmp/tidex-tariff-diff.json
```

This uses only the public `tariffs:versions` query. It does not load an administrator key, write tariff rows, or edit wage snapshots. Each difference contains the legacy published record and the reviewed version.

To compare a local deployment, add its explicit URL:

```sh
bun backend/scripts/tariffs.ts diff --url http://127.0.0.1:3210 --output /tmp/tidex-tariff-local-diff.json
```

Publishing the reviewed catalogue happens through a reviewed backend deployment. Do not copy rich rule JSON into legacy tariff tables. Old clients cannot calculate those rules.

## Inventory affected jobs

The internal maintenance queries require a deployment administrator key. They are not exposed to app sessions. Use an explicit env file so the deployment is visible in the command.

Before inspecting jobs, identify the exact App Review account ID and supply it with `--exclude-user-id`. This work did not identify or read that account. An empty exclusion list is rejected. Do not guess the account from its demo job names.

```sh
bun backend/scripts/tariffs.ts impact \
  --env-file backend/.env.production \
  --exclude-user-id '<App Review user UUID>' \
  --as-of 2026-11-06 \
  --output /tmp/tidex-tariff-impact.json
```

The query paginates active jobs and emits only aggregate counts. It compares the applicable saved rate with the reviewed category. A higher saved wage is not an error. Custom pay and an unknown category are not automatically mapped to the minimum.

Production deployment and correction writes require approval under the repository deployment rule. Read-only inventory is permitted. No production wage inventory or correction was run during this implementation.

## Prepare a future snapshot correction

A proposal targets one explicit job and the expected source snapshot revision. It refuses stale revisions, an existing snapshot on the proposed date, excluded users, unknown categories, and dates outside verified coverage.

```sh
bun backend/scripts/tariffs.ts proposal \
  --env-file backend/.env.production \
  --exclude-user-id '<App Review user UUID>' \
  --job-id '<job UUID>' \
  --snapshot-id '<current wage snapshot UUID>' \
  --expected-revision 123 \
  --from-date 2026-11-06 \
  --output /tmp/tidex-tariff-proposal.json
```

The private proposal must be written under `/tmp`. It contains the original setup, the proposed rate and rules, and their differences. It performs zero writes. It keeps a saved base wage above the minimum. Tax, breaks, and other source settings remain in the template.

Review custom supplements before using that template. The proposed tariff rules are a comparison, not authorization to replace the worker's own rules. Confirm qualification, work schedule, and the agreement itself. A tariff ID alone cannot establish those facts.

There is deliberately no automatic snapshot apply command. Release compatible clients first, review each correction and its date, then implement a task-specific transaction with a revision check. Compensation for past earnings remains a separate operation. Protocols can exclude historical recalculation of overtime and allowances, so ordinary rate updates cannot calculate backpay safely.

## Supported estimates and explicit limits

The catalogue includes standard HK-Virke retail, Riksavtalen occupation/seniority/night-role variants, security schedules with fagbrev categories, NHO Handelsoverenskomsten and Butikkoverenskomsten, energy stations, NHO and Virke cleaning, Grossistoverenskomsten, statutory sectors, KS chapter 4 non-teaching roles, and PBL.

Each choice describes what the calculation covers. The following work needs facts the app does not yet store:

- Daily or scheduled overtime needs the contractual workday anchor, ordinary shift boundaries, and averaging agreement. A weekly threshold remains an estimate. KS and Grossist shift overtime are disabled because a clock-based percentage would give a false result.
- KS night pay after 06:00 depends on a qualifying night shift. It cannot be applied to every early-morning hour. The current catalogue marks it for manual adjustment.
- Spekter hospital pay needs the agreement area, union, role, and employer's B agreement. No universal hospital preset is published.
- Shipyard shift and overnight-assignment allowances need the actual shift arrangement and assignment status. Only the day-work statutory floor is offered.
- Minimum call-out payments, paid absence, local allowances, and expenses remain outside ordinary worked-shift pay. They are recorded in each relevant coverage note.

These limits are explicit records in `unavailableTariffs` and user-visible coverage notes. They must not be described as complete payroll support in release notes.

## Release and rollback

Merge and deploy the compatible backend before releasing the client. Verify the reviewed 48-choice query and the unchanged five-choice legacy query. Release the client only after its source, category, and saved-pay journeys pass. Monitor capability errors from older devices before preparing any existing-job corrections.

Before any reviewed wage snapshots exist, the feature can be rolled back with the client and backend changes together. Once rich snapshots have been saved, keep the capability checks and compatible payroll engines. Rolling the backend back past those checks would let older clients misread or erase saved rules. Correct the affected catalogue entry and ship a compatible fix instead. Do not delete or rewrite saved snapshots to make rollback easier.

The baseline and tariff PR are integrated into local `main`. Local `main` still contains unpublished work. The user authorized the matching backend for the phone build. The compatible backend and additive family metadata were deployed on 6 November after backups and live verification. Existing wage snapshots were not migrated.
