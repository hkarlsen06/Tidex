# Onboarding Flow

**Route**: `app/(app)/onboarding/page.tsx`
**Purpose**: Guide new users through initial setup to ensure they can immediately start tracking shifts and wages.

---

## Overview

The onboarding flow collects the minimum required configuration for wage calculation and shift tracking. It should feel fast, friendly, and contextual. The goal is to get users to their first shift ASAP while explaining why each setting matters.

---

## Flow Structure

### Multi-step form (3-4 steps)

**Design**: Use a step indicator at the top (e.g., `1 of 3`, `2 of 3`) with progress bar. Each step is a full-screen card similar to the current onboarding placeholder design.

### Step Indicator Component

**Components Used**:
- **`Progress`** - Visual progress bar
- Text showing "Steg X av Y"

```tsx
<div className="space-y-2 mb-8">
  <div className="flex items-center justify-between text-sm">
    <span className="text-text-secondary">Steg {currentStep} av {totalSteps}</span>
    <span className="text-text-secondary">{Math.round((currentStep / totalSteps) * 100)}%</span>
  </div>
  <Progress value={(currentStep / totalSteps) * 100} />
</div>
```

---

## Step 1: Wage Configuration

**Title**: "Hva er din timelønn?"
**Subtitle**: "Vi trenger dette for å beregne lønnen din nøyaktig."

### Components Used
- **`RadioGroup`** + **`RadioGroupItem`** - Wage type selector
- **`Select`** + **`SelectTrigger`** + **`SelectContent`** + **`SelectItem`** - Preset level dropdown
- **`Input`** - Custom wage numeric input
- **`Label`** - All field labels
- **`Button`** - "Neste" CTA

### Fields

#### 1. Wage Type Selector

**Component**: `RadioGroup` with `RadioGroupItem`

```tsx
<RadioGroup value={wageType} onValueChange={setWageType}>
  <div className="flex items-center space-x-2">
    <RadioGroupItem value="preset" id="preset" />
    <Label htmlFor="preset">Jeg er på tariffavtale</Label>
  </div>
  <div className="flex items-center space-x-2">
    <RadioGroupItem value="custom" id="custom" />
    <Label htmlFor="custom">Jeg har egendefinert lønn</Label>
  </div>
</RadioGroup>
```

- **Option A**: "Jeg er på tariffavtale" (Preset/tariff)
  - Shows dropdown with preset wage levels
- **Option B**: "Jeg har egendefinert lønn" (Custom wage)
  - Shows numeric input for hourly rate

#### 2A. Preset Selector (if Option A selected)

**Component**: `Select` with dropdown items

```tsx
<div className="space-y-2">
  <Label htmlFor="wage-level">Velg tariff nivå</Label>
  <Select value={wageLevel} onValueChange={setWageLevel}>
    <SelectTrigger id="wage-level">
      <SelectValue placeholder="Velg nivå" />
    </SelectTrigger>
    <SelectContent>
      <SelectItem value="-2">Ikke faglært (lav) - 132.90 kr/t</SelectItem>
      <SelectItem value="-1">Ikke faglært - 129.91 kr/t</SelectItem>
      <SelectItem value="1">Tariff Nivå 1 - 184.54 kr/t</SelectItem>
      <SelectItem value="2">Tariff Nivå 2 - 185.38 kr/t</SelectItem>
      <SelectItem value="3">Tariff Nivå 3 - 187.46 kr/t</SelectItem>
      <SelectItem value="4">Tariff Nivå 4 - 193.05 kr/t</SelectItem>
      <SelectItem value="5">Tariff Nivå 5 - 210.81 kr/t</SelectItem>
      <SelectItem value="6">Tariff Nivå 6 - 256.14 kr/t</SelectItem>
    </SelectContent>
  </Select>
</div>
```

Dropdown with preset wage levels from `PRESET_WAGE_RATES` in `lib/payroll/calc.ts`:

