---
name: Tidex
description: Serious, transparent product UI for shift pay clarity.
colors:
  ink-navy: "#020817"
  night-surface: "#16243a"
  night-surface-raised: "#1b2c45"
  paper-mist: "#f5f8fc"
  paper-surface: "#ffffff"
  paper-surface-muted: "#f6f7f8"
  text-primary-dark: "#f2f7fc"
  text-secondary-dark: "#c6d7e6"
  text-muted-dark: "#9db4c8"
  text-primary-light: "#031425"
  text-secondary-light: "#405c72"
  text-muted-light: "#596b80"
  workday-blue: "#4c86ea"
  workday-blue-light: "#3a84e0"
  ledger-cyan: "#22d3ee"
  signal-green: "#22c55e"
  payroll-amber: "#fbbf24"
  error-red: "#ef4444"
  border-dark: "#384761"
  border-dark-subtle: "#303d52"
  border-light: "#c7d1db"
  border-light-subtle: "#d9e0e8"
typography:
  display:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "56pt"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "0"
  headline:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "28pt"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0"
  title:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "22pt"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0"
  body:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "16pt"
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: "0"
  label:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "14pt"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "0"
  mono:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "13pt"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "0"
rounded:
  xxs: "4pt"
  xs: "6pt"
  sm: "8pt"
  md: "10pt"
  lg: "12pt"
  xl: "14pt"
  xxl: "16pt"
  xxxl: "20pt"
  bubble: "18pt"
  card: "24pt"
  pill: "32pt"
spacing:
  micro: "2pt"
  xxs: "4pt"
  xxxs: "6pt"
  xs: "8pt"
  xsm: "10pt"
  sm: "12pt"
  msm: "14pt"
  md: "16pt"
  mlg: "20pt"
  lg: "24pt"
  xl: "32pt"
  xxl: "40pt"
  xxxl: "48pt"
  huge: "56pt"
components:
  button-primary:
    backgroundColor: "{colors.workday-blue}"
    textColor: "{colors.paper-surface}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    height: "48pt"
    padding: "0 16pt"
  button-primary-disabled:
    backgroundColor: "{colors.workday-blue}"
    textColor: "{colors.paper-surface}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    height: "48pt"
    padding: "0 16pt"
  input-default:
    backgroundColor: "{colors.night-surface-raised}"
    textColor: "{colors.text-primary-dark}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "12pt 16pt"
  card-primary:
    backgroundColor: "{colors.night-surface}"
    textColor: "{colors.text-primary-dark}"
    rounded: "{rounded.card}"
    padding: "24pt"
  badge-info:
    backgroundColor: "{colors.workday-blue}"
    textColor: "{colors.paper-surface}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "4pt 8pt"
---

# Design System: Tidex

## 1. Overview

**Creative North Star: "The Shift Ledger"**

Tidex should feel like a precise pay record that happens to live in a modern iPhone app. The surface is calm, assertive, and native; the product earns trust by letting users inspect what happened, what changed, and why a total is what it is.

The system is product-first. It should support fast shift entry, repeated checking, and clear payroll review without turning young shift workers into a childish audience. The visual language is rounded and approachable, but never cute. The interface should look serious enough to sit beside a paycheck, a workplace rota, or a dispute with payroll.

It explicitly rejects the anti-references in PRODUCT.md: a joke, a toy calculator, a gamified budgeting app, a casual student side project, playful mascots, meme-adjacent copy, and opaque "magic number" presentation.

**Key Characteristics:**

- Native iOS confidence: SF Pro, Dynamic Type, semantic colors, standard controls.
- Inspectable density: totals are prominent, but the supporting rows stay close.
- Restrained color: one blue action voice, semantic status colors, no decorative saturation.
- Tonal depth: surfaces separate through adaptive layers first, shadows second.
- Transparent state: sync, errors, disabled states, and calculations are visible.

## 2. Colors

The palette is a restrained ledger palette: deep ink and paper neutrals, one workday blue accent, and semantic colors reserved for real state.

### Primary

- **Workday Blue**: The primary action and selection color. Use for main CTAs, active month controls, focused fields, current dates, and informative status.
- **Ledger Cyan**: The public web highlight and brand glow. Use sparingly on marketing surfaces, app icons, logo gradients, and ambient hero lighting; do not promote it to a second app action color.

### Secondary

