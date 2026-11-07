# Retained tariff evidence

These artifacts were copied from the original task's temporary files on 7 November 2026. `manifest.json` records their original basenames and retained-file SHA-256 hashes. Two dry-run logs have trailing whitespace trimmed; their original source hashes and that normalization are recorded separately. The logs contain public test names, synthetic test values, build summaries and deployment status. They contain no deployment credentials or customer wage records.

`receipts.json` combines the original reviewed-catalogue receipt, a reconstructed grouping-deployment receipt, a filtered historical device readback and fresh read-only production probes. The reconstruction is labeled as such. It is not a contemporaneous receipt, and the first receipt's timestamp is its capture time rather than a recorded server commit time.

The full installed-app inventory was not copied. Only Tidex's bundle identifier, version and build are retained. Successful in-place installation and version readback do not constitute a before/after inspection of every stored user record.

Test phases are separate:

| Artifact | Result |
| --- | --- |
| `backend-initial.log` | 37 backend tests |
| `backend-reviewed.log` | 48 backend tests after calculation fixes |
| `backend-grouped.log` | 55 backend tests after grouping metadata |
| `backend-postmerge.log` | 61 backend tests on 7 November, including sharing compatibility |
| `swift-initial.log` | 49 tests in one run |
| `swift-calendar.log` | One additional calendar editor test |
| `swift-overtime.log` | 22 overtime tests in a later recheck |
| `swift-conflict-and-ui.log` | Eight conflict and UI tests |
| `swift-grouped-model.log` | 17 service and selection tests |
| `swift-grouped-ui.log` | Ten UI journeys |

The early "50 Swift tests" checkpoint is 49 plus the additional calendar test, not one 50-test run. The grouped-selection result is 17 plus 10, totaling 27 tests. Reruns overlap, so the rows must not all be added together.

`decision-trail-review.md` is the completed Claude Sonnet 5.5 report. Its flags are preserved verbatim, including claims corrected by the subsequent artifact check. Read [the disposition](../audit-followup.md) alongside it.