| Level | Label | Rate (NOK/h) |
|-------|-------|--------------|
| -2 | Ikke faglært (lav) | 132.90 |
| -1 | Ikke faglært | 129.91 |
| 1 | Tariff Nivå 1 | 184.54 |
| 2 | Tariff Nivå 2 | 185.38 |
| 3 | Tariff Nivå 3 | 187.46 |
| 4 | Tariff Nivå 4 | 193.05 |
| 5 | Tariff Nivå 5 | 210.81 |
| 6 | Tariff Nivå 6 | 256.14 |

**Default**: Level 1 (184.54 NOK/h)

**Display format**: Show both label and rate: `"Tariff Nivå 1 (184.54 kr/t)"`

#### 2B. Custom Wage Input (if Option B selected)

**Component**: `Input` with numeric type

```tsx
<div className="space-y-2">
  <Label htmlFor="custom-wage">Timelønn</Label>
  <div className="relative">
    <Input
      id="custom-wage"
      type="number"
      min={100}
      value={customWage}
      onChange={(e) => setCustomWage(e.target.value)}
      className="pr-12"
    />
    <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
      kr/t
    </span>
  </div>
</div>
```

- Input field: numeric, suffix "kr/t"
- Validation: minimum 100 NOK/h (prevent typos)
- Default: 200 NOK/h

### Data to save

- `user_settings.use_preset`: `true` (Option A) or `false` (Option B)
- `user_settings.current_wage_level`: Selected level (if preset)
- `user_settings.custom_wage`: Entered rate (if custom)

---

## Step 2: Break Policy

**Title**: "Pauseinnstillinger"
**Subtitle**: "Automatisk trekk for lovpålagt pause."

### Components Used
- **`Switch`** - Enable/disable break toggle
- **`Input`** - Threshold and duration numeric inputs
- **`Select`** - Break method dropdown
- **`Label`** - Field labels
- **`Tooltip`** + **`TooltipProvider`** + **`TooltipTrigger`** + **`TooltipContent`** - Help text for break methods
- **`Badge`** - "Anbefalt" tag on default method
- **`Separator`** - Visual divider between sections
- **`Button`** - "Neste" CTA

### Fields

#### 1. Enable Breaks Toggle

**Component**: `Switch` with `Label`

```tsx
<div className="flex items-center justify-between space-x-2">
  <div className="space-y-0.5">
    <Label htmlFor="break-enabled">Trekk automatisk pause fra vakter</Label>
    <p className="text-sm text-text-muted">
      Anbefalt: Lovpålagt 30 min pause etter 5,5 timer
    </p>
  </div>
  <Switch
    id="break-enabled"
    checked={breakEnabled}
    onCheckedChange={setBreakEnabled}
  />
</div>
```

- Label: "Trekk automatisk pause fra vakter"
- Default: `true`
- Helper text: "Anbefalt: Lovpålagt 30 min pause etter 5,5 timer."

#### 2. Break Settings (shown if enabled)

**Break Threshold**

**Component**: `Input` with suffix

```tsx
<div className="space-y-2">
  <Label htmlFor="threshold">Pause trekkes når vakten er lengre enn</Label>
  <div className="relative">
    <Input
      id="threshold"
      type="number"
      step={0.5}
      min={4}
      max={8}
      value={threshold}
      onChange={(e) => setThreshold(e.target.value)}
      className="pr-16"
    />
    <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
      timer
    </span>
  </div>
</div>
```

- Label: "Pause trekkes når vakten er lengre enn"
- Default: `5.5` hours
- Suffix: "timer"

**Break Duration**

**Component**: `Input` with suffix

```tsx
<div className="space-y-2">
  <Label htmlFor="duration">Pauselengde</Label>
  <div className="relative">
    <Input
      id="duration"
      type="number"
      min={15}
      step={15}
      value={duration}
      onChange={(e) => setDuration(e.target.value)}
      className="pr-20"
    />
    <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
      minutter
    </span>
  </div>
</div>
```

- Label: "Pauselengde"
- Default: `30` minutes
- Suffix: "minutter"

