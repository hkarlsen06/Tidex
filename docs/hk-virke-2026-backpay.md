# HK/Virke 2026 Backpay Runbook

This runbook covers the one-off HK/Virke 2026 backpay adjustment and the later app-facing tariff-rate update.

## Scope

- Backpay and operational wage-update script: `scripts/hk-virke-backpay.ts`
- Package command: `pnpm tariff:hk-virke:backpay`
- Backpay period: `2026-02-01` through `2026-05-31`
- Payout month seed: `2026-06-15`
- Adjustment payout dates: each job's adjusted June 2026 payroll date, using the same Tuesday-Friday/non-holiday adjustment as the app
- Operational tariff effective date for the app: `2026-06-01`
- Adjustment marker: `hk_virke_2026_backpay`
- Source page: `https://www.virke.no/tariff-og-lonn/finn-tariffavtale/landsoverenskomsten-hk/#sistenyttavtale`

The script supports separate apply modes:

- `--apply-operational-wage-snapshots` writes or updates `public.wage_snapshots` rows effective `2026-06-01` for each active job whose current snapshot uses the HK/Virke tariff.
- `--apply-backpay` writes `public.payroll_adjustments` rows for historical backpay.
- `--apply` runs both apply modes, and is only valid once both guard dates have passed.

It does not edit shifts, recurring shifts, jobs, historical wage snapshots, or historical tariff versions. If a `2026-06-01` wage snapshot already exists for an eligible tariff job, the operational apply updates only that row's tariff fields (`hourly_wage`, `wage_level`, `tariff_type_id`) and preserves tax, break, and supplement settings.

Backpay adjustment rows must use the app-visible payout date for the job, not the raw 15th. For June 2026 this means payroll-day 10 jobs use `2026-06-10`, while payroll-day 15 jobs use `2026-06-12` because `2026-06-15` is a Monday and the app adjusts payroll dates backwards.

## Tariff Values

The script calculates old-vs-new payroll with the shared payroll engine.

Trinn 6 guarantee from `2026-02-01`:

| Level | Target hourly rate |
| --- | ---: |
| 6 | 261.14 |

April increase from `2026-04-01`:

| Level | Target hourly rate |
| --- | ---: |
| -2 | 139.40 |
| -1 | 136.41 |
| 1 | 195.04 |
| 2 | 195.88 |
| 3 | 197.96 |
| 4 | 203.55 |
| 5 | 221.31 |
| 6 | 271.64 |

## Production Dry-Run Result

Corrected pre-apply dry run against production data on `2026-06-01` after fixing conflict exclusion scope:

| Metric | Value |
| --- | ---: |
| Eligible jobs | 18 |
| Users with adjustments | 7 |
| Adjustment rows | 7 |
| Actual shifts included | 119 |
| Generated recurring shifts included | 19 |
| Conflicting entries excluded | 0 |
| Total gross backpay | 8942.96 kr |
| Operational wage snapshots to create | 0 |
| Existing `2026-06-01` wage snapshots | 18 |
| Operational wage snapshots skipped without an increase | 0 |
| Existing marker rows before apply | 0 |

Eligibility includes legacy HK/Virke snapshots where `tariff_type_id IS NULL`.

Operational snapshot apply status on `2026-05-29`:

| Metric | Value |
| --- | ---: |
| `2026-06-01` HK/Virke wage snapshots inserted | 19 |
| Existing `2026-06-01` HK/Virke wage snapshots updated | 1 |
| Explicit `hk_retail` source snapshots | 3 |
| Legacy `NULL` tariff source snapshots | 16 |
| Existing backpay marker rows after operational apply | 0 |

After the operational apply, dry runs should report `0` operational wage snapshots to create or update. The current active-job count is `18`; older notes expected `20` before two job-state/default-snapshot details were reconciled.

## Adjustment Row Review

The corrected dry run produces 7 adjustment rows.

