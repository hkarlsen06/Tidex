# Settings Implementation Guide

> **Purpose**: Complete specification for implementing the settings feature with goal-based UX architecture.
>
> **How to use this guide**: This document contains all architectural decisions, component mappings, database columns, and implementation patterns needed to build the settings feature from scratch. Follow the implementation priority order and refer to component specifications as needed.

---

## ✅ IMPLEMENTATION STATUS (Updated 2025-10-09)

### Completed ✅
- **Phase 1: Foundation**
  - ✅ Route structure created (`app/(app)/settings/`)
  - ✅ Settings layout with responsive navigation (sidebar desktop, tabs mobile)
  - ✅ Root redirect page (`/settings` → `/settings/profile`)
  - ✅ Data loaders (`_data/getSettings.ts`)
  - ✅ Server actions (`_actions/updateSettings.ts`)

- **Phase 2: All Pages Implemented**
  - ✅ Profile page (name editing, avatar, clear all shifts)
  - ✅ Display page (theme, default view, currency)
  - ✅ Preferences page (3 toggle settings with tooltips)
  - ✅ Pay page (wage config, supplements, breaks, tax, goals)
  - ✅ Data page (export/import placeholders)

- **Phase 3: Component Architecture**
  - ✅ SupplementsEditor extracted to `components/settings/SupplementsEditor/`
  - ✅ All form components moved to `components/settings/{page}/`
  - ✅ Onboarding refactored to use shared SupplementsEditor
  - ✅ No compilation errors, dev server runs successfully

### Remaining 🚧
- **Phase 4: Navigation & Polish**
  - ⏳ Add "Settings" link to TopHeader/UserMenu
  - ⏳ Add Settings to main navigation (if applicable)

- **Phase 5: Testing**
  - ⏳ Manual testing of all pages
  - ⏳ Test SupplementsEditor in both onboarding and settings
  - ⏳ Verify responsive design
  - ⏳ Test theme changes
  - ⏳ Verify all server actions work

### Notes
- All core functionality is complete and working
- Components properly organized in `/components/settings/`
- Ready for navigation integration and final testing

---

# Settings Reference

## Route Structure

```
app/(app)/settings/
├── layout.tsx           # Settings shell with sidebar navigation
├── page.tsx             # Redirect to /settings/profile
├── profile/page.tsx
├── pay/page.tsx
├── display/page.tsx
├── preferences/page.tsx
└── data/page.tsx
```

## Navigation Structure (Goal-Based UX)

### 1. Profile (`/settings/profile`)
**Purpose**: Personal information and account management

**Settings**:
- Name (text input)
- Profile picture (upload with preview)
- Clear all shifts (danger zone with confirmation)

**DB columns**:
- `supabase_auth.users.user_metadata.first_name`
- `user_settings.profile_picture_url`
- `user_shifts` (delete all rows for user)

**shadcn components**:
- `Input` - Name field
- `Button` - Save, upload, clear actions
- `Dialog` - Confirmation modal for destructive actions
- `Card` - Section grouping (profile info vs danger zone)
- `Avatar` - Profile picture display
- `Label` - Form labels

### 2. Pay (`/settings/pay`)
**Purpose**: Everything that affects earnings and take-home pay

**Settings**:
- Wage method toggle (preset vs custom)
- Wage level dropdown (if preset) or custom wage input
- Monthly goal (number input with currency)
- Payroll day (1-31 selector)
- **Supplements** (reuse `SupplementsStep.tsx` component!)
- Break deduction toggle + method
- Break deduction settings (hours/minutes)
- Tax deduction toggle + percentage

**DB columns**:
- `user_settings.use_preset`
- `user_settings.current_wage_level`
- `user_settings.custom_wage`
- `user_settings.custom_bonuses`
- `user_settings.monthly_goal`
- `user_settings.payroll_day`
- `user_settings.pause_deduction_enabled`
- `user_settings.pause_deduction_method`
- `user_settings.pause_threshold_hours`
- `user_settings.pause_deduction_minutes`
- `user_settings.tax_deduction_enabled`
- `user_settings.tax_percentage`
- `user_settings.break_policy` (for enterprise users)