- **Signal Green**: Success, completed sync, positive employment or earnings indicators.
- **Payroll Amber**: Warnings, conflicts, pending attention, and payroll states that require review.
- **Error Red**: Errors, destructive actions, failed validation, and negative payroll adjustments.

### Neutral

- **Ink Navy**: The dark app base. It gives the product its assertive posture and keeps pay data legible in low light.
- **Night Surface**: Primary dark cards, sheets, and raised panels.
- **Night Surface Raised**: Secondary dark containers, form fields, and nested detail blocks.
- **Paper Mist**: The light app base.
- **Paper Surface**: Primary light cards and controls. Treat it as a semantic token, not a raw white to sprinkle through new code.
- **Paper Surface Muted**: Secondary light containers and quiet grouped rows.
- **Text Primary / Secondary / Muted**: Strict hierarchy for reading speed. Do not use opacity as a substitute for the named text tokens.
- **Border / Border Subtle**: One-pixel structural separation for fields, cards, warning banners, and secondary surfaces.

### Named Rules

**The One Action Voice Rule.** Workday Blue owns primary actions, active state, and focus. Do not add a competing accent because a screen feels plain.

**The Status Earns Color Rule.** Signal Green, Payroll Amber, and Error Red appear only when the state is real. Never use status colors as decoration.

**The No Hidden Math Rule.** Color can call attention to a total, but it cannot replace the row-level explanation of supplements, breaks, tax, and adjustments.

## 3. Typography

**Display Font:** SF Pro via SwiftUI system fonts, with Apple system fallbacks.
**Body Font:** SF Pro via SwiftUI system fonts, with Apple system fallbacks.
**Label/Mono Font:** SF Mono for codes, chart labels, time chips, compact technical values, and security flows.

**Character:** Typography is native, direct, and numeric. Large amounts can be bold and rounded when the user needs a single value, but labels, controls, rows, and descriptions stay plain.

### Hierarchy

- **Display** (700, 56pt, 1.0): Large currency displays and dashboard stat values. Use only where the number is the point of the screen.
- **Headline** (700, 28pt, 1.15): Screen titles, onboarding headings, and major task starts.
- **Title** (700, 22pt, 1.2): Card headers, section titles, and dense review blocks.
- **Body** (400, 16pt, 1.35): Default app reading text, field content, and explanatory rows. Keep prose near 65-75 characters on web surfaces.
- **Label** (500, 14pt, 1.25): Form labels, secondary emphasis, button text, badges, and action links.
- **Mono** (500, 13pt, 1.25): MFA codes, time chips, chart labels, and precise system values.

### Named Rules

**The Native Type Rule.** Use SF Pro and Dynamic Type in the app. Do not introduce display fonts into UI labels, buttons, forms, or data.

**The Numbers Need Room Rule.** Pay amounts can be large, but every oversized number needs nearby context, period, currency, and calculation access.

## 4. Elevation

Tidex uses tonal layering first and adaptive shadows second. In light mode, subtle blue-gray shadows separate cards from Paper Mist. In dark mode, a top-edge rim and restrained shadow define surfaces without turning the UI into glass. Marketing surfaces may use a cyan radial atmosphere, but app surfaces should rely on semantic layers.

### Shadow Vocabulary

- **Subtle** (`radius 4pt, y 1pt, light opacity 0.06; dark radius 3pt, y 1pt, opacity 0.15`): Nested cards and small grouped surfaces.
- **Card** (`radius 8pt, y 2pt, light opacity 0.10; dark radius 6pt, y 2pt, opacity 0.30`): Standard shift cards, settings rows, and review panels.
- **Elevated** (`radius 16pt, y 4pt, light opacity 0.15; dark radius 10pt, y 3pt, opacity 0.40`): Sheets, popovers, and overlays.
- **Floating** (`radius 24pt, y 8pt, light opacity 0.20; dark radius 14pt, y 5pt, opacity 0.50`): Floating action surfaces and persistent bottom affordances.
- **Chip** (`radius 3pt, y 1pt, light opacity 0.15; dark radius 2pt, y 1pt, opacity 0.35`): Small badges and status chips.

### Named Rules

**The Tonal First Rule.** Try a semantic surface layer before adding shadow. Shadow is for separation, not decoration.

**The No Decorative Glass Rule.** Blur and glass treatments must support an input or floating control state. Decorative glass cards are prohibited.

## 5. Components

### Buttons

Buttons should feel confident and native. The main action is a full-width pill when it completes a flow, and a compact icon or text button when it acts inside a toolbar.

