# Agent Task: Integrate TotalCard Component into Next.js Wage Calculator

## Context

You are working in a Next.js wage calculator application that uses:
- **LiftKit Design System** (custom Material Design 3-based component library)
- **Material Color Utilities** for dynamic theming
- **CSS custom properties** with `--lk-*` design tokens (NOT Tailwind)
- **TypeScript** with strict typing
- Component structure using data attributes for styling

A base `TotalCard.tsx` component has been created in the legacy repo. Your job is to **adapt and integrate it** into this Next.js codebase following the existing patterns.

## Component Purpose

The TotalCard is a hero card that displays monthly wage totals prominently on the dashboard:
- Shows gross wage amount in large display typography
- Optional secondary info (net wage, tax percentage)
- Loading skeleton state
- Glass material effect for elevation
- Clickable for navigation to detailed view

## Your Tasks

### 1. Analyze the Existing Codebase

First, understand the current patterns:

**Study these files:**
- `src/components/card/index.tsx` - The base Card component you'll build upon
- `src/components/card/card.css` - Styling patterns with data attributes
- `src/components/theme/index.tsx` - Theme system and color tokens
- `src/lib/types/lk-*.d.ts` - Available design tokens (colors, typography, sizes)
- `src/lib/utilities.ts` - The `propsToDataAttrs` utility function
- `app/globals.css` - Global LiftKit token definitions

**Key patterns to follow:**
1. Components export props interface with LiftKit types (e.g., `LkCardProps`)
2. Use `propsToDataAttrs()` to convert props to `data-*` attributes
3. Style via CSS files using `[data-lk-component="name"]` selectors
4. Leverage existing components (Card, MaterialLayer) through composition
5. Use design tokens exclusively: `var(--lk-surface)`, `var(--display1-font-size)`

### 2. Create the Component Structure

**File: `src/components/total-card/index.tsx`**

Requirements:
- Use the existing `<Card>` component as the foundation
- Accept these props (adapt types to match your codebase):
  - `label: string` - Label like "Brutto", "Netto"
  - `amount: string` - Formatted amount with currency
  - `secondaryInfo?: string` - Optional secondary text
  - `isLoading?: boolean` - Loading state
  - `onClick?: () => void` - Optional click handler
  - `material?: "flat" | "glass"` - Material type (default: "glass")
  - `bgColor?: LkColorWithOnToken` - Background color token
- Set appropriate Card props:
  - `scaleFactor="display1"` (matches large amount typography)
  - `variant="fill"`
  - `opticalCorrection="all"` (balanced padding)
  - `isClickable` when onClick provided
- Add data attribute: `data-lk-component="total-card"`
- Implement loading skeleton with three shimmer lines
- Add keyboard navigation (Enter/Space trigger onClick)

**Implementation pattern:**
```tsx
"use client";

import Card from '@/components/card';
import { propsToDataAttrs } from '@/lib/utilities';
import './total-card.css';

// Define props interface using LiftKit types
// Use existing Card component
// Add loading skeleton
// Handle click interaction with keyboard support
```

### 3. Create Component Styles

**File: `src/components/total-card/total-card.css`**

Requirements:
- Use data attribute selectors: `[data-lk-component="total-card"]`
- Use only LiftKit design tokens - NO hardcoded values
- Style three elements:
  - `[data-lk-total-card-element="label"]` - Small uppercase label
  - `[data-lk-total-card-element="amount"]` - Large display text
  - `[data-lk-total-card-element="secondary"]` - Body text
- Create loading skeleton:
  - Three shimmer lines using `@keyframes skeleton-shimmer`
  - Gradient: `var(--lk-surfacecontainerlow)` to `var(--lk-surfacecontainerhigh)`
  - Animation: 1.5s ease-in-out infinite
- Support dark mode automatically via tokens

**Typography tokens to use:**
- Label: `var(--label-font-size)`, `var(--label-line-height)`
- Amount: `var(--display1-font-size)`, `var(--display1-font-weight)`, `var(--display1-line-height)`
- Secondary: `var(--body-font-size)`, `var(--body-line-height)`