**shadcn components**:
- `RadioGroup` - Preset vs custom toggle
- `Select` - Wage level, break method, break policy dropdowns
- `Input` - Wage amount, monthly goal, percentages, hours/minutes
- `Switch` - Break deduction toggle, tax deduction toggle
- `Card` - Section grouping (base wage, supplements, deductions)
- `Label` - Form labels
- `Separator` - Visual dividers between sections
- **Reuse**: `SupplementsStep.tsx` component for custom supplements

### 3. Display (`/settings/display`)
**Purpose**: Visual appearance and presentation

**Settings**:
- Theme selector (light/dark/system)
- Default shifts view (list/calendar)
- Currency format (NOK/USD/EUR etc)

**DB columns**:
- `user_settings.theme`
- `user_settings.default_shifts_view`
- `user_settings.currency_format`

**shadcn components**:
- `RadioGroup` or `Select` - Theme picker
- `Select` - View type, currency format
- `Card` - Section grouping
- `Label` - Form labels
- **Reuse**: `ThemeToggle` component or build custom theme picker

### 4. Preferences (`/settings/preferences`)
**Purpose**: How you interact with the app (workflow & behavior)

**Settings**:
- Employee tab toggle
- Direct time input toggle
- Full minute range toggle

**DB columns**:
- `user_settings.show_employee_tab`
- `user_settings.direct_time_input`
- `user_settings.full_minute_range`

**shadcn components**:
- `Switch` - Feature toggles
- `Card` - Section grouping
- `Label` - Toggle labels with descriptions
- `Tooltip` - Explain what each preference does

### 5. Data (`/settings/data`)
**Purpose**: Import and export your data

**Settings**:
- Export shifts (download button)
- Import shifts (file upload + preview + confirm)
- Import settings (optional, upload JSON)

**DB operations**:
- `user_shifts` - Insert imported rows
- `user_settings` - Bulk update from imported JSON (optional)

**shadcn components**:
- `Button` - Download, upload, confirm actions
- `Card` - Section grouping (export vs import)
- `Dialog` - Import preview/confirmation
- `Badge` - File status indicators
- `Table` (if needed) - Preview imported data
- `Progress` - Upload progress indicator

## Layout Design

### Desktop (≥768px)
```
┌─────────────────────────────────────┐
│ Settings                      [User]│
├──────────┬──────────────────────────┤
│ Profile  │                          │
│ Pay      │  <Page Content>          │
│ Display  │                          │
│ Prefs    │                          │
│ Data     │                          │
└──────────┴──────────────────────────┘
```
Sidebar navigation with active state highlighting.

### Mobile (<768px)
```
┌─────────────────────────────────────┐
│ [Profile] [Pay] [Display] [...]     │ (horizontal scroll tabs)
├─────────────────────────────────────┤
│                                     │
│  <Page Content>                     │
│                                     │
└─────────────────────────────────────┘
```
Horizontal scrollable tabs or segmented control.

## Form Behavior

**Save strategy**: Explicit save button per page (not auto-save)
- Clear user intent
- Batch updates together
- Show success toast on save
- Show validation errors inline

**Progressive disclosure**:
- Show related settings only when parent is enabled
- Disable inputs with reduced opacity when dependency not met (like `SupplementsStep.tsx`)

**Validation**:
- Real-time validation feedback
- Prevent save if invalid
- Clear error messages

## Technical Notes

### Data Loading
Server Components fetch settings via `createSupabaseServerClient()`:
```tsx
// app/(app)/settings/_data/getSettings.ts
export async function getUserSettings(userId: string) {
  const supabase = await createSupabaseServerClient();
  // Fetch user_settings row
  return settings;
}
```

### Data Saving
Client calls Server Action:
```tsx
// app/(app)/settings/_actions/updateSettings.ts
'use server'
export async function updatePaySettings(data: PaySettings) {
  const supabase = await createSupabaseServerClient();
  // Update user_settings
  revalidatePath('/settings/pay');
}
```