**Break Method**

**Component**: `Select` with `Tooltip` helpers and `Badge` for recommended option

```tsx
<div className="space-y-2">
  <Label htmlFor="method">Hvordan trekkes pausen?</Label>
  <Select value={method} onValueChange={setMethod}>
    <SelectTrigger id="method">
      <SelectValue />
    </SelectTrigger>
    <SelectContent>
      <SelectItem value="proportional">
        <div className="flex items-center gap-2">
          <span>Proporsjonal (fordelt over hele vakten)</span>
          <Badge variant="secondary">Anbefalt</Badge>
        </div>
      </SelectItem>
      <SelectItem value="base_only">
        Fra grunntid (unngå tillegg)
      </SelectItem>
      <SelectItem value="end_of_shift">
        Fra slutten av vakten
      </SelectItem>
      <SelectItem value="none">
        Ingen automatisk trekk
      </SelectItem>
    </SelectContent>
  </Select>

  <TooltipProvider>
    <div className="space-y-2 text-sm text-text-muted">
      <div className="flex items-start gap-2">
        <Tooltip>
          <TooltipTrigger asChild>
            <InfoIcon className="h-4 w-4 mt-0.5 cursor-help" />
          </TooltipTrigger>
          <TooltipContent className="max-w-xs">
            <p><strong>Proporsjonal:</strong> Pausen fordeles jevnt over hele vakten, inkludert tid med tillegg.</p>
            <p><strong>Fra grunntid:</strong> Trekker bare fra perioder med grunnlønn (bevarer mest mulig tillegg).</p>
            <p><strong>Fra slutten:</strong> Trekker fra de siste minuttene av vakten.</p>
            <p><strong>Ingen trekk:</strong> Du må manuelt registrere pauser i hver vakt.</p>
          </TooltipContent>
        </Tooltip>
        <span>Trykk for å se forklaring av metodene</span>
      </div>
    </div>
  </TooltipProvider>
</div>
```

- Label: "Hvordan trekkes pausen?"
- Options:
  - `proportional`: "Proporsjonal (fordelt over hele vakten)" ← default with `Badge`
  - `base_only`: "Fra grunntid (unngå tillegg)"
  - `end_of_shift`: "Fra slutten av vakten"
  - `none`: "Ingen automatisk trekk"
- Helper text for each option via `Tooltip`:
  - **Proportional**: "Pausen fordeles jevnt over hele vakten, inkludert tid med tillegg."
  - **Base only**: "Trekker bare fra perioder med grunnlønn (bevarer mest mulig tillegg)."
  - **End of shift**: "Trekker fra de siste minuttene av vakten."
  - **None**: "Du må manuelt registrere pauser i hver vakt."

### Data to save

- `user_settings.break_enabled`: `true` or `false`
- `user_settings.break_method`: selected method
- `user_settings.break_threshold_hours`: entered threshold
- `user_settings.break_deduction_minutes`: entered duration

---

## Step 3: Bonus Rules (Optional - Consider skipping for MVP)

**Title**: "Har du tillegg?"
**Subtitle**: "Legg til kvelds-, natt- og helgetillegg hvis relevant."

### Components Used
- **`RadioGroup`** + **`RadioGroupItem`** - Bonus type selector
- **`Label`** - Field labels
- **`Badge`** - "Anbefalt" tag on preset option
- **`Button`** - "Neste" / "Hopp over" CTAs

### Fields

#### 1. Bonus Type Toggle

**Component**: `RadioGroup` with `RadioGroupItem`

```tsx
<RadioGroup value={bonusType} onValueChange={setBonusType}>
  <div className="flex items-center space-x-2">
    <RadioGroupItem value="preset" id="bonus-preset" />
    <Label htmlFor="bonus-preset" className="flex items-center gap-2">
      Jeg bruker standard tariff-tillegg
      <Badge variant="secondary">Anbefalt</Badge>
    </Label>
  </div>
  <div className="flex items-center space-x-2">
    <RadioGroupItem value="custom" id="bonus-custom" />
    <Label htmlFor="bonus-custom">Jeg har egendefinerte tillegg</Label>
  </div>
  <div className="flex items-center space-x-2">
    <RadioGroupItem value="none" id="bonus-none" />
    <Label htmlFor="bonus-none">Jeg har ingen tillegg</Label>
  </div>
</RadioGroup>
```

