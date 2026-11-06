# Tidex tariff audit and implementation plan

Checked 6 November 2026. This report covers every agreement currently returned by production, the calculation model that applies them, and a shortlist of additions. It does not change rates, wage snapshots, or production configuration.

## Findings

The current base rates match the published tables for the categories Tidex offers. That does not mean the agreements are fully supported. Riksavtalen has wrong supplement windows and the wrong default night category. Its manual-work night rate also comes from preliminary material rather than the final table. The app uses HK category labels for every agreement. Vekter lacks reduced-week wage tables and automatic fagbrev pay. Overtime replaces ordinary supplements for every agreement, although Riksavtalen requires those supplements to continue.

Fix these calculation and selection problems before expanding the catalogue. Then add the missing retail agreements, energy stations, full cleaning agreements, and statutory hospitality pay. Develop KS support separately because it needs more than another hourly rate table.

These priorities are product judgments based on fit with a shift and earnings app. No customer-demand or tariff-usage statistics were collected, so the order among new sectors remains provisional.

## Evidence and limits

Production was queried through the public `tariffs:types` and `tariffs:versions` Convex queries. The [evidence snapshot](tariff-audit-2026-11-06-evidence.json) records the latest payload for each agreement and all version dates. No user data or secrets were retrieved.

Official sources were checked through web search and direct document reads. Published settlement protocols and final tables take priority over preliminary voting material. Several organisations still publish the 2024-2026 agreement text alongside 2026 settlements. Read them together. Historical versions were inventoried but not independently audited line by line.

Backend calculation examples below ran the repository's actual `buildWagePeriods`, `computeShift`, and `applyWeeklyOvertime` functions against the live tariff payloads. Swift implementation findings come from source inspection, not an iOS execution. No app code changed and no Xcode build or test run was needed for this research deliverable.

## What production offers

All amounts are NOK per hour. Level numbers below are stored identifiers, not interchangeable qualifications across agreements.

| Agreement ID | Latest app date | Stored base rates | Assessment |
| --- | --- | --- | --- |
| `hk_retail` | 2026-06-01 | Under 16: 136.41; under 18: 139.40. Levels 1-6: 195.04, 195.88, 197.96, 203.55, 221.31, 271.64 | Current amounts. App activation date deliberately differs from settlement dates. |
| `bygg_allmenngjort` | 2025-06-15 | Under 18: 162.44; unskilled: 239.61; unskilled with one year: 249.00; skilled: 264.32 | Current statutory floor. Not the full construction agreement. |
| `renhold_allmenngjort` | 2025-06-15 | Under 18: 185.55; adult: 236.54 | Current statutory floor. Not the full cleaning agreement. |
| `riksavtalen_hotel` | 2026-06-01 | Youth: 162.58, 176.84. Other staff without fagbrev at entry/4/10 years: 215.29, 232.51, 241.61; with fagbrev: 230.29, 247.51, 256.61 | Offered base amounts current, but incomplete categories and incorrect supplements. |
| `vekteroverenskomst` | 2026-04-01 | Six seniority bands: 246.22, 248.72, 250.92, 251.92, 253.72, 255.72 | Current 37.5-hour table only. |