- **Shape:** Full primary actions use a pill radius (32pt) and 48pt height. Compact sheet actions can use large rounded rectangles (12-14pt).
- **Primary:** Workday Blue or Brand Primary background, text on brand, SF Pro semibold label. Disabled uses the same color at reduced strength, never a new gray meaning.
- **Hover / Focus:** iOS press feedback scales to 0.97 for 100 ms when motion is allowed. Web buttons use color transitions and focus-visible rings.
- **Secondary / Ghost:** Use text color or subdued surface backgrounds. Ghost actions must still show tappable affordance through icon, label, placement, or focus ring.

### Chips

Chips are compact state markers, not decorations.

- **Style:** Rounded small to medium corners (8-10pt), tinted surface, semibold 12-14pt labels.
- **State:** Selected or active chips may use Workday Blue at low opacity with blue text. Warning chips use Payroll Amber tint and must include label or icon context.

### Cards / Containers

Cards should read as ledger sections: grouped, calm, and close to the calculation they explain.

- **Corner Style:** Standard cards use 24pt for primary shift cards, 16pt for calculation cards, 12pt for small panels, and 8-10pt for fields and chips.
- **Background:** Primary cards use Night Surface or Paper Surface. Detail cards use Night Surface Raised or Paper Surface Muted at reduced emphasis.
- **Shadow Strategy:** Use the Elevation vocabulary. Avoid stacking shadows on nested cards.
- **Border:** Use 1pt semantic borders for fields, warning banners, and focused states.
- **Internal Padding:** 16pt for dense calculation cards, 24pt for primary cards, 8-12pt for nested detail rows.

### Inputs / Fields

Inputs are quiet, explicit, and error-aware.

- **Style:** Secondary surface background, 10pt radius, 16pt horizontal padding, 12pt vertical padding, 1pt border.
- **Focus:** Border shifts to Workday Blue or Brand Primary. Chat composer focus may add a subtle blue tint and shadow.
- **Error / Disabled:** Error border and caption use Error Red. Disabled fields reduce interaction and contrast, but labels remain readable.

### Navigation

Navigation should stay native and predictable.

- **Style:** Inline navigation titles, system tab behavior, toolbar actions, and user menu placement. Avoid custom navigation patterns unless a native pattern cannot handle the workflow.
- **Typography:** Use system headline or title styles, not marketing display sizes.
- **States:** Current tabs and toolbar actions use Workday Blue. Conflicts or payroll warnings can replace the accent only when the status is the point.
- **Mobile Treatment:** iOS is the primary surface. Respect safe areas, one-handed reach, Dynamic Type, and standard sheet behavior.

### Chat Composer

The chat composer is a signature control because it combines input, state, and action.

- **Shape:** 24pt continuous rounded rectangle with a 38pt circular send button.
- **Default:** Blue tint at low opacity, semantic border, body text, up to seven lines.
- **Focus:** Stronger blue tint, blue border, soft blue shadow, and optional horizontal padding change.
- **Motion:** 150 ms state transitions, disabled when Reduce Motion is enabled.

## 6. Do's and Don'ts

### Do:

- **Do** use semantic color tokens such as Workday Blue, Ink Navy, Night Surface, Paper Mist, Signal Green, Payroll Amber, and Error Red.
- **Do** keep pay totals inspectable with nearby row-level detail for supplements, overtime, breaks, tax, and manual adjustments.
- **Do** use SF Pro, Dynamic Type, VoiceOver labels, and 44pt minimum touch targets for tappable controls.
- **Do** use status colors only when the state is real and named in text, iconography, or layout.
- **Do** make loading, sync, validation, subscription limits, and disabled states explicit.
- **Do** use tonal layers before shadows, and keep shadows restrained enough that the ledger still feels calm.

### Don't:

- **Don't** make Tidex look like a joke, a toy calculator, a gamified budgeting app, or a casual student side project.
- **Don't** use playful mascots, meme-adjacent copy, novelty illustration, exaggerated celebration, or decorative complexity that weakens trust.
- **Don't** present opaque "magic number" totals without a path to inspect the calculation.
- **Don't** introduce competing accent colors because a screen feels visually quiet.
- **Don't** use gradient text, colored side-stripe borders, generic glass cards, or identical icon-card grids.
- **Don't** rely on color alone for charts, warnings, payroll differences, conflicts, or sync state.
- **Don't** use display fonts in app UI labels, buttons, data rows, settings, or forms.