- **Option A**: "Jeg bruker standard tariff-tillegg" (Preset bonuses) + `Badge`
  - No additional fields (uses `presetRules` from system)
- **Option B**: "Jeg har egendefinerte tillegg" (Custom bonuses)
  - Shows message: "Du kan konfigurere egne regler i Innstillinger etter onboarding"
- **Option C**: "Jeg har ingen tillegg"
  - Sets `custom_bonuses` to empty

#### 2. Bonus Rule Builder (if custom selected)

For MVP onboarding, show a **simple preset selector** instead of full builder:

**Common Presets**:
- "Kvelds- og nattillegg (standard)"
- "Helgetillegg (lørdag/søndag)"
- "Ingen tillegg"
- "Legg til egne regler senere" ← redirects to Settings after onboarding

**Note**: Full custom bonus builder should live in Settings page. Onboarding should be quick.

### Data to save

- `user_settings.custom_bonuses`: null (use preset) or basic rules structure

**Alternative**: Skip this step entirely in onboarding and default to preset bonuses. Add a banner after onboarding: "Vil du tilpasse tilleggsreglene? Gå til Innstillinger."

---

## Step 4: Theme & Preferences

**Title**: "Tilpass opplevelsen"
**Subtitle**: "Velg tema og visning."

### Components Used
- **`RadioGroup`** + **`RadioGroupItem`** - Theme selector and shifts view selector
- **`Input`** - Monthly goal numeric input
- **`Label`** - Field labels
- **`Separator`** - Visual dividers between sections
- **`Button`** - "Fullfør" CTA

### Fields

#### 1. Theme Selector

**Component**: `RadioGroup` with visual preview

```tsx
<div className="space-y-3">
  <Label>Velg tema</Label>
  <RadioGroup value={theme} onValueChange={setTheme}>
    <div className="flex items-center space-x-2">
      <RadioGroupItem value="light" id="theme-light" />
      <Label htmlFor="theme-light" className="flex items-center gap-2">
        ☀️ Lys
      </Label>
    </div>
    <div className="flex items-center space-x-2">
      <RadioGroupItem value="dark" id="theme-dark" />
      <Label htmlFor="theme-dark" className="flex items-center gap-2">
        🌙 Mørk
      </Label>
    </div>
    <div className="flex items-center space-x-2">
      <RadioGroupItem value="system" id="theme-system" />
      <Label htmlFor="theme-system" className="flex items-center gap-2">
        💻 System
      </Label>
    </div>
  </RadioGroup>
</div>
```

- Options: "Lys", "Mørk", "System"
- Default: "Mørk"
- Shows live preview (toggle theme class on `<html>`)

#### 2. Default Shifts View

**Component**: `RadioGroup`

```tsx
<div className="space-y-3">
  <Label>Foretrekker du liste eller kalendervisning?</Label>
  <RadioGroup value={shiftsView} onValueChange={setShiftsView}>
    <div className="flex items-center space-x-2">
      <RadioGroupItem value="list" id="view-list" />
      <Label htmlFor="view-list">📋 Liste</Label>
    </div>
    <div className="flex items-center space-x-2">
      <RadioGroupItem value="calendar" id="view-calendar" />
      <Label htmlFor="view-calendar">📅 Kalender</Label>
    </div>
  </RadioGroup>
</div>
```

- Label: "Foretrekker du liste eller kalendervisning?"
- Options: "Liste", "Kalender"
- Default: "Liste"

#### 3. Monthly Goal (Optional)

**Component**: `Input` with suffix