Sources for the base-rate comparisons are [Virke HK](https://www.virke.no/tariff-og-lonn/finn-tariffavtale/landsoverenskomsten-hk/), [Arbeidstilsynet statutory rates](https://www.arbeidstilsynet.no/lonn-og-ansettelse/lonn/minstelonn/), [final Riksavtalen rates](https://www.fellesforbundet.no/globalassets/lonn-og-tariffsaker/tariffavtaler/overenskomster-20262028/satser-landsoverenskomst-fra-1.-juni-2026.pdf), and [NHO security settlement](https://www.nhosh.no/contentassets/385855c87911442eaf6c8fccaf866049/tariffbrev-2026-vekter.pdf).

### HK and Virke

The ordinary UB amounts match the published agreement: weekday evening 22 and 45; Saturday 45, 55, and 110; Sunday 115. The agreement excludes UB on hours paid overtime or shift supplements. Tidex's replacement of UB with overtime is consistent with that particular interaction. Night carry across midnight still needs explicit examples against the agreement before it can be certified. [HK agreement, section 14.3](https://www.virke.no/globalassets/6.tariff-og-lonn/protokoller-og-lonnssatser/landsoverenskomsten-hk/landsoverenskomsten-2024-2026-virke-hk-korrigert-14.11.2024.pdf)

The settlement applies ordinary increases from April and a level-6 guarantee increase from February. Tidex activates the new table on 1 June because earlier differences were handled through a separate backpay operation. This is documented in [the backpay runbook](hk-virke-2026-backpay.md). Do not backdate the catalogue and accidentally pay the same increase twice.

HK has qualifications, apprentices, and local wage differences outside these standard steps. The present preset must be described as the standard table. Do not invent a fixed seniority supplement where an employer determines the amount. [Virke HK settlement and seniority guidance](https://www.virke.no/tariff-og-lonn/finn-tariffavtale/landsoverenskomsten-hk/)

### Construction and cleaning statutory floors

The 2025 dates are not evidence of stale data. They remain the rates published for the statutory floors. Cleaning's night minimum is 29 between 21:00 and 06:00, which matches the stored rule. The cleaning record also contains fagbrev metadata, but that is not a substitute for a separate collective-agreement preset. [Arbeidstilsynet minimum pay](https://www.arbeidstilsynet.no/lonn-og-ansettelse/lonn/minstelonn/)

Both records use a 40-hour weekly overtime threshold and 40% overtime premium. These are simplified statutory defaults. The calculation model has no daily overtime trigger or work-schedule exceptions. They cannot be presented as complete determination of overtime entitlement.

### Riksavtalen

This is the first correctness fix.

| Rule | Production | Published agreement and current rate table |
| --- | --- | --- |
| Weekday evening | 17:00-21:00, 16.59 | 21:00-24:00, 16.59 |
| Weekend | All Saturday and Sunday, 31.52 | Saturday 14:00-24:00 and Sunday 06:00-24:00, 31.52 |
| Ordinary night work | Weekdays 21:00-06:00, 24.84 | 00:00-06:00, 58.04 for other workers; 43.94 for night guards |
| Manual work by night guards | Used as the universal night rate | Separate additional provision; final hourly figure 24.87, not preliminary 24.84 |
| UB during overtime | Replaced by overtime premium | Relevant UB continues, without overtime percentage applied to UB |

The time windows and overtime interaction are in [Riksavtalen section 4.3](https://www.nhoreiseliv.no/contentassets/3b3a903b8ed84576a60df30606b3fe5b/riksavtalen-2024---2026.pdf). Amounts are in the [final 2026 table](https://www.fellesforbundet.no/globalassets/lonn-og-tariffsaker/tariffavtaler/overenskomster-20262028/satser-landsoverenskomst-fra-1.-juni-2026.pdf). The [union agreement page](https://www.fellesforbundet.no/lonn-og-tariff/tariffavtaler/riksavtalen/) confirms approval and points to the final rates. Protocol review remains a release gate for exceptions and holiday handling.

Concrete backend runs with live data produced these ordinary-hour supplements:

- Monday 18:00-19:00: 16.59, where this evening provision should give zero.
- Monday 22:00-23:00: 24.84, where the evening rate should be 16.59.
- Tuesday 02:00-03:00: 24.84, where ordinary other-worker night pay should be 58.04.

A second run used four eight-hour shifts followed by Friday 14:00-22:00, without breaks. The last hour was overtime and returned 430.58 total per hour at a base of 215.29. With the applicable evening supplement retained, that hour is 447.17. This demonstrates the replacement problem independently of the wrong stored night rule.

Base-rate coverage also omits cooks, the under-17 category, intermediate seniority steps, and 35.5-hour schedules. Keep existing level IDs stable when adding those choices. The current six positive IDs already mean specific categories.

### Security guards

The offered rates match the 37.5-hour table. The official table also has 35.5- and 33.6-hour variants. Entry pay is respectively 260.08 and 274.81, compared with Tidex's 246.22. Fagbrev adds at least 14.50, but Tidex stores that only in `supplements.meta`. Apprentices are also absent. [NHO 2026 security settlement](https://www.nhosh.no/contentassets/385855c87911442eaf6c8fccaf866049/tariffbrev-2026-vekter.pdf)

The agreement contains holiday-eve windows, holiday premiums, special-service allowances, and overtime tied to work schedules and daily limits. The live preset represents only ordinary night/weekend additions and a weekly overtime approximation. It also applies 100% to ordinary weekday night overtime, while the agreement's general residual rule is 50%. Review the current settlement with the base text before changing this. [Security agreement sections 5 and 6](https://www.virke.no/globalassets/uploaded-files/finn-tariffavtale/vekteroverenskomsten-2024-2026-nho-service-og-handel-naf.pdf)

The backend currently chooses the maximum overlapping supplement. A Sunday 22:00-23:00 run returned 48, dropping the overlapping 28 night rule. The separate entitlements suggest a stacking problem. Confirm the interaction against the current protocol before treating 76 as the approved expected value. The engine needs agreement-specific overlap rules either way.

## Shared implementation gaps

These findings apply before adding any new agreements.

1. `TariffLevel` in `ios/TidexApp/Features/Onboarding/Models/OnboardingData.swift` labels -1 as under 16 and -2 as 16-18 for every tariff. Riksavtalen uses those IDs for 17 and 18 years. Construction and cleaning use -1 for under 18. Positive levels have generic labels instead of qualification and seniority names.
2. `TariffLevel.from` iterates only `[-1, -2, 1, 2, 3, 4, 5, 6]`. Adding rates with other IDs in Convex alone will not make them selectable.
3. `SupplementRulesSnapshot` decodes only `rules`. It discards `meta`, including security fagbrev and explanatory notes. Adding money to metadata never applies that money.
4. Both payroll implementations replace ordinary supplements when overtime starts. The backend's `periods.ts` takes the maximum overlapping supplement. Both behaviors need tariff-specific policies, with legacy behavior preserved for existing snapshots.
5. Overtime configuration contains only a weekly threshold and clock/day percentage rules. It cannot express daily limits, work-plan entitlement, some holiday windows, or alternate percentage bases.
6. Saved wage snapshots contain the actual hourly wage and rules. Publishing a new catalogue version does not itself update existing jobs. The editor preserves saved tariff rates until explicitly refreshed.
7. `TariffVersionService` caches for 24 hours and can use stale cached data on fetch failure. The bundled fallback remains the 2025 HK table. A user must not unknowingly save that fallback for another agreement.
8. `tariff_versions` stores unstructured rate, supplement, and overtime JSON. There is no source citation, verification date, expiry, or machine-checked agreement coverage in the present schema.

## Agreements worth adding

The order below is a proposed delivery sequence, not a measured demand ranking. Complete source extraction and calculation acceptance cases before activating any preset.

| Priority | Addition | Reason and work required |
| --- | --- | --- |
| First | NHO Handelsoverenskomsten | Separate retail agreement. Reuse the hourly table flow after labels and rules are fixed. Confirm scope and current rates rather than copying HK-Virke. [2026 settlement](https://hk.no/2026/06/hk-norge-og-nho-ble-enige/) |
| First | NHO Butikkoverenskomsten | Distinct from Handelsoverenskomsten and HK-Virke. The September settlement applies from May. Approval was reported on 29 September. [NHO result](https://www.nhosh.no/jus-hjelp/lonn-og-tariff/oppgjoret-2026/enighet-om-ny-butikkoverenskomsten/), [HK approval listing](https://hk.no/kategori/nyheter/oppgjor/) |
| First | Energistasjonsoverenskomsten HK-Virke | Close fit for evening and weekend shift workers. Adult rates are 196.08-256.58, youth 149.84. Approved in October with April rate effect. [Virke](https://www.virke.no/tariff-og-lonn/finn-tariffavtale/energistasjonsoverenskomsten-virkehk/) |
| First | Full cleaning agreements, NHO and Virke separately | The existing legal floor misses seniority. NHO adult bands are 247.29, 250.66, 257.39, 261.24 from June, plus fagbrev 15.50. NHO also has a separate May guarantee step. Virke's effective dates differ. [NHO final result](https://www.nhosh.no/contentassets/38c2c52065f34c9c8efb8ba648fcef41/tariffbrev-2026-renhold.pdf), [Virke](https://www.virke.no/tariff-og-lonn/finn-tariffavtale/renholdsoverenskomsten/) |
| First | Statutory hospitality minimum | Needed alongside Riksavtalen for workplaces without that collective agreement. Adult starting floor 204.79. Do not attach Riksavtalen UB automatically. [Arbeidstilsynet](https://www.arbeidstilsynet.no/lonn-og-ansettelse/lonn/minstelonn/) |
| Next | KS chapter 4 | Useful for municipal care and other shift work. Requires education group, seniority, annual salary conversion, schedule, and percentage/minimum UB. May wage tables and October supplement changes need separate versions. [KS implementation circular](https://www.ks.no/contentassets/4101c824e048412bbe4cd7bf26815b94/hovedtariffoppgjoret-2026---iverksetting-og-kommentarer-b-rundskriv-.pdf) |
| Next | Grossistoverenskomsten Virke | Warehouse and distribution work fits Tidex. Needs agreement-specific shift percentages and guarantee rules. [Virke](https://www.virke.no/tariff-og-lonn/finn-tariffavtale/grossistoverenskomsten-ff/) |
| Next | Statutory automotive minimum | New from June 2026. Clear hourly categories, but scope exclusions matter. [Arbeidstilsynet](https://www.arbeidstilsynet.no/lonn-og-ansettelse/lonn/minstelonn/) |
| Conditional | PBL | Preschool staff, including substitutes. The new settlement was approved in October. Needs annual salary and role/seniority support. [PBL](https://pbl.no/tariff-og-loenn/hoved-og-melloppgjor) |
| Conditional | Spekter hospital agreements | Valuable for healthcare, but do not create one universal hospital table. Select agreement area, union, occupation, and applicable local B agreement. [Delta 2026 hospital settlement](https://www.delta.no/lonn-og-avtaler/spekter/omrade-10/2026-2028/enighet-i-sentrale-lonnsforhandlinger-for-sykehusansatte) |
| Conditional | Other statutory sectors | Assess electrical work, agriculture, freight, tour coaches, and shipyards against actual demand. Their shift, travel, or schedule provisions need explicit coverage. [Arbeidstilsynet](https://www.arbeidstilsynet.no/lonn-og-ansettelse/lonn/minstelonn/) |
| Conditional | Fish processing | New regulation takes effect today, 6 November. Skilled 252.09, production 236.09, with youth and shift provisions. The older Arbeidstilsynet summary still describes repeal in August. Use the new decision, including the gap in validity. [Tariffnemnda decision hosted by NNN](https://nnn.no/wp-content/uploads/2026/11/Allmenngjoring-Fiskeindustribedrifter.pdf) |

## Implementation plan

### 1. Establish a reviewed catalogue and correction scope

Create a checked-in catalogue under `backend/` with stable agreement and category IDs. Include authoritative URLs, document sections, checked date, legal effective date, app activation date, supported categories, and known exclusions. Model statutory minimums separately from collective agreements.

Build a command that validates the catalogue and compares it with Convex. Default to a read-only diff. Apply only explicit additions or corrections through an internal authenticated mutation. Reject duplicate agreement/date keys, unknown categories, invalid money, invalid times, and contradictory rule definitions. Make reapplying the same revision a no-op. Never use `backend/scripts/migrate.ts`, which replaces deployment data.

Prepare a read-only aggregate of active tariff jobs, categories, effective snapshot dates, and app builds. Exclude the App Review account. Do not infer a user's qualification or agreement from an employer name. This aggregate determines which corrections need migration support first.

Deliverable: source-backed catalogue, production diff, affected-job counts, and a reviewable correction proposal. Do not overwrite existing snapshots yet.

### 2. Fix category selection and saved-rate behavior

Add explicit category labels and order to tariff data. Extend iOS decoding and both onboarding and pay settings. Keep current IDs and historical snapshots intact. Use new IDs for additional categories, and stop assuming every agreement has six steps.

For security, expose schedule variants and fagbrev choices. For Riksavtalen, expose occupation, qualification, seniority, and night role. Start with explicit presets or variants where they fit the existing model. Do not build a general rules language.

A failed fetch may retain a saved wage or offer custom entry. It must not offer HK fallback rates as another agreement's verified rates. Show source and effective date where users choose pay. Preserve local wage amounts above the minimum.

Deliverable: a device journey in which each supported worker selects the correct category and sees the saved rate survive offline use.

### 3. Correct supplement and overtime calculations

Add explicit agreement policies for overlapping supplements and UB during overtime. Apply identical semantics in Swift and backend TypeScript. Default old snapshots to existing behavior until an explicit conversion is approved.

Fix Riksavtalen's windows and final rate figures, including the distinction between ordinary night workers and night guards. Model holiday-eve intervals and their exclusions before claiming complete support. Review security overtime against the current protocol, then add schedule thresholds and holiday premiums with their actual calculation bases.

Daily overtime and scheduled-work entitlement need inputs that are not present today. Add only the inputs required by an agreed first scope, and mark unsupported arrangements clearly. A weekly threshold alone is not enough.

Deliverable: matching calculation outputs from both engines for official examples and boundary cases.

### 4. Introduce corrections without changing history silently

Separate catalogue updates, future job snapshots, and historical compensation. Use the HK backpay record as a constraint, not as a universal migration recipe. Some settlements exclude recalculation of historical overtime and allowances.

Before changing existing jobs, generate a dry-run diff with old/new rates, dates, rules, and earnings deltas. Preserve custom pay, tax, breaks, supplements, and manual adjustments. Decide explicitly whether a correction is prospective or requires historical compensation. Record its revision so retries cannot duplicate it.

Keep the existing query response usable by older iOS builds. Serve richer rules only to clients that can calculate them, or keep new variants unavailable there. A server-only data patch cannot fix an old client that drops UB during overtime.

Production deployment requires approval under the repository's deployment rule. Prepare code, checks, exact data diff, rollback, and historical-impact report before that approval step.

### 5. Add agreements in small releases

After corrections pass, add each first-priority agreement separately. For every addition, extract base rates, category eligibility, ordinary supplements, overtime, holiday rules, effective dates, and backpay exclusions. Compare the final protocol with the published wage table.

Develop KS as a separate feature with annual salary, tariff divisors, role/seniority, and supplement minimums. Do not divide every public-sector salary by one assumed annual-hours figure. Add PBL and Spekter only after those required concepts are supported.

### 6. Keep rates current

Review official sources monthly and weekly during active settlements. Distinguish proposed, approved, effective, and superseded versions. Detect changed source documents, but require review before publishing monetary rules. Recheck sector summary pages against dated decisions, as the fish-processing discrepancy demonstrates.

Store the next review date and unresolved interpretation beside each agreement. A missed review should create an internal task, not invent a new rate or silently reuse an expired entitlement.

## Verification plan

Extend existing tests where these changes affect pay or decoding. Use common outcome fixtures in both payroll implementations, derived from the official rules rather than copied from production data.

Required cases include:

- Riksavtalen evening boundaries, Saturday 14:00, Sunday 06:00, midnight, each night role, holiday eves, and UB retained during overtime.
- Security schedule variants, fagbrev included in the correct pay basis, overlapping night/weekend rules after interpretation is confirmed, and holiday premiums below the weekly overtime threshold.
- Correct category selection for hotel youth, construction youth, qualifications, and newly added categories beyond level 6.
- HK UB excluded during overtime, April/June activation differences preserved, and backpay never duplicated.
- Snapshot dates before and after a rate change, offline cached data, failed fetch with no matching tariff, and unchanged custom wages.
- Cross-midnight shifts, DST, breaks, and weekly/daily threshold transitions for every new calculation policy.

Use `TariffVersionServiceTests`, `PayrollCalculatorBehaviorTests`, and `PayrollEngineOvertimeTests` as the first focused Swift targets. Extend `ShiftJourneyUITests` when the wage-selection journey changes. Run backend calculation fixtures against the real TypeScript functions and the local Convex deployment for catalogue validation, authorization, and idempotency.

Run the repository's test wrapper with focused `-only-testing` filters. Prefer a connected device, otherwise use its shared-simulator allocation. The test wrapper builds the app, so do not build separately first. Inspect Norwegian and English category labels with accessibility text sizes on a device. Add only checks the simulator cannot cover to `RELEASE_CHECKS.md`.

## Documentation inconsistencies found

- `docs/hk-virke-2026-backpay.md` says iOS fetches tariff data through Supabase RPCs. Current code calls Convex `tariffs:types` and `tariffs:versions`. Its accounting and backpay constraints remain relevant, but its deployment instructions are legacy.
- The Riksavtalen migration describes one flat active-night supplement as a simplification. The agreement distinguishes night roles and additional manual work, and the final table gives 24.87 instead of the preliminary 24.84 copied into production.
- The cleaning tariff payload carries fagbrev metadata, while the iOS snapshot model explicitly decodes only rules. The metadata does not implement the entitlement.
- Generic model comments describe wage levels as 1-9; the actual picker accepts only two negative IDs and 1-6. Expanded rates need a picker change.

The audit records these discrepancies without editing older runbooks or changing payroll behavior.
