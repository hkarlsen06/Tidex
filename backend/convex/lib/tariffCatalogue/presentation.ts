import type {
  CatalogueEntry,
  TariffPresentation,
  TariffPresentationOption,
} from "./model";

const weekHelp = {
  help_en:
    "The full-time hours in your agreement, including if you work part-time.",
  help_nb:
    "Timene i en full stilling etter avtalen, også når du jobber deltid.",
};

function week(value: "37.5" | "35.5" | "33.6"): TariffPresentationOption {
  return {
    dimension_id: "week",
    label_en: "Contractual full-time week",
    label_nb: "Fulltidsuke etter avtalen",
    ...weekHelp,
    value,
    value_en: `${value} hours`,
    value_nb: `${value.replace(".", ",")} timer`,
  };
}

function employment(
  value: "employee" | "apprentice",
): TariffPresentationOption {
  return {
    dimension_id: "employment",
    label_en: "Employment",
    label_nb: "Ansettelse",
    value,
    value_en: value === "employee" ? "Employee" : "Apprentice",
    value_nb: value === "employee" ? "Ansatt" : "Lærling",
  };
}

function nightRole(
  value: "other" | "guard" | "manual",
): TariffPresentationOption {
  const labels = {
    other: { en: "No", nb: "Nei" },
    guard: { en: "Yes", nb: "Ja" },
    manual: {
      en: "Yes, with agreed manual work",
      nb: "Ja, med avtalt manuelt arbeid",
    },
  };
  return {
    dimension_id: "night_role",
    label_en: "Are you employed as a night guard?",
    label_nb: "Er du ansatt som nattevakt?",
    help_en: "Standard night premiums still apply when you choose No.",
    help_nb: "Ordinære nattillegg er inkludert også når du velger nei.",
    value,
    value_en: labels[value].en,
    value_nb: labels[value].nb,
  };
}

function arrangement(input: {
  value: string;
  en: string;
  nb: string;
}): TariffPresentationOption {
  return {
    dimension_id: "work_arrangement",
    label_en: "Work arrangement",
    label_nb: "Arbeidstidsordning",
    help_en: "Choose the arrangement in your employment agreement.",
    help_nb: "Velg ordningen i arbeidsavtalen din.",
    value: input.value,
    value_en: input.en,
    value_nb: input.nb,
  };
}

const day = arrangement({ value: "day", en: "Day work", nb: "Dagarbeid" });
const twoShift = arrangement({
  value: "two_shift",
  en: "Two shifts",
  nb: "2-skift",
});
const threeShift = arrangement({
  value: "three_shift",
  en: "Three shifts",
  nb: "3-skift",
});
const rota = arrangement({ value: "rota", en: "Rota", nb: "Turnus" });

function workRelationship(input: {
  value: "seasonal" | "permanent" | "animal_care_relief";
  en: string;
  nb: string;
}): TariffPresentationOption {
  return {
    dimension_id: "work_relationship",
    label_en: "Work relationship",
    label_nb: "Arbeidsforhold",
    value: input.value,
    value_en: input.en,
    value_nb: input.nb,
  };
}

type Family = Omit<TariffPresentation, "options" | "category_group">;
function family(
  input: Family & {
    variants: {
      id: string;
      options?: TariffPresentationOption[];
      category_group?: string;
    }[];
  },
): [string, TariffPresentation][] {
  const { variants, ...metadata } = input;
  return variants.map(
    ({ id, options = [], category_group = input.family_id }) => [
      id,
      { ...metadata, options, category_group },
    ],
  );
}