```tsx
<div className="space-y-2">
  <Label htmlFor="monthly-goal">Har du et månedlig lønnsmål?</Label>
  <p className="text-sm text-text-muted">
    Dette brukes til å vise progresjon på dashbordet
  </p>
  <div className="relative">
    <Input
      id="monthly-goal"
      type="number"
      min={0}
      step={1000}
      value={monthlyGoal}
      onChange={(e) => setMonthlyGoal(e.target.value)}
      placeholder="20000"
      className="pr-12"
    />
    <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
      kr
    </span>
  </div>
</div>
```

- Label: "Har du et månedlig lønnsmål?"
- Input: numeric, optional
- Suffix: "kr"
- Default: 20,000 NOK
- Helper text: "Dette brukes til å vise progresjon på dashbordet."

### Data to save

- `user_settings.theme`: selected theme
- `user_settings.default_shifts_view`: "list" or "calendar"
- `user_settings.monthly_goal`: entered goal (or default)

---

## Final Step: Completion

**Title**: "Ferdig!"
**Subtitle**: "Du er klar til å registrere din første vakt."

### Components Used
- **`Card`** - Container for summary
- **`Badge`** - Status badges for each setting
- **`Separator`** - Dividers between summary items
- **`Button`** - "Gå til hjem" CTA

### Content

```tsx
<div className="space-y-6 text-center">
  <div className="flex items-center justify-center">
    <div className="rounded-full bg-success-subtle p-4">
      <CheckCircle className="h-12 w-12 text-success-foreground" />
    </div>
  </div>

  <div className="space-y-4">
    <h2 className="text-2xl font-bold">Alt er klart!</h2>
    <p className="text-text-secondary">
      Her er en oppsummering av dine innstillinger
    </p>
  </div>

  <Separator />

  <div className="space-y-3 text-left">
    <div className="flex items-center justify-between">
      <span className="text-text-secondary">Timelønn</span>
      <Badge variant="secondary">{wageDisplay}</Badge>
    </div>
    <div className="flex items-center justify-between">
      <span className="text-text-secondary">Pause</span>
      <Badge variant="secondary">
        {breakEnabled ? `${duration} min etter ${threshold} timer` : "Av"}
      </Badge>
    </div>
    <div className="flex items-center justify-between">
      <span className="text-text-secondary">Tema</span>
      <Badge variant="secondary">{theme}</Badge>
    </div>
  </div>

  <Separator />

  <Button onClick={handleComplete} className="w-full">
    Gå til hjem
  </Button>
</div>
```

- Success animation or checkmark icon
- Summary of configured settings:
  - "Din timelønn: X kr/t"
  - "Pause: 30 min etter 5,5 timer (proporsjonal)"
  - "Tillegg: Standard tariff"
  - "Tema: Mørk"
- CTA button: "Gå til hjem" → redirect to `/`

### Data to finalize

- **Mark onboarding as complete**: Update `auth.users.raw_user_meta_data.finishedOnboarding` to `true`
  - Use `supabase.auth.updateUser({ data: { finishedOnboarding: true } })`
- Create/update `user_settings` row with all collected data
- Create initial `profiles` row if not exists (should already exist from `handle_new_user` trigger)

---

## Technical Implementation

### Component Structure

```
app/(app)/onboarding/
├── page.tsx              # Main onboarding orchestrator (Server Component)
├── _components/
│   ├── OnboardingForm.tsx    # Client component with step state
│   ├── StepIndicator.tsx     # Progress bar (1 of 4, 2 of 4, etc.)
│   ├── WageStep.tsx          # Step 1
│   ├── BreakStep.tsx         # Step 2
│   ├── BonusStep.tsx         # Step 3 (optional)
│   ├── PreferencesStep.tsx   # Step 4
│   └── CompletionStep.tsx    # Final step
└── actions.ts            # Server actions for saving settings
```

### Data Flow

