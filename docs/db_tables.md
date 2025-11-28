# Database Tables (public schema)

Lookup file. Keep updated when new columns are added.

---

## profiles

- **id** → `uuid` (PK, FK → auth.users)
- **before_paywall** → `boolean` (default: false)
- **wagey_invocations** → `jsonb` (default: `{"count": 0, "month": null}`)
- **created_at** → `timestamp with time zone`
- **updated_at** → `timestamp with time zone`

---

## subscriptions

- **id** → `uuid` (PK)
- **user_id** → `uuid` (FK → auth.users, unique)
- **stripe_customer_id** → `text` (not null, unique, format: `cus_*`)
- **stripe_subscription_id** → `text`
- **status** → `text` (default: 'incomplete')
- **price_id** → `text`
- **current_period_end** → `timestamp with time zone`
- **cancel_at** → `timestamp with time zone`
- **cancel_at_period_end** → `boolean` (default: false)
- **canceled_at** → `timestamp with time zone`
- **cancellation_reason** → `text`
- **cancellation_feedback** → `text`
- **cancellation_comment** → `text`
- **created_at** → `timestamp with time zone`
- **updated_at** → `timestamp with time zone`

---

## user_settings

- **user_id** → `uuid` (PK, FK → auth.users)
- **monthly_goal** → `integer` (default: 20000)
- **payroll_day** → `integer` (default: 15, range: 1-31)
- **default_shifts_view** → `varchar` (default: 'calendar', values: 'list' | 'calendar')
- **profile_picture_url** → `text`
- **tax_deduction_enabled** → `boolean` (default: false)
- **tax_percentage** → `numeric` (default: 0.0, range: 0-100)
- **half_tax_month** → `integer` (values: 11, 12, or null)
- **pause_deduction_enabled** → `boolean` (default: true)
- **pause_deduction_method** → `text` (default: 'proportional', values: 'proportional' | 'base_only' | 'end_of_shift' | 'none')
- **pause_threshold_hours** → `numeric` (default: 5.5)
- **pause_deduction_minutes** → `integer` (default: 30)
- **theme** → `text` (default: 'dark', values: 'light' | 'dark' | 'system')
- **currency** → `text` (default: 'kr')
- **last_active** → `timestamp with time zone`
- **created_at** → `timestamp with time zone`
- **updated_at** → `timestamp with time zone`

---

## user_shifts

- **id** → `uuid` (PK)
- **user_id** → `uuid` (FK → auth.users)
- **shift_date** → `date` (not null)
- **start_time** → `text` (not null)
- **end_time** → `text` (not null)
- **custom_supplements** → `jsonb` (shift-specific supplement overrides, structure: `{ mode: "replace" | "merge", rules: SupplementRule[] }`)
- **created_at** → `timestamp with time zone`

---

## recurring_shifts

- **id** → `uuid` (PK)
- **user_id** → `uuid` (FK → auth.users, default: auth.uid())
- **start_time** → `time with time zone` (not null)
- **end_time** → `time with time zone` (not null)
- **repeat_interval_weeks** → `smallint` (not null)
- **selected_days** → `jsonb` (not null)
- **end_condition** → `jsonb`
- **exclusions** → `jsonb`
- **date_specific_supplements** → `jsonb` (date-specific supplement overrides, structure: `{ [isoDate]: { mode: "replace" | "merge", rules: SupplementRule[] } }`)

---

## wage_snapshots

- **id** → `uuid` (PK)
- **user_id** → `uuid` (FK → auth.users)
- **from_date** → `date` (not null, unique per user)
- **hourly_wage** → `numeric(10,2)` (not null)
- **wage_level** → `integer` (null = custom wage, 1-9 = tariff level)
- **supplements** → `jsonb` (default: `[]`)
- **created_at** → `timestamp with time zone`

---

## stripe_events

- **id** → `text` (PK)
- **type** → `text` (not null)
- **received_at** → `timestamp with time zone` (default: now())
- **processed_at** → `timestamp with time zone`
- **attempts** → `integer` (default: 0)
- **last_error** → `text`
