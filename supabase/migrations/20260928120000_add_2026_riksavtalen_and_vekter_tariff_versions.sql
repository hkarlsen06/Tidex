-- 2026 settlements for Riksavtalen and Vekteroverenskomsten.
-- Overtime rules did not change, so each new version copies overtime from
-- the version it replaces.

-- Riksavtalen (Fellesforbundet / NHO Reiseliv), effective 2026-06-01.
-- Source: https://www.fellesforbundet.no/globalassets/blokker/t26/riksavtalen/stemmemateriell-riksavtalen---2026.pdf
-- Every minimum rate rose 10.50 kr/h. Skilled levels 4-6 rose 15.50 kr/h.
-- Levels 1-3 are øvrige u/fagbrev (begynner, 4 års, 10 års praksis),
-- levels 4-6 are the same steps with fagbrev, -1 is 17 år and -2 is 18 år.
-- Night uses the "nattvakter, manuelt arbeid" rate, as in 2025.
INSERT INTO internal.tariff_versions (
  tariff_type_id,
  effective_date,
  name,
  rates,
  supplements,
  overtime
)
SELECT
  'riksavtalen_hotel',
  DATE '2026-06-01',
  'Riksavtalen satser 2026 (Juni)',
  '{
    "-2": 176.84,
    "-1": 162.58,
    "1": 215.29,
    "2": 232.51,
    "3": 241.61,
    "4": 230.29,
    "5": 247.51,
    "6": 256.61
  }'::jsonb,
  '{
    "meta": { "note": "Riksavtalen kan ha ulike nattillegg (aktivt nattarbeid vs nattportier). Her modelleres aktivt nattarbeid som flat sats." },
    "rules": [
      { "days": [1, 2, 3, 4, 5], "from": "17:00", "to": "21:00", "rate": 16.59 },
      { "days": [1, 2, 3, 4, 5], "from": "21:00", "to": "06:00", "rate": 24.84 },
      { "days": [6, 7], "from": "00:00", "to": "24:00", "rate": 31.52 }
    ]
  }'::jsonb,
  previous.overtime
FROM internal.tariff_versions AS previous
WHERE previous.tariff_type_id = 'riksavtalen_hotel'
  AND previous.effective_date = DATE '2025-04-01'
  AND NOT EXISTS (
    SELECT 1
    FROM internal.tariff_versions
    WHERE tariff_type_id = 'riksavtalen_hotel'
      AND effective_date = DATE '2026-06-01'
  );

-- Vekteroverenskomsten (Arbeidsmandsforbundet / NHO Service og Handel),
-- effective 2026-04-01. Source:
-- https://www.nhosh.no/contentassets/385855c87911442eaf6c8fccaf866049/tariffbrev-2026-vekter.pdf
-- Every level rose 10.50 kr/h and the fagbrev supplement rose from 9.50 to
-- 14.50 kr/h. Night and weekend supplements did not change.
INSERT INTO internal.tariff_versions (
  tariff_type_id,
  effective_date,
  name,
  rates,
  supplements,
  overtime
)
SELECT
  'vekteroverenskomst',
  DATE '2026-04-01',
  'Vekter satser 2026 (April)',
  '{
    "1": 246.22,
    "2": 248.72,
    "3": 250.92,
    "4": 251.92,
    "5": 253.72,
    "6": 255.72
  }'::jsonb,
  jsonb_set(previous.supplements, '{meta,fagbrev_tillegg_per_time}', '14.50'::jsonb),
  previous.overtime
FROM internal.tariff_versions AS previous
WHERE previous.tariff_type_id = 'vekteroverenskomst'
  AND previous.effective_date = DATE '2025-04-01'
  AND NOT EXISTS (
    SELECT 1
    FROM internal.tariff_versions
    WHERE tariff_type_id = 'vekteroverenskomst'
      AND effective_date = DATE '2026-04-01'
  );