const presentations = new Map<string, TariffPresentation>([
  ...family({
    family_id: "hk_retail",
    name_en: "Retail, HK–Virke",
    name_nb: "Butikk, HK–Virke",
    kind: "agreement",
    search_terms: ["butikk", "retail", "HK", "Virke", "Landsoverenskomsten"],
    variants: [{ id: "hk_retail" }],
  }),
  ...family({
    family_id: "handel_nho",
    name_en: "Retail, NHO Handelsoverenskomsten",
    name_nb: "Handel, NHO Handelsoverenskomsten",
    kind: "agreement",
    search_terms: ["butikk", "retail", "HK", "NHO", "Handelsoverenskomsten"],
    variants: [{ id: "handel_nho" }],
  }),
  ...family({
    family_id: "butikk_nho",
    name_en: "Retail, NHO Butikkoverenskomsten",
    name_nb: "Butikk, NHO Butikkoverenskomsten",
    kind: "agreement",
    search_terms: ["butikk", "retail", "HK", "NHO", "Butikkoverenskomsten"],
    variants: [{ id: "butikk_nho" }],
  }),
  ...family({
    family_id: "riksavtalen",
    name_en: "Hotel and restaurant, Riksavtalen",
    name_nb: "Hotell og restaurant, Riksavtalen",
    kind: "agreement",
    search_terms: [
      "hotell",
      "hotel",
      "restaurant",
      "servering",
      "hospitality",
      "Riksavtalen",
      "Fellesforbundet",
      "NHO Reiseliv",
    ],
    variants: [
      { id: "riksavtalen_hotel", options: [week("37.5"), nightRole("other")] },
      {
        id: "riksavtalen_guard_375",
        options: [week("37.5"), nightRole("guard")],
      },
      {
        id: "riksavtalen_manual_375",
        options: [week("37.5"), nightRole("manual")],
      },
      {
        id: "riksavtalen_other_355",
        options: [week("35.5"), nightRole("other")],
      },
      {
        id: "riksavtalen_guard_355",
        options: [week("35.5"), nightRole("guard")],
      },
      {
        id: "riksavtalen_manual_355",
        options: [week("35.5"), nightRole("manual")],
      },
    ],
  }),
  ...family({
    family_id: "security",
    name_en: "Security, Vekteroverenskomsten",
    name_nb: "Vekteroverenskomsten",
    kind: "agreement",
    search_terms: [
      "vekter",
      "security",
      "vakt",
      "NHO",
      "Norsk Arbeidsmandsforbund",
    ],
    variants: [
      {
        id: "vekteroverenskomst",
        options: [employment("employee"), week("37.5")],
      },
      { id: "vekter_355", options: [employment("employee"), week("35.5")] },
      { id: "vekter_336", options: [employment("employee"), week("33.6")] },
      {
        id: "vekter_apprentice_375",
        category_group: "security_apprentice",
        options: [employment("apprentice"), week("37.5")],
      },
    ],
  }),
  ...family({
    family_id: "cleaning_nho",
    name_en: "Cleaning, NHO",
    name_nb: "Renhold, NHO",
    kind: "agreement",
    search_terms: [
      "renhold",
      "cleaning",
      "NHO",
      "Renholdsoverenskomsten",
      "Norsk Arbeidsmandsforbund",
    ],
    variants: [
      {
        id: "cleaning_nho_375",
        options: [employment("employee"), week("37.5")],
      },
      {
        id: "cleaning_nho_355",
        options: [employment("employee"), week("35.5")],
      },
      {
        id: "cleaning_nho_336",
        options: [employment("employee"), week("33.6")],
      },
      {
        id: "cleaning_nho_apprentice",
        category_group: "cleaning_nho_apprentice",
        options: [employment("apprentice"), week("37.5")],
      },
    ],
  }),
  ...family({
    family_id: "cleaning_virke",
    name_en: "Cleaning, Virke",
    name_nb: "Renhold, Virke",
    kind: "agreement",
    search_terms: [
      "renhold",
      "cleaning",
      "Virke",
      "Renholdsoverenskomsten",
      "Norsk Arbeidsmandsforbund",
    ],
    variants: [
      {
        id: "cleaning_virke_375",
        options: [employment("employee"), week("37.5")],
      },
      {
        id: "cleaning_virke_355",
        options: [employment("employee"), week("35.5")],
      },
      {
        id: "cleaning_virke_336",
        options: [employment("employee"), week("33.6")],
      },
      {
        id: "cleaning_virke_apprentice",
        category_group: "cleaning_virke_apprentice",
        options: [employment("apprentice"), week("37.5")],
      },
    ],
  }),
  ...family({
    family_id: "energy_hk_virke",
    name_en: "Energy stations, HK–Virke",
    name_nb: "Energistasjon, HK–Virke",
    kind: "agreement",
    search_terms: [
      "energistasjon",
      "bensinstasjon",
      "petrol",
      "energy",
      "HK",
      "Virke",
    ],
    variants: [
      { id: "energy_hk_virke", options: [week("37.5")] },
      { id: "energy_hk_virke_355", options: [week("35.5")] },
    ],
  }),
  ...family({
    family_id: "grossist_virke",
    name_en: "Warehouse, Virke",
    name_nb: "Lager, Virke",
    kind: "agreement",
    search_terms: [
      "lager",
      "grossist",
      "warehouse",
      "Virke",
      "Fellesforbundet",
      "Grossistoverenskomsten",
    ],
    variants: [
      { id: "grossist_virke_1", options: [day] },
      { id: "grossist_virke_2", options: [twoShift] },
      { id: "grossist_virke_3", options: [threeShift] },
    ],
  }),
  ...family({
    family_id: "ks_ch4",
    name_en: "Municipal KS, chapter 4",
    name_nb: "Kommune KS, kapittel 4",
    kind: "agreement",
    search_terms: ["kommune", "municipal", "KS", "kapittel 4", "chapter 4"],
    variants: [
      { id: "ks_ch4_375", options: [week("37.5")] },
      { id: "ks_ch4_355", options: [week("35.5")] },
      { id: "ks_ch4_336", options: [week("33.6")] },
    ],
  }),
  ...family({
    family_id: "pbl",
    name_en: "Private preschool, PBL",
    name_nb: "Privat barnehage, PBL",
    kind: "agreement",
    search_terms: [
      "barnehage",
      "preschool",
      "kindergarten",
      "PBL",
      "private barnehagers landsforbund",
    ],
    variants: [
      { id: "pbl_day", options: [day] },
      { id: "pbl_rota", options: [rota] },
    ],
  }),
  ...family({
    family_id: "bygg_allmenngjort",
    name_en: "Construction, statutory minimum",
    name_nb: "Bygg, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: ["bygg", "construction", "minstelønn", "minimum"],
    variants: [{ id: "bygg_allmenngjort" }],
  }),
  ...family({
    family_id: "renhold_allmenngjort",
    name_en: "Cleaning, statutory minimum",
    name_nb: "Renhold, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: ["renhold", "cleaning", "minstelønn", "minimum"],
    variants: [{ id: "renhold_allmenngjort" }],
  }),
  ...family({
    family_id: "hospitality_allmenngjort",
    name_en: "Hospitality, statutory minimum",
    name_nb: "Hotell og servering, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: [
      "hotell",
      "hotel",
      "restaurant",
      "servering",
      "hospitality",
      "minstelønn",
      "minimum",
    ],
    variants: [{ id: "hospitality_allmenngjort" }],
  }),
  ...family({
    family_id: "automotive_allmenngjort",
    name_en: "Automotive, statutory minimum",
    name_nb: "Bilbransjen, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: [
      "bil",
      "verksted",
      "automotive",
      "mechanic",
      "minstelønn",
      "minimum",
    ],
    variants: [{ id: "automotive_allmenngjort" }],
  }),
  ...family({
    family_id: "freight_allmenngjort",
    name_en: "Road freight, statutory minimum",
    name_nb: "Godstransport, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: [
      "gods",
      "transport",
      "lastebil",
      "freight",
      "truck",
      "minstelønn",
      "minimum",
    ],
    variants: [{ id: "freight_allmenngjort" }],
  }),
  ...family({
    family_id: "coach_allmenngjort",
    name_en: "Tour coaches, statutory minimum",
    name_nb: "Turbuss, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: ["turbuss", "buss", "coach", "bus", "minstelønn", "minimum"],
    variants: [{ id: "coach_allmenngjort" }],
  }),
  ...family({
    family_id: "agriculture_allmenngjort",
    name_en: "Agriculture, statutory minimum",
    name_nb: "Jordbruk, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: [
      "jordbruk",
      "landbruk",
      "sesong",
      "røkter",
      "avløser",
      "agriculture",
      "farm",
      "seasonal",
      "animal care",
      "relief",
      "minstelønn",
      "minimum",
    ],
    variants: [
      {
        id: "agriculture_seasonal_allmenngjort",
        category_group: "agriculture_seasonal",
        options: [
          workRelationship({
            value: "seasonal",
            en: "Seasonal help",
            nb: "Ferie- og innhøstingshjelp",
          }),
        ],
      },
      {
        id: "agriculture_permanent_allmenngjort",
        category_group: "agriculture_permanent",
        options: [
          workRelationship({
            value: "permanent",
            en: "Permanent employee",
            nb: "Fast ansatt",
          }),
        ],
      },
      {
        id: "agriculture_relief_allmenngjort",
        category_group: "agriculture_permanent",
        options: [
          workRelationship({
            value: "animal_care_relief",
            en: "Animal-care relief in regular rota",
            nb: "Røkter og avløser i fast turnus",
          }),
        ],
      },
    ],
  }),
  ...family({
    family_id: "electrical_allmenngjort",
    name_en: "Electrical work, statutory minimum",
    name_nb: "Elektro, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: [
      "elektro",
      "elektriker",
      "electrical",
      "electrician",
      "minstelønn",
      "minimum",
    ],
    variants: [
      {
        id: "electrical_allmenngjort_375",
        options: [
          arrangement({
            value: "hours_375",
            en: "37.5-hour full-time week",
            nb: "37,5-timersuke i full stilling",
          }),
        ],
      },
      {
        id: "electrical_allmenngjort_365",
        options: [
          arrangement({
            value: "hours_365",
            en: "36.5-hour full-time week",
            nb: "36,5-timersuke i full stilling",
          }),
        ],
      },
      {
        id: "electrical_allmenngjort_355",
        options: [
          arrangement({
            value: "hours_355",
            en: "35.5-hour full-time week",
            nb: "35,5-timersuke i full stilling",
          }),
        ],
      },
      {
        id: "electrical_allmenngjort_336",
        options: [
          arrangement({
            value: "hours_336",
            en: "33.6-hour full-time week",
            nb: "33,6-timersuke i full stilling",
          }),
        ],
      },
    ],
  }),
  ...family({
    family_id: "fish_processing_allmenngjort",
    name_en: "Fish processing, statutory minimum",
    name_nb: "Fiskeindustri, allmenngjort minstelønn",
    kind: "statutory",
    search_terms: [
      "fisk",
      "fiskeindustri",
      "fish",
      "processing",
      "minstelønn",
      "minimum",
    ],
    variants: [
      { id: "fish_processing_allmenngjort_1", options: [day] },
      { id: "fish_processing_allmenngjort_2", options: [twoShift] },
      { id: "fish_processing_allmenngjort_3", options: [threeShift] },
    ],
  }),
  ...family({
    family_id: "shipyard_allmenngjort",
    name_en: "Shipyards, ordinary day work minimum",
    name_nb: "Skips- og verftsindustri, allmenngjort minstelønn for dagarbeid",
    kind: "statutory",
    search_terms: [
      "skip",
      "verft",
      "ship",
      "shipyard",
      "minstelønn",
      "minimum",
    ],
    variants: [{ id: "shipyard_allmenngjort" }],
  }),
]);

