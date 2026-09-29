# Database Schema

Reference documentation for Tidex database tables and relationships.

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              auth.users                                      │
│                          (Central Entity)                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
   ONE-TO-ONE (1:1)           ONE-TO-MANY (1:N)           MANY-TO-MANY
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐           ┌───────────────┐           ┌───────────────┐
│   profiles    │           │     jobs      │           │ shift_shares  │
│user_settings  │           │  user_shifts  │           │(owner↔viewer) │
│ subscriptions │           │recurring_shifts│           └───────────────┘
│notification_  │           │ wage_snapshots │
│  preferences  │           │ push_devices  │
│app_account_   │           │   feedback    │
│    tokens     │           │               │
│               │           │               │
└───────────────┘           └───────────────┘
                                    │
                             jobs owns 1:N
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
             ┌──────────────┐             ┌─────────────────┐
             │ user_shifts  │             │  wage_snapshots  │
             │ recurring_   │             │                 │
             │   shifts     │             └─────────────────┘
             └──────────────┘

                    ┌───────────────┐
                    │ tariff_types  │
                    └───────┬───────┘
                            │ 1:N
                            ▼
                    ┌───────────────┐
                    │tariff_versions│
                    └───────────────┘
```

---

## Relationship Types

### One-to-One (1:1)

Each user has exactly one of these records.

| Parent | Child | Enforcement |
|--------|-------|-------------|
| `auth.users` | `profiles` | PK = FK (id references auth.users.id) |
| `auth.users` | `user_settings` | user_id is PK |
| `auth.users` | `subscriptions` | UNIQUE constraint on user_id |
| `auth.users` | `notification_preferences` | user_id is PK |
| `auth.users` | `app_account_tokens` | user_id is PK |

### One-to-Many (1:N)

Each user can have many of these records.

| One (Parent) | Many (Child) | Description |
|--------------|--------------|-------------|
| `auth.users` | `jobs` | One user → many jobs/employers |
| `auth.users` | `user_shifts` | One user → many individual shifts |
| `auth.users` | `recurring_shifts` | One user → many recurring shift patterns |
| `auth.users` | `wage_snapshots` | One user → many wage history records |
| `auth.users` | `push_devices` | One user → many registered devices |
| `auth.users` | `feedback` | One user → many feedback submissions |
| `jobs` | `user_shifts` | One job → many shifts belonging to that job |
| `jobs` | `recurring_shifts` | One job → many recurring patterns belonging to that job |
| `jobs` | `wage_snapshots` | One job → many wage history records for that job |
| `tariff_types` | `tariff_versions` | One tariff agreement → many versions over time |
| `impersonation_sessions` | `impersonation_audit_log` | One session → many audit entries |

### Many-to-Many (M:N)

| Entity A | Entity B | Junction Table | Description |
|----------|----------|----------------|-------------|
| `auth.users` | `auth.users` | `shift_shares` | Self-referencing: users share shifts with other users via owner_id ↔ viewer_id |

---

## Tables (public schema)

### jobs

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK, default: `gen_random_uuid()` |
| user_id | `uuid` | FK → auth.users (ON DELETE CASCADE), NOT NULL |
| name | `text` | NOT NULL, 1-100 chars |
| color | `text` | nullable, format: `#RRGGBB` |
| is_default | `boolean` | NOT NULL, default: false |
| sort_order | `smallint` | NOT NULL, default: 0 |
| payroll_day | `integer` | range: 1-31, default: 15 |
| half_tax_month | `integer` | values: 11, 12, or null |
| monthly_goal | `integer` | default: 20000 |
| archived_at | `timestamptz` | nullable (archived = hidden from Add Shift pickers) |
| deleted_at | `timestamptz` | nullable (soft delete) |
| created_at | `timestamptz` | NOT NULL, default: `now()` |
| updated_at | `timestamptz` | NOT NULL, default: `now()` |
| revision | `bigint` | NOT NULL, default: 1 |

**Unique constraints:**
- `UNIQUE (user_id) WHERE is_default = true AND deleted_at IS NULL AND archived_at IS NULL`