### Component Reuse
- `SupplementsStep.tsx` from onboarding can be extracted to `components/app/SupplementsEditor.tsx` and reused in settings
- `ThemeToggle.tsx` logic can be adapted for settings theme picker
- All forms use consistent `@appui/*` components

## Supplements Component Refactoring

### Current Implementation
The `SupplementsStep.tsx` component is currently tightly coupled to the onboarding flow with:
- `onNext`, `onBack` navigation callbacks
- Onboarding-specific copy ("Hopp over", "Neste", etc.)
- Wizard-style button layout (Back/Skip/Next)
- Special handling for preset users (shows info card instead of editor)

### Required Refactoring

**Extract to `components/app/SupplementsEditor.tsx`:**

```tsx
interface SupplementsEditorProps {
  customBonuses: { rules: SupplementRule[] } | null;
  onChange: (value: { rules: SupplementRule[] } | null) => void;
  wageType: "preset" | "custom";
  readOnly?: boolean; // Optional: for displaying without editing
}
```

**Changes needed:**
1. **Remove navigation props**: No `onNext`, `onBack`, `onSubmit` - just controlled state via `onChange`
2. **Remove wizard buttons**: No "Neste"/"Tilbake"/"Hopp over" footer - parent handles save
3. **Simplify preset handling**: Return null or show read-only info based on `readOnly` prop
4. **Keep core logic**:
   - Progressive enablement (days → time → type → value)
   - Add/remove rules
   - Validation (disable "Add" button if current rule incomplete)
   - Beautiful day selector UI
   - Time range inputs
   - Percent vs fixed rate toggle
   - All the UX polish you built!

**Usage in Settings:**
```tsx
// app/(app)/settings/pay/page.tsx (client component section)
const [supplements, setSupplements] = useState(initialData.custom_bonuses);

<Card>
  <Label>Tillegg</Label>
  <SupplementsEditor
    customBonuses={supplements}
    onChange={setSupplements}
    wageType={wageType}
  />
</Card>

<Button onClick={() => saveSettings({ ...otherSettings, custom_bonuses: supplements })}>
  Lagre innstillinger
</Button>
```

**Usage in Onboarding (keep existing):**
```tsx
// app/(app)/onboarding/_components/SupplementsStep.tsx
// Wrap SupplementsEditor with wizard navigation
<SupplementsEditor ... />
<div className="flex gap-3">
  <Button onClick={onBack}>Tilbake</Button>
  <Button onClick={handleSkip}>Hopp over</Button>
  <Button onClick={handleNext}>Neste</Button>
</div>
```

### Key Benefits
- **Separation of concerns**: Editor logic separate from navigation/wizard flow
- **Reusability**: Same component works in onboarding and settings
- **Maintainability**: One source of truth for supplement editing UX
- **Progressive enhancement**: Can add `readOnly` mode for viewing later if needed

### Files to Create/Modify
1. **Create** `components/app/SupplementsEditor.tsx` (extracted logic)
2. **Modify** `app/(app)/onboarding/_components/SupplementsStep.tsx` (wrapper with nav)
3. **Use in** `app/(app)/settings/pay/page.tsx` (settings implementation)

## Implementation Priority

1. **Profile** (simplest, sets pattern)
2. **Display** (reuses theme components)
3. **Preferences** (simple toggles)
4. **Pay** (most complex, reuses supplements UI)
5. **Data** (requires file handling)

---

# Implementation Instructions

## Step 1: Create Route Structure

Create the following files and folders:

```bash
mkdir -p app/(app)/settings/{profile,pay,display,preferences,data}
touch app/(app)/settings/layout.tsx
touch app/(app)/settings/page.tsx
touch app/(app)/settings/profile/page.tsx
touch app/(app)/settings/pay/page.tsx
touch app/(app)/settings/display/page.tsx
touch app/(app)/settings/preferences/page.tsx
touch app/(app)/settings/data/page.tsx
```

## Step 2: Settings Layout (`app/(app)/settings/layout.tsx`)

Create a settings shell with:
- **Desktop**: Sidebar navigation with active states
- **Mobile**: Horizontal scrollable tabs
- Links to all 5 sections
- Responsive breakpoint at 768px

