# Database Tables (public schema)

Lookup file. Keep updated when new columns are added.

---

## profiles

- **id** → `uuid`
- **before_paywall** → `boolean`
- **created_at** → `timestamp with time zone`
- **updated_at** → `timestamp with time zone`

---

## subscriptions

- **id** → `uuid`
- **user_id** → `uuid`
- **stripe_customer_id** → `text`
- **stripe_subscription_id** → `text`
- **status** → `text`
- **current_period_end** → `timestamp with time zone`
- **created_at** → `timestamp with time zone`
- **updated_at** → `timestamp with time zone`
- **price_id** → `text`

---

## user_settings

- **user_id** → `uuid`
- **use_preset** → `boolean`
- **custom_wage** → `numeric`
- **current_wage_level** → `integer`
- **custom_bonuses** → `jsonb`
- **pause_deduction** → `boolean`
- **created_at** → `timestamp with time zone`
- **updated_at** → `timestamp with time zone`
- **last_active** → `timestamp with time zone`
- **direct_time_input** → `boolean`
- **monthly_goal** → `integer`
- **default_shifts_view** → `character varying`
- **profile_picture_url** → `text`
- **tax_deduction_enabled** → `boolean`
- **tax_percentage** → `numeric`
- **payroll_day** → `integer`
- **pause_deduction_enabled** → `boolean`
- **pause_deduction_method** → `text`
- **pause_threshold_hours** → `numeric`
- **pause_deduction_minutes** → `integer`
- **audit_break_calculations** → `boolean`
- **break_policy** → `text`
- **theme** → `text`
- **show_employee_tab** → `boolean`

---

## user_shifts

- **id** → `uuid`
- **user_id** → `uuid`
- **shift_date** → `date`
- **start_time** → `text`
- **end_time** → `text`
- **shift_type** → `integer`
- **created_at** → `timestamp with time zone`
- **series_id** → `uuid`
- **pause_duration_hours** → `numeric`
