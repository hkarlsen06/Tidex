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
- **pause_deduction** → `boolean` (deprecated, use `break_enabled`)
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
- **break_enabled** → `boolean` - Master switch for automatic break deductions
- **break_method** → `text` - How to apply deduction: 'proportional', 'base_only', 'end_of_shift', 'none'
- **break_threshold_hours** → `numeric` - Minimum shift duration to trigger break (e.g., 5.5)
- **break_deduction_minutes** → `integer` - Amount to deduct (e.g., 30)
- **audit_break_calculations** → `boolean`
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