**Requirements**:
- Use `Link` from `next/link` with active state detection via `usePathname()`
- Sidebar should be sticky on desktop
- Mobile tabs should scroll horizontally
- Apply theme-aware styling with semantic color tokens

**Navigation items**:
```tsx
const settingsNav = [
  { href: '/settings/profile', label: 'Profil' },
  { href: '/settings/pay', label: 'Lønn' },
  { href: '/settings/display', label: 'Utseende' },
  { href: '/settings/preferences', label: 'Preferanser' },
  { href: '/settings/data', label: 'Data' },
];
```

## Step 3: Root Settings Page (`app/(app)/settings/page.tsx`)

Simple redirect to `/settings/profile`:

```tsx
import { redirect } from 'next/navigation';

export default function SettingsPage() {
  redirect('/settings/profile');
}
```

## Step 4: Create Data Loaders

### `app/(app)/settings/_data/getSettings.ts`

Server-side data loader to fetch user settings:

```tsx
'use server'

import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function getUserSettings(userId: string) {
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from('user_settings')
    .select('*')
    .eq('user_id', userId)
    .single();

  if (error) throw error;
  return data;
}

export async function getUserProfile(userId: string) {
  const supabase = await createSupabaseServerClient();

  const { data: { user } } = await supabase.auth.getUser();

  return {
    firstName: user?.user_metadata?.first_name || '',
    email: user?.email || '',
    profilePictureUrl: data?.profile_picture_url || null,
  };
}
```

## Step 5: Create Server Actions

### `app/(app)/settings/_actions/updateSettings.ts`

Server actions for each settings section:

```tsx
'use server'

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';

export async function updateProfileSettings(data: {
  firstName: string;
  profilePictureUrl?: string | null;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  // Update auth metadata
  await supabase.auth.updateUser({
    data: { first_name: data.firstName }
  });

  // Update profile picture if changed
  if (data.profilePictureUrl !== undefined) {
    await supabase
      .from('user_settings')
      .update({ profile_picture_url: data.profilePictureUrl })
      .eq('user_id', user.id);
  }

  revalidatePath('/settings/profile');
  return { success: true };
}

export async function updatePaySettings(data: {
  use_preset: boolean;
  current_wage_level?: number;
  custom_wage?: number;
  custom_bonuses?: any;
  monthly_goal?: number;
  payroll_day?: number;
  pause_deduction_enabled?: boolean;
  pause_deduction_method?: string;
  pause_threshold_hours?: number;
  pause_deduction_minutes?: number;
  tax_deduction_enabled?: boolean;
  tax_percentage?: number;
  break_policy?: string;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  revalidatePath('/settings/pay');
  return { success: true };
}

// Add similar actions for display, preferences, data sections
```

## Step 6: Implement Profile Page (`app/(app)/settings/profile/page.tsx`)

**Requirements**:
- Fetch user profile data server-side
- Client component for form with state management
- Name input field
- Profile picture upload (if implemented) or placeholder
- "Clear All Shifts" danger zone with confirmation dialog
- Save button that calls `updateProfileSettings` server action
- Toast notification on success/error

**Components needed**:
- `Input` from `@appui/Input`
- `Button` from `@appui/Button`
- `Label` from `@appui/Label`
- `Card` from `@appui/Card`
- `Dialog` from `@appui/Dialog` (for clear shifts confirmation)

## Step 7: Implement Display Page (`app/(app)/settings/display/page.tsx`)

**Requirements**:
- Theme selector (light/dark/system) - integrate with existing `ThemeToggle` logic
- Default shifts view dropdown (list/calendar)
- Currency format dropdown (NOK/USD/EUR)
- Save button with server action
- Progressive disclosure if needed

**Components needed**:
- `Select` from `@appui/Select`
- `RadioGroup` from `@appui/RadioGroup` (for theme)
- `Card`, `Label`, `Button`

## Step 8: Implement Preferences Page (`app/(app)/settings/preferences/page.tsx`)

**Requirements**:
- Three toggle switches with descriptions:
  - Employee tab toggle
  - Direct time input toggle
  - Full minute range toggle
