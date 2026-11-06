# Tariff selection design

The 48 calculation configurations must not appear as 48 agreements. Two independent design agents compared a searchable agreement sheet with inline setup choices against a staged wizard. Both chose the sheet and inline form. They also agreed on the night-guard question after checking the existing category and payroll models.

## Compared wireframes

The inline design keeps the setup and its resulting wage together.

```text
Agreement                         Choose >
  Searchable sheet, one row per agreement
Contractual full-time week         Choose >
Are you employed as a night guard? Choose >
Pay category                    Choose >
  Searchable sheet with categories and rates
  Selected category and hourly rate
About the agreement and sources          >
Continue
```

The alternative wizard separates those choices across screens.

```text
Choose agreement > Work arrangement > Category > Review pay
```

The wizard makes infrequent setup questions prominent but adds navigation to ordinary editing and duplicates onboarding's own steps. The inline design gives simple agreements one choice and exposes additional controls only where needed. A second design pass moved the 27 hotel and 35 KS category choices into a shared searchable sheet. Both agents agreed this keeps the arrangement, selected category and resulting pay together on the main screen. Native screenshots and real selection journeys check the resulting form.

## Shared behavior

- Choose each agreement once. Keep collective agreements and statutory minima distinct, including NHO and Virke agreements with similar rates.
- Search agreement names, parties and sectors. Group the search results into collective agreements and statutory minima.
- Ask for the contractual full-time week, including for part-time workers. Never derive it from their recorded hours.
- For Riksavtalen ask "Er du ansatt som nattevakt?" with "Nei", "Ja", and "Ja, med avtalt manuelt arbeid". Explain once that ordinary night premiums also apply with "Nei".
- Require explicit answers for new setups with several valid options. A single supported option is shown as a fixed value.
- Restore the exact saved configuration, category, rate, supplements and overtime. Opening or canceling a chooser does not refresh pay.
- Clear the category when changing agreement. Preserve it across variants only when explicit metadata guarantees equivalent category meaning and the category remains available.
- Show whether the applied setup estimates overtime from weekly hours or requires manual adjustments beside the pay result. In editing, use the saved or edited rules, not the latest catalogue rules. Keep source links, dates and detailed exclusions in the agreement-details disclosure. Keep choice-specific explanations beside the relevant control.
- Use the same selector in onboarding and wage editing. Resolve every complete selection back to its existing concrete tariff ID.

## Data contract

Each catalogue type has optional presentation metadata with a stable family ID, localized family name, agreement or statutory kind, search terms, category group and ordered option values. The UI derives valid combinations from those exact tuples. It never parses localized names or tariff IDs. Types without metadata remain singleton families. Unknown saved IDs remain visible and retain their saved pay.

Rates, category IDs and payroll rules do not change as part of this design.
