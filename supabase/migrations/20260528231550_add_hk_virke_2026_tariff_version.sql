INSERT INTO internal.tariff_versions (
  tariff_type_id,
  effective_date,
  name,
  rates,
  supplements
)
SELECT
  'hk_retail',
  DATE '2026-06-01',
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
WHERE NOT EXISTS (
  SELECT 1
  FROM internal.tariff_versions
  WHERE tariff_type_id = 'hk_retail'
    AND effective_date = DATE '2026-06-01'
);