**Notes:**
- Every user gets a default job ("Jobb") on sign-up
- Payroll settings (`payroll_day`, `half_tax_month`, `monthly_goal`) have been moved here from `user_settings`; `user_settings` keeps mirrored copies for legacy client compatibility
- DB triggers keep `user_settings` and the default job in sync bidirectionally

---

### profiles

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK, FK → auth.users |
| before_paywall | `boolean` | default: false |
| created_at | `timestamptz` | |
| updated_at | `timestamptz` | |

---

### subscriptions

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK |
| user_id | `uuid` | FK → auth.users, UNIQUE, NOT NULL |
| stripe_customer_id | `text` | UNIQUE, format: `cus_*` |
| stripe_subscription_id | `text` | |
| status | `text` | default: 'incomplete' |
| provider | `text` | default: 'stripe', values: stripe, apple, admin_trial |
| provider_subscription_id | `text` | |
| product_id | `text` | |
| price_id | `text` | |
| price_display | `text` | Localized price from App Store |
| current_period_start | `timestamptz` | |
| current_period_end | `timestamptz` | |
| cancel_at | `timestamptz` | |
| cancel_at_period_end | `boolean` | default: false |
| canceled_at | `timestamptz` | |
| cancellation_reason | `text` | |
| cancellation_feedback | `text` | |
| cancellation_comment | `text` | |
| apple_original_transaction_id | `text` | |
| apple_last_transaction_id | `text` | |
| apple_environment | `text` | values: Production, Sandbox |
| app_account_token | `uuid` | |
| raw_provider_payload | `jsonb` | |
| created_at | `timestamptz` | |
| updated_at | `timestamptz` | |

---

### user_settings

| Column | Type | Constraints |
|--------|------|-------------|
| **user_id** | `uuid` | PK, FK → auth.users |
| monthly_goal | `integer` | default: 20000 |
| payroll_day | `integer` | default: 15, range: 1-31 |
| default_shifts_view | `varchar` | default: 'calendar', values: list, calendar |
| profile_picture_url | `text` | |
| theme | `text` | default: 'dark', values: light, dark, system |
| currency | `text` | default: 'kr' |
| half_tax_month | `integer` | values: 11, 12, or null |
| calendar_animation_style | `text` | default: 'horizontal', values: horizontal, vertical |
| revision | `bigint` | default: 1 |
| last_active | `timestamptz` | |
| created_at | `timestamptz` | |
| updated_at | `timestamptz` | |

---

### user_shifts

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK |
| user_id | `uuid` | FK → auth.users, NOT NULL |
| job_id | `uuid` | FK → jobs, NOT NULL (assigned by trigger when omitted by legacy clients) |
| shift_date | `date` | NOT NULL |
| start_time | `text` | NOT NULL |
| end_time | `text` | NOT NULL |
| custom_pause_windows | `jsonb` | structure: `{ windows: [{ start: "HH:mm", end: "HH:mm" }] }`; normalized to `NULL` when empty/invalid |
| custom_supplements | `jsonb` | structure: `{ mode: "replace" | "merge", rules: SupplementRule[] }` |
| deleted_at | `timestamptz` | soft delete |
| revision | `bigint` | default: 1 |
| created_at | `timestamptz` | |
| updated_at | `timestamptz` | |

---

### recurring_shifts

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK |
| user_id | `uuid` | FK → auth.users, default: auth.uid() |
| job_id | `uuid` | FK → jobs, NOT NULL (all generated virtual shifts inherit this job) |
| start_time | `timetz` | NOT NULL |
| end_time | `timetz` | NOT NULL |
| repeat_interval_weeks | `smallint` | NOT NULL |
| selected_days | `jsonb` | NOT NULL |
| end_condition | `jsonb` | |
| exclusions | `jsonb` | |
| date_specific_pause_windows | `jsonb` | structure: `{ [isoDate]: { windows: [{ start, end }] } }`; invalid/empty entries normalize away |
| date_specific_supplements | `jsonb` | structure: `{ [isoDate]: { mode, rules } }` |
| deleted_at | `timestamptz` | soft delete |
| revision | `bigint` | default: 1 |
| created_at | `timestamptz` | |
| updated_at | `timestamptz` | |