export function withPresentation(entry: CatalogueEntry): CatalogueEntry {
  const presentation = presentations.get(entry.type.id);
  if (!presentation)
    throw new Error(`Missing tariff presentation ${entry.type.id}`);
  return { ...entry, type: { ...entry.type, presentation } };
}

export function validatePresentations(entries: CatalogueEntry[]): void {
  const families = new Map<string, string>();
  const dimensions = new Map<string, string>();
  const values = new Map<string, string>();
  const categories = new Map<string, string>();
  const tuples = new Set<string>();
  const nonempty = (value: string) => value.trim().length > 0;
  for (const { type, version } of entries) {
    const presentation = type.presentation;
    if (!presentation)
      throw new Error(`Missing tariff presentation ${type.id}`);
    if (
      ![
        presentation.family_id,
        presentation.name_en,
        presentation.name_nb,
        presentation.category_group,
      ].every(nonempty) ||
      !["agreement", "statutory"].includes(presentation.kind) ||
      !presentation.search_terms.length ||
      !presentation.search_terms.every(nonempty)
    )
      throw new Error(`Invalid tariff presentation ${type.id}`);

    const familyKey = presentation.family_id;
    const familyMetadata = JSON.stringify({
      name_en: presentation.name_en,
      name_nb: presentation.name_nb,
      kind: presentation.kind,
      search_terms: presentation.search_terms,
      dimensions: presentation.options.map((option) => option.dimension_id),
    });
    const previousFamily = families.get(familyKey);
    if (previousFamily !== undefined && previousFamily !== familyMetadata)
      throw new Error(`Inconsistent tariff family ${familyKey}`);
    families.set(familyKey, familyMetadata);

    const seenDimensions = new Set<string>();
    for (const option of presentation.options) {
      if (
        seenDimensions.has(option.dimension_id) ||
        ![
          option.dimension_id,
          option.label_en,
          option.label_nb,
          option.value,
          option.value_en,
          option.value_nb,
        ].every(nonempty) ||
        (option.help_en !== undefined && !nonempty(option.help_en)) ||
        (option.help_nb !== undefined && !nonempty(option.help_nb)) ||
        (option.help_en === undefined) !== (option.help_nb === undefined)
      )
        throw new Error(`Invalid tariff option ${type.id}`);
      seenDimensions.add(option.dimension_id);
      const dimensionKey = JSON.stringify([familyKey, option.dimension_id]);
      const dimensionMetadata = JSON.stringify([
        option.label_en,
        option.label_nb,
        option.help_en,
        option.help_nb,
      ]);
      const previousDimension = dimensions.get(dimensionKey);
      if (
        previousDimension !== undefined &&
        previousDimension !== dimensionMetadata
      )
        throw new Error(
          `Inconsistent tariff dimension ${type.id}:${option.dimension_id}`,
        );
      dimensions.set(dimensionKey, dimensionMetadata);
      const valueKey = JSON.stringify([
        familyKey,
        option.dimension_id,
        option.value,
      ]);
      const valueMetadata = JSON.stringify([option.value_en, option.value_nb]);
      const previousValue = values.get(valueKey);
      if (previousValue !== undefined && previousValue !== valueMetadata)
        throw new Error(
          `Inconsistent tariff value ${type.id}:${option.dimension_id}`,
        );
      values.set(valueKey, valueMetadata);
    }
    const tuple = JSON.stringify([
      familyKey,
      presentation.options.map((option) => [option.dimension_id, option.value]),
    ]);
    if (tuples.has(tuple))
      throw new Error(`Ambiguous tariff selection ${type.id}`);
    tuples.add(tuple);
    for (const category of version.categories) {
      const key = JSON.stringify([presentation.category_group, category.level]);
      const meaning = JSON.stringify([category.label_en, category.label_nb]);
      const previous = categories.get(key);
      if (previous !== undefined && previous !== meaning)
        throw new Error(
          `Inconsistent tariff category group ${type.id}:${category.level}`,
        );
      categories.set(key, meaning);
    }
  }
}
