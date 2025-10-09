# Shadcn Components for Onboarding Flow

This document lists the shadcn/ui components needed for implementing the onboarding flow described in `onboarding.md`.

---

## Currently Installed Components

✅ **Already available** (in `components/ui/`):
- `button` - For CTAs and navigation
- `card` - For step containers (already used in login/signup)
- `input` - For text fields (email, custom wage, etc.)
- `input-otp` - For OTP verification (already used in signup)
- `dialog` - For modals/confirmations

---

## Components to Install

### Priority 1: Essential for MVP

#### 1. **Radio Group**
```bash
npx shadcn@latest add radio-group
```
**Use case**: Step 1 - Wage type selector (Preset vs. Custom)
```tsx
<RadioGroup value={wageType} onValueChange={setWageType}>
  <RadioGroupItem value="preset">Jeg er på tariffavtale</RadioGroupItem>
  <RadioGroupItem value="custom">Jeg har egendefinert lønn</RadioGroupItem>
</RadioGroup>
```

#### 2. **Select**
```bash
npx shadcn@latest add select
```
**Use case**: Step 1 - Preset wage level dropdown
```tsx
<Select value={wageLevel} onValueChange={setWageLevel}>
  <SelectTrigger>
    <SelectValue placeholder="Velg tariff nivå" />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="-2">Ikke faglært (lav) - 132.90 kr/t</SelectItem>
    <SelectItem value="-1">Ikke faglært - 129.91 kr/t</SelectItem>
    <SelectItem value="1">Tariff Nivå 1 - 184.54 kr/t</SelectItem>
    {/* ... more options */}
  </SelectContent>
</Select>
```

**Also used in**: Step 2 - Break method dropdown

#### 3. **Switch**
```bash
npx shadcn@latest add switch
```
**Use case**: Step 2 - Enable/disable break deductions
```tsx
<div className="flex items-center space-x-2">
  <Switch id="break-enabled" checked={breakEnabled} onCheckedChange={setBreakEnabled} />
  <Label htmlFor="break-enabled">Trekk automatisk pause fra vakter</Label>
</div>
```

#### 4. **Label**
```bash
npx shadcn@latest add label
```
**Use case**: All steps - Accessible labels for form fields
```tsx
<Label htmlFor="custom-wage">Timelønn (kr/t)</Label>
<Input id="custom-wage" type="number" value={wage} onChange={...} />
```

#### 5. **Progress**
```bash
npx shadcn@latest add progress
```
**Use case**: Step indicator showing onboarding progress
```tsx
<Progress value={(currentStep / totalSteps) * 100} />
<p className="text-sm text-text-secondary">Steg {currentStep} av {totalSteps}</p>
```

### Priority 2: Nice to Have

#### 6. **Slider**
```bash
npx shadcn@latest add slider
```
**Use case**: Step 2 - Visual selection of break threshold hours
```tsx
<Label>Pause trekkes når vakten er lengre enn {threshold} timer</Label>
<Slider value={[threshold]} onValueChange={([v]) => setThreshold(v)}
        min={4} max={8} step={0.5} />
```

**Also useful for**: Step 4 - Monthly goal selection

#### 7. **Separator**
```bash
npx shadcn@latest add separator
```
**Use case**: Visual dividers between form sections within a step
```tsx
<div className="space-y-4">
  <WageTypeSelector />
  <Separator />
  <WageLevelSelector />
</div>
```

#### 8. **Tooltip**
```bash
npx shadcn@latest add tooltip
```
**Use case**: Help text for complex settings (break method, bonus rules)
```tsx
<TooltipProvider>
  <Tooltip>
    <TooltipTrigger asChild>
      <InfoIcon className="h-4 w-4 text-text-muted" />
    </TooltipTrigger>
    <TooltipContent>
      <p>Proporsjonal: Pausen fordeles jevnt over hele vakten</p>
    </TooltipContent>
  </Tooltip>
</TooltipProvider>
```

#### 9. **Badge**
```bash
npx shadcn@latest add badge
```
**Use case**: Highlighting recommended options
```tsx
<SelectItem value="proportional">
  Proporsjonal <Badge variant="secondary">Anbefalt</Badge>
</SelectItem>
```