---

### wage_snapshots

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK |
| user_id | `uuid` | FK → auth.users |
| job_id | `uuid` | FK → jobs, NOT NULL (controls which job's wage history applies) |
| from_date | `date` | unique per (user, job); NULL = baseline snapshot for this job |
| hourly_wage | `numeric` | NOT NULL |
| wage_level | `integer` | null = custom, 1-9 = tariff level |
| tariff_type_id | `text` | FK → internal.tariff_types |
| supplements | `jsonb` | default: `[]` |
| tax_enabled | `boolean` | default: false |
| tax_percentage | `numeric` | default: 0, range: 0-100 |
| break_enabled | `boolean` | default: true |
| break_method | `text` | default: 'proportional' |
| break_threshold_hours | `numeric` | default: 5.5 |
| break_deduction_minutes | `integer` | default: 30 |
| deleted_at | `timestamptz` | soft delete |
| revision | `bigint` | default: 1 |
| created_at | `timestamptz` | |
| updated_at | `timestamptz` | |

**Unique constraints (updated for multi-job):**
- `UNIQUE (user_id, job_id) WHERE from_date IS NULL AND deleted_at IS NULL`
- `UNIQUE (user_id, job_id, from_date) WHERE from_date IS NOT NULL AND deleted_at IS NULL`

---

### shift_shares

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK |
| owner_id | `uuid` | FK → auth.users |
| viewer_id | `uuid` | FK → auth.users |
| show_earnings | `boolean` | default: true |
| blocked | `boolean` | default: false |
| muted | `boolean` | default: false |
| created_at | `timestamptz` | |

---

### notification_preferences

| Column | Type | Constraints |
|--------|------|-------------|
| **user_id** | `uuid` | PK, FK → auth.users |
| shared_shifts_enabled | `boolean` | default: true |
| shift_reminders_enabled | `boolean` | default: true |
| shift_reminder_minutes_array | `integer[]` | default: `{300}`, max 4 items |
| updated_at | `timestamptz` | |

---

### feedback

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK |
| user_id | `uuid` | FK → auth.users |
| message | `text` | 1-2000 chars |
| user_email | `text` | |
| response | `text` | admin response |
| responded_at | `timestamptz` | |
| responded_by | `uuid` | FK → auth.users |
| created_at | `timestamptz` | |

---

## Tables (internal schema)

### tariff_types

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `text` | PK, slug: hk_retail, fellesforbundet, etc. |
| display_name | `text` | |
| description | `text` | |
| country | `text` | default: 'NO' |
| is_default | `boolean` | default: false |
| created_at | `timestamptz` | |

---

### tariff_versions

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK |
| tariff_type_id | `text` | FK → tariff_types |
| effective_date | `date` | |
| name | `text` | |
| rates | `jsonb` | `{ "-1": 129.91, "1": 184.54, ... }` |
| supplements | `jsonb` | `{ rules: [...] }` |
| created_at | `timestamptz` | |

---

### push_devices

| Column | Type | Constraints |
|--------|------|-------------|
| **id** | `uuid` | PK |
| user_id | `uuid` | FK → auth.users |
| fcm_token | `text` | UNIQUE |
| apns_token | `text` | |
| platform | `text` | values: ios, android, web |
| device_id | `text` | stable identifier |
| device_model | `text` | |
| app_version | `text` | |
| last_seen_at | `timestamptz` | |
| created_at | `timestamptz` | |
| updated_at | `timestamptz` | |

---

### app_account_tokens

| Column | Type | Constraints |
|--------|------|-------------|
| **user_id** | `uuid` | PK, FK → auth.users |
| token | `uuid` | UNIQUE, default: gen_random_uuid() |
| created_at | `timestamptz` | |
| updated_at | `timestamptz` | |

---

*Last updated: 2026-02-26*