| User | Job | Level | Dates | Sources | Paid hours | Rate delta | Amount | Assessment |
| --- | --- | ---: | --- | --- | ---: | ---: | ---: | --- |
| Deltid i butikk user | Deltid i butikk | 6 | 2026-04-02..2026-05-30 | 37 shifts | 239.50 | 15.50 | 3712.25 | Corrected from cross-user conflict exclusion. Payroll date `2026-06-12`. |
| Hjalmar Karlsen | Coop | 3 | 2026-04-01..2026-05-30 | 18 shifts, 6 recurring | 152.00 | 10.50 | 1595.91 | Matches the Wagey April-May paid-hour total; includes generated recurring shifts with no same-job actual conflict. Payroll date `2026-06-10`. |
| Ask Hoaas | Jobb | 1 | 2026-04-08..2026-05-30 | 22 shifts, 4 recurring | 137.90 | 10.50 | 1447.93 | Corrected from cross-user conflict exclusion. Payroll date `2026-06-10`. |
| FERDIN KHAWAJA | Job | 6 | 2026-02-02..2026-02-28 | 20 shifts | 163.11 | 5.00 | 815.55 | Matches trinn 6 February guarantee exactly: `163.11 * 5.00`. |
| Ibsen | Rema | 6 | 2026-04-08..2026-05-01 | 5 shifts | 41.50 | 15.50 | 643.32 | All 5 actual shifts are included, including 2026-04-08. Difference from simple hours math is 0.07 kr rounding through payroll engine. |
| Øyvind Hansen | Rema | -1 | 2026-04-29..2026-05-31 | 11 shifts, 1 recurring | 57.75 | 6.50 | 375.38 | Corrected from cross-user conflict exclusion. Payroll date `2026-06-10`. |
| isak | Job | -2 | 2026-04-04..2026-05-21 | 6 shifts, 8 recurring | 54.25 | 6.50 | 352.62 | Corrected from cross-user conflict exclusion. Payroll date `2026-06-10`. |

The rows make sense under the chosen rules:

- Trinn 6 has separate February/March treatment, then April treatment.
- Other levels only receive April/May backpay.
- Actual shifts are preferred over generated recurring shifts when they overlap for the same user/job/date.
- Generated recurring shifts are included when no actual conflicting shift exists.
- Amounts use `computeShift`, so percentage/custom supplements can change when base hourly wage changes.
- Isak's Påskeaften custom supplement was changed from `percent: 100` to fixed `rate: 132.90` because a percentage supplement would otherwise increase with the new tariff rate and overpay backpay unless a local agreement explicitly required that.

## How To Run

Use a Supabase secret/admin key only in the shell environment. Do not commit or paste the key into files.

```bash
export SUPABASE_URL="https://iuwjdacxbirhmsglcbxp.supabase.co"
export SUPABASE_SECRET_KEY="..."
```

`SUPABASE_SERVICE_ROLE_KEY` is still accepted for legacy environments, but this project has legacy API keys disabled.

Check the script:

```bash
pnpm dlx deno-bin@2.2.7 check --no-lock --config supabase/functions/deno.json scripts/hk-virke-backpay.ts
```

Dry run:

```bash
pnpm tariff:hk-virke:backpay
```

Expected dry-run shape before apply:

```text
HK/Virke 2026 backpay dry-run
Operational tariff effective date: 2026-06-01
Backpay period: 2026-02-01..2026-05-31
Payout month seed: 2026-06-15
Backpay eligibility date: <today>
Operational eligibility date: 2026-06-01
Eligible backpay jobs: 18
Eligible operational jobs: 18
Adjustment groups: 7
Shifts included: 119
Recurring shifts included: 19
Conflicting entries excluded: 0
Total gross backpay: 8942.96 kr
Operational wage snapshots for 2026-06-01: 0
Existing operational wage snapshots skipped: 18
Operational wage snapshots skipped without an increase: 0
No rows inserted. Re-run with --apply, --apply-backpay, or --apply-operational-wage-snapshots after approval.
```

Before apply, verify no previous run exists:

```sql
select id, user_id, job_id, amount, payout_date, note
from public.payroll_adjustments
where deleted_at is null
  and category = 'retro_pay'
  and note ilike '%hk_virke_2026_backpay%';
```

The generated adjustment rows should use Norwegian user-facing fields:

| Column | Value |
| --- | --- |
| `description` | `Tariffoppgjøret HK - Virke 2026` |
| `curated_note` | `Les mer om lønnsøkningen din` |
| `curated_description` | `De nye satsene i tariffoppgjøret gjelder også for vakter som allerede er jobbet. Siden disse vaktene først ble beregnet med gammel sats, får du en egen etterbetaling som dekker forskjellen mellom gammel og ny lønn. Trykk nedenfor for å lese nøyaktig hvordan lønnen din økte.` |
| `curated_link` | `https://www.virke.no/tariff-og-lonn/finn-tariffavtale/landsoverenskomsten-hk/#sistenyttavtale` |
| `curated_link_title` | `Se tariffavtalen hos Virke` |

Apply operational wage snapshots only after approval:

```bash
pnpm tariff:hk-virke:backpay -- --apply-operational-wage-snapshots
```

The script refuses operational wage snapshot apply before `2026-05-27`.

Apply backpay after the backpay period is complete:

```bash
pnpm tariff:hk-virke:backpay -- --apply-backpay
```

The script refuses backpay apply before `2026-06-01`.

After apply, verify that 7 adjustment rows exist:

```sql
select user_id, job_id, amount, currency, description,
       curated_note, curated_description, curated_link, curated_link_title, note,
       earned_from_date, earned_to_date, payout_date
from public.payroll_adjustments
where deleted_at is null
  and category = 'retro_pay'
  and note ilike '%hk_virke_2026_backpay%'
order by amount desc;
```

Also verify that 18 direct operational wage snapshots exist for active HK/Virke jobs:

```sql
select ws.id, ws.user_id, ws.job_id, j.name as job_name,
       ws.from_date, ws.hourly_wage, ws.wage_level, ws.tariff_type_id
from public.wage_snapshots ws
join public.jobs j on j.id = ws.job_id
where ws.deleted_at is null
  and j.deleted_at is null
  and j.archived_at is null
  and ws.from_date = date '2026-06-01'
  and ws.tariff_type_id = 'hk_retail'
  and ws.wage_level in (-2, -1, 1, 2, 3, 4, 5, 6)
order by ws.user_id, j.name;
```

Expected rows: 18 active direct rows. Two additional active jobs can inherit a default-job June snapshot; do not use this verification query alone as eligibility proof.

Inserted wage snapshots copy supplements, tax settings, and break settings from each job's current snapshot. Existing `2026-06-01` snapshots keep their existing supplements, tax settings, and break settings. The operational apply only sets the new stored hourly wage for the same tariff level and normalizes legacy HK/Virke snapshots from `tariff_type_id IS NULL` to `tariff_type_id = 'hk_retail'`.

## Recovery

If an applied run is wrong, soft-delete the generated rows and rerun after fixing the script.

```sql
update public.payroll_adjustments
set deleted_at = now()
where deleted_at is null
  and category = 'retro_pay'
  and note ilike '%hk_virke_2026_backpay%';
```

The source of truth remains the database shifts, recurring shifts, jobs, and snapshots. The generated adjustment and wage snapshot rows are amendable.

If the operational wage snapshots need to be removed, first capture the generated snapshot IDs from the verification query and soft-delete exactly those IDs:

```sql
update public.wage_snapshots
set deleted_at = now()
where deleted_at is null
  and id in (
    -- paste the verified generated wage_snapshot ids here
  );
```

## Adding The App-Facing Tariff Rates

Do not add historical app-facing tariff versions for `2026-02-01` or `2026-04-01`; that would make app tariff lookups alter historical calculations. The historical difference is represented by the post-payment adjustments above.

When the new tariff should become active for normal app calculations, add one `hk_retail` tariff version effective `2026-06-01`.

Use a migration in `supabase/migrations/`, created with:

```bash
supabase migration new add_hk_virke_2026_tariff_version
```

Migration body:

```sql
insert into internal.tariff_versions (
  tariff_type_id,
  effective_date,
  name,
  rates,
  supplements
)
select
  'hk_retail',
  date '2026-06-01',
  '2026 Tariff (June)',
  '{
    "-2": 139.40,
    "-1": 136.41,
    "1": 195.04,
    "2": 195.88,
    "3": 197.96,
    "4": 203.55,
    "5": 221.31,
    "6": 271.64
  }'::jsonb,
  '{
    "rules": [
      { "days": [1, 2, 3, 4, 5], "from": "18:00", "to": "21:00", "rate": 22 },
      { "days": [1, 2, 3, 4, 5], "from": "21:00", "to": "24:00", "rate": 45 },
      { "days": [6], "from": "13:00", "to": "15:00", "rate": 45 },
      { "days": [6], "from": "15:00", "to": "18:00", "rate": 55 },
      { "days": [6], "from": "18:00", "to": "24:00", "rate": 110 },
      { "days": [7], "from": "00:00", "to": "24:00", "rate": 115 }
    ]
  }'::jsonb
where not exists (
  select 1
  from internal.tariff_versions
  where tariff_type_id = 'hk_retail'
    and effective_date = date '2026-06-01'
);
```

Apply with:

```bash
supabase db push
```

Verify through the public RPC used by iOS:

```sql
select *
from public.get_tariff_version_for_date('hk_retail', date '2026-06-01');
```

Also verify the version list returns the new version first:

```sql
select *
from public.get_tariff_versions('hk_retail')
limit 1;
```

The iOS app fetches tariff data through `get_tariff_versions` / `get_tariff_version_for_date`, so no app release is required for the new rates if the RPC returns the new version correctly.