#### 10. **Tabs** (Alternative design)
```bash
npx shadcn@latest add tabs
```
**Use case**: Alternative to Radio Group for wage type selection
```tsx
<Tabs value={wageType} onValueChange={setWageType}>
  <TabsList>
    <TabsTrigger value="preset">Tariffavtale</TabsTrigger>
    <TabsTrigger value="custom">Egendefinert</TabsTrigger>
  </TabsList>
  <TabsContent value="preset">...</TabsContent>
  <TabsContent value="custom">...</TabsContent>
</Tabs>
```

### Priority 3: Future Enhancements

#### 11. **Accordion**
```bash
npx shadcn@latest add accordion
```
**Use case**: Expandable help sections for complex explanations
```tsx
<Accordion type="single" collapsible>
  <AccordionItem value="break-methods">
    <AccordionTrigger>Hva er forskjellen mellom metodene?</AccordionTrigger>
    <AccordionContent>
      <ul>
        <li><strong>Proporsjonal:</strong> ...</li>
        <li><strong>Fra grunntid:</strong> ...</li>
        {/* ... */}
      </ul>
    </AccordionContent>
  </AccordionItem>
</Accordion>
```

#### 12. **Toggle Group**
```bash
npx shadcn@latest add toggle-group
```
**Use case**: Theme selector (alternative to current ThemeToggle)
```tsx
<ToggleGroup type="single" value={theme} onValueChange={setTheme}>
  <ToggleGroupItem value="light">☀️ Lys</ToggleGroupItem>
  <ToggleGroupItem value="dark">🌙 Mørk</ToggleGroupItem>
  <ToggleGroupItem value="system">💻 System</ToggleGroupItem>
</ToggleGroup>
```

#### 13. **Alert**
```bash
npx shadcn@latest add alert
```
**Use case**: Informational messages and warnings
```tsx
<Alert>
  <AlertCircle className="h-4 w-4" />
  <AlertTitle>Obs!</AlertTitle>
  <AlertDescription>
    Du kan endre disse innstillingene senere i Innstillinger.
  </AlertDescription>
</Alert>
```

---

## Installation Order for MVP

Run these commands in order:

```bash
# Essential components (install all at once)
npx shadcn@latest add radio-group select switch label progress

# Nice to have (install if needed)
npx shadcn@latest add slider separator tooltip badge
```

---

## Component Mapping to Onboarding Steps

### Step 1: Wage Configuration
- ✅ `Card` - Step container
- 🆕 `RadioGroup` - Wage type selector (Preset vs Custom)
- 🆕 `Select` - Preset level dropdown
- 🆕 `Label` - Field labels
- ✅ `Input` - Custom wage input
- ✅ `Button` - "Neste" CTA

### Step 2: Break Policy
- ✅ `Card` - Step container
- 🆕 `Switch` - Enable/disable breaks
- 🆕 `Label` - Field labels
- ✅ `Input` - Threshold and duration inputs
- 🆕 `Select` - Break method dropdown
- 🆕 `Tooltip` (optional) - Explain break methods
- ✅ `Button` - "Neste" CTA

### Step 3: Bonus Rules (Optional MVP)
- ✅ `Card` - Step container
- 🆕 `RadioGroup` - Preset vs Custom bonuses
- 🆕 `Badge` (optional) - "Anbefalt" tag
- ✅ `Button` - "Neste" / "Hopp over"

### Step 4: Theme & Preferences
- ✅ `Card` - Step container
- 🆕 `RadioGroup` or `ToggleGroup` - Theme selector
- 🆕 `RadioGroup` - Default shifts view
- ✅ `Input` - Monthly goal input
- 🆕 `Slider` (optional) - Visual goal selector
- ✅ `Button` - "Fullfør"

### All Steps
- 🆕 `Progress` - Step indicator at top
- 🆕 `Separator` - Visual dividers
- 🆕 `Alert` (optional) - Help messages

---

## App Component Wrappers to Create

After installing the raw shadcn components, create app-specific wrappers in `components/app/`:

1. `RadioGroup.tsx` - Exports from `@ui/radio-group`
2. `Select.tsx` - Exports from `@ui/select`
3. `Switch.tsx` - Exports from `@ui/switch`
4. `Label.tsx` - Exports from `@ui/label`
5. `Progress.tsx` - Exports from `@ui/progress`
6. `Slider.tsx` (if used) - Exports from `@ui/slider`
7. `Separator.tsx` (if used) - Exports from `@ui/separator`
8. `Tooltip.tsx` (if used) - Exports from `@ui/tooltip`
9. `Badge.tsx` (if used) - Exports from `@ui/badge`