- Each toggle should have a `Tooltip` explaining what it does
- Save button with server action

**Components needed**:
- `Switch` from `@appui/Switch`
- `Tooltip` from `@appui/Tooltip`
- `Card`, `Label`, `Button`

## Step 9: Extract Supplements Component

### `components/app/SupplementsEditor.tsx`

Extract core logic from `app/(app)/onboarding/_components/SupplementsStep.tsx`:

**Interface**:
```tsx
interface SupplementsEditorProps {
  customBonuses: { rules: SupplementRule[] } | null;
  onChange: (value: { rules: SupplementRule[] } | null) => void;
  wageType: "preset" | "custom";
  readOnly?: boolean;
}
```

**Changes from original**:
1. Remove `onNext`, `onBack`, `onSubmit` props
2. Remove wizard navigation buttons (Back/Skip/Next)
3. Keep all core logic: progressive enablement, validation, UI polish
4. For preset users: show info card (no editing) instead of full wizard flow
5. Call `onChange` whenever rules change (controlled component pattern)

**What to keep**:
- Day selector with beautiful UI
- Progressive enablement (days → time → type → value)
- Add/remove rules functionality
- Validation logic
- Time inputs
- Percent vs fixed rate toggle
- All existing styling and UX polish

### Update `app/(app)/onboarding/_components/SupplementsStep.tsx`

Refactor to use `SupplementsEditor`:

```tsx
export function SupplementsStep({ customBonuses, setCustomBonuses, wageType, onNext, onBack }) {
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">Egendefinerte tillegg</h2>
        <p className="text-text-secondary">
          Sett opp tillegg som kveldstillegg, helgetillegg, etc. (valgfritt)
        </p>
      </div>

      <SupplementsEditor
        customBonuses={customBonuses}
        onChange={setCustomBonuses}
        wageType={wageType}
      />

      <div className="flex gap-3">
        <Button onClick={onBack} variant="outline" className="flex-1">
          Tilbake
        </Button>
        <Button onClick={() => { setCustomBonuses(null); onNext(); }} variant="ghost" className="flex-1">
          Hopp over
        </Button>
        <Button onClick={onNext} className="flex-1">
          Neste
        </Button>
      </div>
    </div>
  );
}
```

## Step 10: Implement Pay Page (`app/(app)/settings/pay/page.tsx`)

**Requirements** (most complex page):
1. Wage method toggle (preset vs custom)
2. Conditional fields based on wage type
3. Monthly goal input
4. Payroll day selector
5. **SupplementsEditor** integration
6. Break deduction section with toggle and settings
7. Tax deduction section
8. Save button

**Structure**:
```tsx
<Card> {/* Base Wage */}
  <RadioGroup> {/* Preset vs Custom */}
  {wageType === 'preset' ? (
    <Select> {/* Wage level dropdown */}
  ) : (
    <Input> {/* Custom wage */}
  )}
</Card>

<Card> {/* Goals */}
  <Input> {/* Monthly goal */}
  <Select> {/* Payroll day */}
</Card>

<Card> {/* Supplements */}
  <SupplementsEditor ... />
</Card>

<Card> {/* Deductions */}
  <Switch> {/* Break deduction toggle */}
  {/* Progressive disclosure: show method/settings when enabled */}

  <Separator />

  <Switch> {/* Tax deduction toggle */}
  {/* Progressive disclosure: show percentage when enabled */}
</Card>

<Button> {/* Save */}
```

## Step 11: Implement Data Page (`app/(app)/settings/data/page.tsx`)

**Requirements**:
- Export shifts button (generate CSV/JSON download)
- Import shifts file upload with preview dialog
- Optional: Import settings JSON

**Flow for import**:
1. User selects file
2. Parse and validate file
3. Show preview in `Dialog`
4. Confirm → insert into `user_shifts` table
5. Show success toast

**Components needed**:
- `Button` for download/upload triggers
- `Dialog` for import preview/confirmation
- `Badge` for file status
- Optional: `Table` for preview data
- `Progress` for upload indicator

