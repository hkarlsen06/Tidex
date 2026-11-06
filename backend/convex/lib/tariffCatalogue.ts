import { existingTariffs } from "./tariffCatalogue/existing";
import { statutoryTariffs } from "./tariffCatalogue/statutory";
import { retailTariffs } from "./tariffCatalogue/retail";
import { cleaningTariffs } from "./tariffCatalogue/cleaning";
import { publicSectorTariffs } from "./tariffCatalogue/publicSector";
import { CATALOGUE_REVISION, validateCatalogue } from "./tariffCatalogue/model";
export { CATALOGUE_REVISION, validateCatalogue } from "./tariffCatalogue/model";
export type { CatalogueEntry, CatalogueVersion } from "./tariffCatalogue/model";

export const tariffCatalogue = [
  ...existingTariffs,
  ...retailTariffs,
  ...cleaningTariffs,
  ...statutoryTariffs,
  ...publicSectorTariffs,
];
validateCatalogue(tariffCatalogue);
export const unavailableTariffs = [
  {
    id: "spekter_hospitals",
    source_url:
      "https://www.delta.no/lonn-og-avtaler/spekter/omrade-10/2026-2028/enighet-i-sentrale-lonnsforhandlinger-for-sykehusansatte",
    reason:
      "The correct area, union, job classification and employer B agreement must be selected. No universal hospital wage table is accurate.",
  },
  {
    id: "shipyard_shift_work",
    source_url:
      "https://www.arbeidstilsynet.no/lonn-og-ansettelse/lonn/minstelonn/",
    reason:
      "Shift and overnight assignment allowances require the actual shift arrangement and assignment status. The day-work statutory floor is available.",
  },
  {
    id: "daily_and_scheduled_overtime",
    source_url:
      "https://www.arbeidstilsynet.no/arbeidstid-og-organisering/arbeidstid/overtid/",
    reason:
      "A workday anchor, contracted daily schedule and averaging agreement are needed. The app currently knows only worked shifts and a weekly threshold.",
  },
  {
    id: "ks_night_extension",
    source_url:
      "https://www.ks.no/fagomrader/lonn-og-tariff/hovedtariffavtalen/endringer-i-tilleggene-i-hta-kapittel-1--5-fra-forste-oktober/",
    reason:
      "Extension of night premium to08:00 depends on a qualifying night shift. Rota overtime uses position relative to the contracted shift, not clock time. Enter these adjustments manually.",
  },
];
export function requireCatalogueRevision(revision: string): void {
  if (revision !== CATALOGUE_REVISION)
    throw new Error("Unsupported tariff catalogue revision");
}
export function exportCatalogue() {
  return {
    types: tariffCatalogue.map((entry) => entry.type),
    versions: tariffCatalogue.map((entry) => entry.version),
  };
}
export function overdueTariffs(on: string) {
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(on) ||
    new Date(on).toISOString().slice(0, 10) !== on
  )
    throw new Error("Invalid review date");
  return tariffCatalogue
    .filter(({ version }) => version.review_on <= on)
    .map(({ type, version }) => ({
      id: type.id,
      revision: version.catalogue_revision,
      verified_on: version.verified_on,
      review_on: version.review_on,
      source_urls: version.source_urls,
    }));
}