**Pattern** (following existing convention):
```tsx
// components/app/RadioGroup.tsx
export * from "../ui/radio-group";
```

Or with additional app-specific logic:
```tsx
// components/app/Select.tsx
import * as React from "react";
import { Select as BaseSelect } from "@ui/select";
import { cn } from "@/lib/cn";

type Props = React.ComponentProps<typeof BaseSelect> & {
  invalid?: boolean;
};

export function Select({ className, invalid, ...props }: Props) {
  return (
    <BaseSelect
      {...props}
      className={cn(invalid && "ring-1 ring-error", className)}
    />
  );
}

// Re-export all other Select subcomponents
export * from "../ui/select";
```

---

## Design Notes

### Consistency with Existing Design
All forms in the app (login, signup, reset-password) use:
- **Card wrapper**: `rounded-3xl border border-border bg-surface-secondary p-10 shadow-app-lg`
- **Input styling**: `rounded-full border border-border-subtle bg-background-primary`
- **Button styling**: Gradient brand buttons for primary CTAs

Onboarding should match this design language.

### Accessibility
- Use `Label` with `htmlFor` for all inputs
- Include `aria-describedby` for help text
- Mark invalid fields with `aria-invalid`
- Ensure keyboard navigation works (Tab, Enter, Space)
- Progress indicator should be announced by screen readers

### Mobile Responsiveness
- Stack form fields vertically on mobile
- Use full-width buttons
- Ensure touch targets are at least 44x44px
- Test Select dropdowns on iOS/Android

---

## Example Component Structure

```tsx
// app/(app)/onboarding/_components/WageStep.tsx
import { RadioGroup, RadioGroupItem } from "@appui/RadioGroup";
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@appui/Select";
import { Label } from "@appui/Label";
import { Input } from "@appui/Input";
import { Button } from "@appui/Button";

export function WageStep({ onNext }: { onNext: () => void }) {
  const [wageType, setWageType] = useState<"preset" | "custom">("preset");
  const [wageLevel, setWageLevel] = useState("1");
  const [customWage, setCustomWage] = useState("200");

  return (
    <div className="space-y-6">
      <RadioGroup value={wageType} onValueChange={(v) => setWageType(v as "preset" | "custom")}>
        <div className="flex items-center space-x-2">
          <RadioGroupItem value="preset" id="preset" />
          <Label htmlFor="preset">Jeg er på tariffavtale</Label>
        </div>
        <div className="flex items-center space-x-2">
          <RadioGroupItem value="custom" id="custom" />
          <Label htmlFor="custom">Jeg har egendefinert lønn</Label>
        </div>
      </RadioGroup>

      {wageType === "preset" ? (
        <div className="space-y-2">
          <Label htmlFor="wage-level">Velg tariff nivå</Label>
          <Select value={wageLevel} onValueChange={setWageLevel}>
            <SelectTrigger id="wage-level">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="1">Tariff Nivå 1 (184.54 kr/t)</SelectItem>
              {/* ... more */}
            </SelectContent>
          </Select>
        </div>
      ) : (
        <div className="space-y-2">
          <Label htmlFor="custom-wage">Timelønn (kr/t)</Label>
          <Input
            id="custom-wage"
            type="number"
            value={customWage}
            onChange={(e) => setCustomWage(e.target.value)}
          />
        </div>
      )}

      <Button onClick={onNext} className="w-full">Neste</Button>
    </div>
  );
}
```

---

## Next Steps

1. **Install Priority 1 components** (radio-group, select, switch, label, progress)
2. **Create app wrappers** in `components/app/`
3. **Build onboarding step components** in `app/(app)/onboarding/_components/`
4. **Test accessibility** with keyboard navigation and screen readers
5. **Add mobile responsiveness** testing

---

## Questions for Implementation

1. **Should we use Tabs instead of RadioGroup for wage type?**
   → Tabs might provide a clearer visual separation

2. **Should monthly goal be a Slider or Input?**
   → Input is more precise, Slider is more playful

3. **Include Tooltip for all help text or use expandable sections?**
   → Tooltips for short hints, Accordion for detailed explanations

4. **Should we animate step transitions?**
   → Would require Framer Motion or CSS transitions (not a shadcn component)