**Color tokens to use:**
- Text: `var(--lk-onsurface)`, `var(--lk-onsurfacevariant)`
- Skeleton: `var(--lk-surfacecontainerlow)`, `var(--lk-surfacecontainerhigh)`
- Spacing: `var(--lk-size-sm)`, `var(--lk-size-md)`

### 4. Integrate into Dashboard

**File: `app/page.tsx` (or relevant dashboard page)**

Requirements:
- Import TotalCard component
- Fetch wage data from API (create if doesn't exist)
- Format currency using Norwegian locale: `nb-NO` with space separator
- Handle loading state
- Pass appropriate props:
  ```tsx
  <TotalCard
    label="Brutto"
    amount={formatCurrency(wageData.gross)}
    secondaryInfo={`Netto: ${formatCurrency(net)} (${taxRate}% skatt)`}
    isLoading={isLoading}
    material="glass"
    bgColor="surfacecontainerhigh"
  />
  ```

### 5. Create API Route (if needed)

**File: `app/api/wages/route.ts`**

If wage calculation API doesn't exist, create it:
- Accept month/year query params
- Use existing Supabase client: `createClient()` from `@/lib/supabase/server`
- Fetch shifts for the selected month
- Calculate gross wage (port logic from old `/server/payroll/calc.js` if needed)
- Calculate tax deduction and net wage
- Return JSON: `{ gross, net, taxRate }`

### 6. Verify Integration

Check that:
- [ ] Component uses existing Card component (not custom div)
- [ ] All styling uses LiftKit design tokens (`--lk-*`, not custom variables)
- [ ] Loading skeleton animates smoothly
- [ ] Click interaction works (mouse and keyboard)
- [ ] Dark mode works automatically (test theme toggle)
- [ ] Typography scales appropriately
- [ ] Glass material effect is visible
- [ ] Responsive on mobile (padding adjusts via optical correction)
- [ ] Accessibility: keyboard nav, focus states, proper ARIA
- [ ] TypeScript types are correct (no `any` types)

## Important: What NOT to Do

❌ Don't use Tailwind classes - this codebase uses CSS custom properties
❌ Don't create custom CSS variables - use existing `--lk-*` tokens
❌ Don't hardcode colors/sizes - use design tokens exclusively
❌ Don't build a card from scratch - use the existing `<Card>` component
❌ Don't copy the old app's CSS - translate to LiftKit patterns
❌ Don't use inline styles - use data attribute selectors in CSS

## Success Criteria

The component should:
1. Look identical to the original design but use LiftKit components
2. Feel native to this codebase (not like a ported component)
3. Support light/dark themes automatically
4. Work with the existing theme system
5. Follow all established patterns (data attributes, design tokens, composition)
6. Be fully typed with TypeScript
7. Include proper accessibility features

## Reference: Original Component

The original TotalCard from the legacy app:

**HTML Structure (from `/app/index.html` lines 108-120):**
```html
<div class="total-card">
  <div class="total-label">Brutto</div>
  <div class="total-amount" id="totalAmount">0 kr</div>
  <div class="total-secondary-info" id="totalSecondaryInfo">
    <!-- Tax info -->
  </div>
  <!-- Skeleton -->
  <div class="total-skeleton skeleton">
    <div class="skeleton-line"></div>
    <div class="skeleton-line"></div>
    <div class="skeleton-line"></div>
  </div>
</div>
```

**Key Styles to Translate:**
- Card: elevated background with glass effect
- Label: uppercase, small, secondary color
- Amount: very large (display typography), primary color
- Secondary: body size, secondary color
- Skeleton: shimmer animation, three lines

**Behavior:**
- Updates when month changes
- Shows loading skeleton on data fetch
- Clickable to show wage details
- Displays tax calculation info

## Questions to Ask User

If you encounter ambiguity:
1. "Should I create the API route or does it already exist?"
2. "Where should the wage calculation logic live?"
3. "What's the desired click behavior? Navigate or show modal?"
4. "Are there existing formatter utilities I should use?"

## Final Note

You're adapting a component to fit this codebase's architecture. Don't just copy the base component - study the existing patterns in `src/components/card/` and other components, then rebuild TotalCard to match those patterns while preserving the original design and functionality.
