# Settings Reference

## Menu → DB Map

```json
{
  "account": {
    "user_settings": ["profile_picture_url"],

    "user_shifts": ["delete_all_rows_for_user (clearAllShifts)"],

    "supabase_auth.users": ["user_metadata.first_name"]
  },

  "wage": {
    "user_settings": [
      "use_preset",

      "wage_level (legacy column if present)",

      "current_wage_level",

      "custom_wage",

      "custom_bonuses",

      "monthly_goal",

      "payroll_day"
    ]
  },

  "wage-advanced": {
    "user_settings": [
      "pause_deduction_enabled",

      "pause_deduction_method",

      "pause_threshold_hours",

      "pause_deduction_minutes",

      "tax_deduction_enabled",

      "tax_percentage",

      "break_policy"
    ]
  },

  "interface": {
    "user_settings": [
      "theme",

      "default_shifts_view",

      "show_employee_tab",

      "direct_time_input",

      "full_minute_range",

      "currency_format"
    ]
  },

  "data": {
    "user_shifts": ["insert_imported_rows"],

    "user_settings": [
      "use_preset",

      "custom_wage",

      "current_wage_level",

      "custom_bonuses",

      "pause_deduction",

      "full_minute_range",

      "direct_time_input",

      "monthly_goal",

      "currency_format"
    ]
  }
}
```

## Details

### Account

-`user_settings.profile_picture_url` updated when avatars are saved (`app/src/js/appLogic.js:8201`).

- Clearing all shifts wipes `user_shifts` rows for the signed-in user (`app/src/js/appLogic.js:10407`).
- Profile name edits push to Supabase auth metadata (`app/src/js/appLogic.js:7930`).
- UI lives under `/settings/account` (`app/src/pages/settings.js:107`).

### Wage

- Preset/custom wage values persist via `saveSettingsToSupabase` (`app/src/js/appLogic.js:2795`).
- Page wiring is defined at `/settings/wage` (`app/src/pages/settings.js:143`).

### Wage Advanced

- Break deduction toggles map to pause-related columns (`app/src/js/appLogic.js:9045`).
- Tax toggles write `tax_deduction_*` fields (`app/src/js/appLogic.js:3136`).
- Enterprise break policy select saves `break_policy` (`app/src/js/appLogic.js:549`).
- UI layout for `/settings/wage-advanced` (`app/src/pages/settings.js:368`).

### Interface

- Theme choice persisted via `themeManager.saveThemeToDatabase` (`app/src/js/themeManager.js:103`).
- Shift view, employee tab, and time entry toggles handled in `setupNewSettingsListeners` (`app/src/js/appLogic.js:11904`).
- Page markup lives at `/settings/interface` (`app/src/pages/settings.js:600`).

### Data

- Imports insert `user_shifts` rows (`app/src/js/appLogic.js:11763`).
- Optional settings import calls `saveSettingsToSupabase` with mapped fields (`app/src/js/appLogic.js:11806`).
- UI for `/settings/data` (`app/src/pages/settings.js:784`).