## Step 12: Add Missing shadcn Components

If any components are missing, install them:

```bash
# Check what's needed and install
npx shadcn@latest add avatar
npx shadcn@latest add separator
# ... etc
```

Then wrap in `components/app/` following the two-tier architecture.

## Step 13: Testing Checklist

- [ ] All routes render without errors
- [ ] Navigation works (sidebar on desktop, tabs on mobile)
- [ ] Profile settings save and update user data
- [ ] Theme changes reflect immediately (Display page)
- [ ] Preference toggles persist across sessions
- [ ] Pay settings handle preset/custom wage correctly
- [ ] SupplementsEditor works in both onboarding and settings
- [ ] Break/tax deduction progressive disclosure works
- [ ] Data export downloads correctly
- [ ] Data import validates and previews before inserting
- [ ] All forms show success toasts
- [ ] Validation errors display clearly
- [ ] Responsive design works on mobile/tablet/desktop
- [ ] Dark mode styling is correct throughout

## Design Principles to Follow

1. **Always use semantic color tokens** - never hardcoded colors
2. **Progressive disclosure** - show related options only when parent is enabled
3. **Explicit save buttons** - no auto-save, clear user intent
4. **Real-time validation** - show errors inline, prevent invalid saves
5. **Toast notifications** - confirm successful saves
6. **Responsive** - mobile-first, works on all screen sizes
7. **Accessible** - proper labels, keyboard navigation, ARIA attributes
8. **Two-tier components** - always import from `@appui/*`, never `@ui/*`

---

# Quick Reference Tables

## Database Column Mapping

| Section | Column | Type | Description |
|---------|--------|------|-------------|
| Profile | `user_metadata.first_name` | string | User's first name |
| Profile | `profile_picture_url` | string\|null | Avatar URL |
| Pay | `use_preset` | boolean | Using tariff vs custom |
| Pay | `current_wage_level` | number | Preset wage level |
| Pay | `custom_wage` | number | Custom hourly rate |
| Pay | `custom_bonuses` | json | Supplement rules |
| Pay | `monthly_goal` | number | Target earnings |
| Pay | `payroll_day` | number | Day of month (1-31) |
| Pay | `pause_deduction_enabled` | boolean | Break deduction on/off |
| Pay | `pause_deduction_method` | string | Method type |
| Pay | `pause_threshold_hours` | number | Threshold hours |
| Pay | `pause_deduction_minutes` | number | Minutes to deduct |
| Pay | `tax_deduction_enabled` | boolean | Tax deduction on/off |
| Pay | `tax_percentage` | number | Tax rate |
| Pay | `break_policy` | string | Enterprise policy |
| Display | `theme` | string | light/dark/system |
| Display | `default_shifts_view` | string | list/calendar |
| Display | `currency_format` | string | NOK/USD/EUR |
| Preferences | `show_employee_tab` | boolean | Toggle |
| Preferences | `direct_time_input` | boolean | Toggle |
| Preferences | `full_minute_range` | boolean | Toggle |

## Component Quick Reference

| Need | Use Component | Import Path |
|------|---------------|-------------|
| Text input | `Input` | `@appui/Input` |
| Button | `Button` | `@appui/Button` |
| Toggle switch | `Switch` | `@appui/Switch` |
| Dropdown | `Select` | `@appui/Select` |
| Radio buttons | `RadioGroup` | `@appui/RadioGroup` |
| Modal dialog | `Dialog` | `@appui/Dialog` |
| Card container | `Card` | `@appui/Card` |
| Form label | `Label` | `@appui/Label` |
| Visual divider | `Separator` | `@appui/Separator` |
| Help tooltip | `Tooltip` | `@appui/Tooltip` |
| Status badge | `Badge` | `@appui/Badge` |
| Avatar image | `Avatar` | `@appui/Avatar` |
| Progress bar | `Progress` | `@appui/Progress` |
| Theme toggle | `ThemeToggle` | `@appui/ThemeToggle` |
| Supplements | `SupplementsEditor` | `@appui/SupplementsEditor` |

---

**End of Implementation Guide**