1. **Load defaults**: Server Component fetches existing `user_settings` (if any) and passes to client form
2. **Client state**: `OnboardingForm` manages step index and form state
3. **Validation**: Each step validates on "Neste" click
4. **Save**: Final step calls Server Action to:
   - Upsert `user_settings` with all collected data
   - Update `auth.users.raw_user_meta_data.finishedOnboarding = true`
   - Redirect to `/`

### Persistence Strategy

- **Option A**: Save each step incrementally (better UX, prevents data loss)
- **Option B**: Save all at once at the end (simpler code, risk of data loss if user closes tab)

**Recommendation**: Use Option A with Server Actions. Each "Neste" button saves current step data.

---

## Edge Cases & Considerations

### 1. User already has settings
- If `user_settings` row exists (e.g., from Google OAuth or previous partial setup):
  - Pre-fill form with existing values
  - Still require completing all steps (to ensure consistency)

### 2. Skip onboarding?
- Add a "Hopp over og bruk standardinnstillinger" link at the bottom of Step 1
  - Applies defaults:
    - Preset wage level 1
    - Break enabled, proportional, 5.5h threshold, 30min
    - Dark theme, list view, 20k goal
  - Marks onboarding complete and redirects to `/`

### 3. Google OAuth users
- These users already have `name` in metadata
- Onboarding should feel seamless and skip name collection

### 4. Re-running onboarding
- Add a hidden route `/onboarding?force=true` or button in Settings:
  - "Kjør onboarding på nytt"
  - Resets `finishedOnboarding` to `false`
  - Shows the full flow again

---

## Visual Design Notes

- **Match current design system**: Use same card style, colors, gradients as `/login` and `/signup`
- **Animations**: Smooth slide transitions between steps (e.g., Framer Motion or CSS transitions)
- **Validation feedback**: Inline error messages below fields (red text with error icon)
- **Help text**: Use tooltips or expandable sections for complex settings (break method, bonus rules)
- **Mobile-first**: Stack fields vertically on mobile, ensure CTA buttons are thumb-friendly

---

## Post-Onboarding Experience

After completing onboarding and redirecting to `/`:

1. **Show welcome banner** (dismissible):
   - "Velkommen! Klar til å registrere din første vakt?"
   - CTA: "Legg til vakt" → `/shifts/add`
2. **Highlight navigation**:
   - Subtle animation on "Vakter" nav item (if using TopHeader)
3. **Empty state on dashboard**:
   - "Du har ingen vakter ennå. Legg til din første vakt for å se statistikk."
   - CTA button: "Legg til vakt"

---

## Future Enhancements

- **Step 3.5**: Add profile picture upload (optional)
- **Step 2.5**: Explain tax settings (currently in Settings page)
- **Gamification**: "3 av 4 steg fullført!" with confetti on completion
- **A/B testing**: Test different step orders and copy variations
- **Video tutorials**: Embed short explainer videos for complex settings
- **AI assistance**: "Vet ikke hvilken tariff du har? Last opp arbeidsavtale" (OCR/GPT parse)

---

## Questions for Review

1. **Should Step 3 (Bonus Rules) be skipped in MVP?**
   → Simplifies onboarding. Users can configure later in Settings.

2. **Should theme be part of onboarding or auto-detect?**
   → Could default to system theme and skip this field entirely.

3. **Is monthly goal too advanced for onboarding?**
   → Could move to Settings and show as a dashboard prompt after first few shifts.

4. **Should we explain payroll day during onboarding?**
   → Currently in Settings (line 47 in db_tables.md). Might be too much for initial setup.

5. **Do we need email verification reminder?**
   → Show banner if `email_confirmed_at` is null: "Bekreft e-posten din for full funksjonalitet."

---

## Success Metrics

Track these events in analytics (if implemented):

- Onboarding started (user lands on `/onboarding`)
- Step 1 completed
- Step 2 completed
- Step 3 completed (if included)
- Step 4 completed
- Onboarding fully completed
- Onboarding skipped (if skip option added)
- Drop-off rate per step
- Time spent in onboarding
- First shift created within 24h of completing onboarding
