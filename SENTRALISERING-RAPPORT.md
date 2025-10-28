# Rapport: Sentralisering av kode i Tidex

**Dato:** 2025-10-28
**Analysert av:** Claude Code
**Omfang:** Fullstendig kodebase-gjennomgang

---

## Sammendrag

Analysen identifiserte **200+ linjer med duplisert kode** fordelt på 5 hovedkategorier med høy prioritet. Implementering av forslagene vil:

- ✅ Redusere vedlikeholdskostnader ved å eliminere duplisering
- ✅ Forbedre kodekonsistens og redusere feil
- ✅ Gjøre kodebasen mer skalerbar
- ✅ Minimal påvirkning på ytelse (kun forbedringer)

---

## 1. Valideringsfunksjoner (HØY PRIORITET)

### Problem
Tre valideringsfunksjoner er duplisert i minst 4 forskjellige filer:

**Dupliserte funksjoner:**
- `isISODate()` - Validerer ISO-datoformat (YYYY-MM-DD)
- `isHHMM()` - Validerer tidsformat (HH:MM)
- `shiftTypeFromISODate()` - Beregner skifttype fra dato

**Lokasjon av duplikater:**
- [app/[locale]/(app)/shifts/add/actions.ts](app/[locale]/(app)/shifts/add/actions.ts) (linjer 19, 23, 27)
- [app/[locale]/(app)/shifts/_actions/moveSeriesShift.ts](app/[locale]/(app)/shifts/_actions/moveSeriesShift.ts) (linjer 20, 24, 28)
- [app/[locale]/(app)/shifts/_actions/copyShifts.ts](app/[locale]/(app)/shifts/_actions/copyShifts.ts) (linjer 18, 22)
- [app/[locale]/(app)/shifts/_actions/updateShift.ts](app/[locale]/(app)/shifts/_actions/updateShift.ts) (linjer 17, 21, 25)
- Flere andre action-filer

**Eksempel på duplisering:**
```typescript
// Gjentatt i 4+ filer
function isISODate(input: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(input);
}

function isHHMM(input: string): boolean {
  return /^\d{2}:\d{2}$/.test(input);
}

function shiftTypeFromISODate(iso: string): 0 | 1 | 2 {
  const d = new Date(`${iso}T00:00:00Z`);
  const weekday = d.getUTCDay();
  return weekday === 6 ? 1 : weekday === 0 ? 2 : 0;
}
```

### Løsning
Opprett ny fil: `lib/validation/shift-validators.ts`

```typescript
/**
 * Validates ISO date format (YYYY-MM-DD)
 */
export function isISODate(input: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(input);
}

/**
 * Validates time format (HH:MM)
 */
export function isHHMM(input: string): boolean {
  return /^\d{2}:\d{2}$/.test(input);
}

/**
 * Determines shift type from ISO date
 * @returns 0 (weekday), 1 (Saturday), 2 (Sunday)
 */
export function shiftTypeFromISODate(iso: string): 0 | 1 | 2 {
  const d = new Date(`${iso}T00:00:00Z`);
  const weekday = d.getUTCDay();
  return weekday === 6 ? 1 : weekday === 0 ? 2 : 0;
}
```

**Bruk:**
```typescript
import { isISODate, isHHMM, shiftTypeFromISODate } from "@/lib/validation/shift-validators";

// I server actions
if (!isISODate(date)) {
  throw new Error("Ugyldig dato");
}
```

### Forventet effekt
- **Linjer redusert:** ~60 linjer
- **Filer påvirket:** 6+ action-filer
- **Vedlikehold:** Endringer i valideringslogikk gjøres kun ett sted
- **Ytelse:** Ingen endring (samme logikk)
- **Risiko:** Lav - enkel refaktorering

---

## 2. Revalidering av cache (HØY PRIORITET)

### Problem
Samme mønster for cache-revalidering er copy-pastet i **11+ server actions**:

```typescript
// Gjentatt i alle shift-actions
revalidatePath("/[locale]/shifts", "page");
revalidatePath("/[locale]", "page");
revalidatePath("/[locale]/stats", "page");
```

**Filer med duplisering:**
- Alle filer i [app/[locale]/(app)/shifts/_actions/](app/[locale]/(app)/shifts/_actions/)
- [app/[locale]/(app)/settings/_actions/bulkClearSnapshots.ts](app/[locale]/(app)/settings/_actions/bulkClearSnapshots.ts)
- Andre action-filer som påvirker skiftdata

### Løsning
Opprett ny fil: `lib/revalidation/paths.ts`

```typescript
import { revalidatePath } from "next/cache";

/**
 * Revalidates all pages that display shift data
 * Call this after any shift modification
 */
export function revalidateShiftData() {
  revalidatePath("/[locale]/shifts", "page");
  revalidatePath("/[locale]", "page");
  revalidatePath("/[locale]/stats", "page");
}
```

**Bruk:**
```typescript
import { revalidateShiftData } from "@/lib/revalidation/paths";

// I server actions
export async function updateShift(id: string, data: ShiftData) {
  // ... update logic
  revalidateShiftData();
  return { success: true };
}
```

### Forventet effekt
- **Linjer redusert:** ~33 linjer (3 linjer × 11 filer)
- **Filer påvirket:** 11+ action-filer
- **Vedlikehold:** Enkelt å legge til nye paths for revalidering
- **Ytelse:** Ingen endring
- **Risiko:** Veldig lav

---

## 3. Cache-invalidering + Revalidering (HØY PRIORITET)

### Problem
Et enda mer komplett mønster gjentas i de fleste actions:

```typescript
// Gjentatt i 11+ filer
invalidateUserCache(user.id);
revalidatePath("/[locale]/shifts", "page");
revalidatePath("/[locale]", "page");
revalidatePath("/[locale]/stats", "page");
```

### Løsning
Utvid `lib/revalidation/paths.ts`:

```typescript
import { revalidatePath } from "next/cache";
import { invalidateUserCache } from "@/data-access/cache";

/**
 * Invalidates user cache and revalidates all shift-related pages
 * Use this after any data modification for a user
 */
export function invalidateAndRevalidate(userId: string) {
  invalidateUserCache(userId);
  revalidatePath("/[locale]/shifts", "page");
  revalidatePath("/[locale]", "page");
  revalidatePath("/[locale]/stats", "page");
}
```

**Bruk:**
```typescript
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";

export async function deleteShift(id: string) {
  const user = await verifySession();
  // ... delete logic
  invalidateAndRevalidate(user.id);
  return { success: true };
}
```

### Forventet effekt
- **Linjer redusert:** ~44 linjer (4 linjer × 11 filer)
- **Filer påvirket:** 11+ action-filer
- **Vedlikehold:** Konsistent cache-håndtering på tvers av actions
- **Ytelse:** Ingen endring
- **Risiko:** Lav

---

## 4. Snapshot-forberedelse (MEDIUM PRIORITET)

### Problem
Logikk for å hente innstillinger og forberede snapshots er duplisert i 6+ filer:

```typescript
// Gjentatt mønster
const { data: settings, error: settingsError } = await supabase
  .from("user_settings")
  .select("use_preset, current_wage_level, custom_wage, custom_supplements")
  .eq("user_id", user.id)
  .single();

if (settingsError || !settings) {
  throw new Error("Kunne ikke hente innstillinger");
}

const snapshots = prepareShiftSnapshots(settings);
```

**Filer:**
- [app/[locale]/(app)/shifts/_actions/clearShiftSnapshots.ts](app/[locale]/(app)/shifts/_actions/clearShiftSnapshots.ts) (linjer 14-27)
- [app/[locale]/(app)/settings/_actions/bulkClearSnapshots.ts](app/[locale]/(app)/settings/_actions/bulkClearSnapshots.ts) (linjer 14-30)
- [app/[locale]/(app)/shifts/_actions/copyShifts.ts](app/[locale]/(app)/shifts/_actions/copyShifts.ts) (linjer 134-135)
- Flere andre

### Løsning
Opprett ny DAL-funksjon: `data-access/snapshots.ts`

```typescript
import { verifySession } from "./auth";
import { getUserSettings } from "./settings";
import { prepareShiftSnapshots } from "@/lib/payroll/prepareShiftSnapshots";
import type { ShiftSnapshots } from "@/types/payroll";

/**
 * Get current wage/supplement snapshots for the authenticated user
 * Based on their current settings
 */
export async function getCurrentSnapshots(): Promise<ShiftSnapshots> {
  await verifySession(); // Ensures auth
  const settings = await getUserSettings();
  return prepareShiftSnapshots(settings);
}
```

**Bruk:**
```typescript
import { getCurrentSnapshots } from "@/data-access/snapshots";

export async function createShift(data: ShiftData) {
  const snapshots = await getCurrentSnapshots();
  // ... use snapshots
}
```

### Forventet effekt
- **Linjer redusert:** ~70 linjer (10-15 linjer × 6 filer)
- **Filer påvirket:** 6+ action-filer
- **Vedlikehold:** Følger DAL-mønsteret, letter testing
- **Ytelse:** Mulig forbedring via caching i DAL
- **Risiko:** Lav-medium (krever testing av alle actions)

---

## 5. Abonnement/tier-sjekking (HØY PRIORITET)

### Problem
Logikk for å sjekke om brukere på gratis plan kan legge til skift i nye måneder er duplisert:

```typescript
// Gjentatt i 3+ filer
const { subscription, profile } = await getUserSubscriptionData();

if (!hasProAccess(subscription, profile)) {
  const { data: existingShifts } = await supabase
    .from("user_shifts")
    .select("shift_date")
    .eq("user_id", user.id);

  const existingMonths = existingShifts
    ? getUniqueShiftMonths(existingShifts)
    : new Set<string>();

  const targetMonth = startDate.slice(0, 7);
  if (existingMonths.size >= 3 && !existingMonths.has(targetMonth)) {
    throw new Error("Gratis plan er begrenset til 3 måneder...");
  }
}
```

**Filer:**
- [app/[locale]/(app)/shifts/_actions/copyShifts.ts](app/[locale]/(app)/shifts/_actions/copyShifts.ts) (linjer 106-131)
- [app/[locale]/(app)/shifts/add/actions.ts](app/[locale]/(app)/shifts/add/actions.ts)
- Andre shift-opprettings-actions

### Løsning
**Bruk eksisterende utility!** Filen [app/[locale]/(app)/shifts/add/_checks/checkShiftLimit.ts](app/[locale]/(app)/shifts/add/_checks/checkShiftLimit.ts) finnes allerede.

**Refaktorer til:**
```typescript
import { checkShiftLimit } from "@/app/[locale]/(app)/shifts/add/_checks/checkShiftLimit";

export async function copyShifts(...) {
  // ... other validation

  const targetMonth = startDate.slice(0, 7);
  const limitCheck = await checkShiftLimit(targetMonth);

  if (!limitCheck.allowed) {
    throw new Error(limitCheck.reason);
  }

  // ... proceed with copy
}
```

**Alternativt:** Flytt `checkShiftLimit` til `lib/subscription/` for bedre synlighet.

### Forventet effekt
- **Linjer redusert:** ~60 linjer (20 linjer × 3 filer)
- **Filer påvirket:** 3+ action-filer
- **Vedlikehold:** Endringer i tier-logikk gjøres kun ett sted
- **Ytelse:** Ingen endring
- **Risiko:** Lav (funksjonen eksisterer allerede)

---

## 6. Feilmeldinger (MEDIUM PRIORITET)

### Problem
Hardkodede norske feilmeldinger er duplisert på tvers av actions:

- "Ugyldig dato" - 3+ filer
- "Ugyldig tid" - 3+ filer
- "Fant ikke skiftet" - 2+ filer
- "Ugyldig skift-ID" - flere filer

### Løsning
Opprett konstantfil: `lib/errors/messages.ts`

```typescript
/**
 * Standard error messages for server actions
 * TODO: Consider i18n for multi-language error messages
 */
export const ERRORS = {
  INVALID_DATE: "Ugyldig dato",
  INVALID_TIME: "Ugyldig tid",
  INVALID_SHIFT_ID: "Ugyldig skift-ID",
  SHIFT_NOT_FOUND: "Fant ikke skiftet",
  SERIES_NOT_FOUND: "Fant ikke serien",
  SETTINGS_NOT_FOUND: "Kunne ikke hente innstillinger",
  UNAUTHORIZED: "Ikke autorisert",
} as const;

export type ErrorMessage = typeof ERRORS[keyof typeof ERRORS];
```

**Bruk:**
```typescript
import { ERRORS } from "@/lib/errors/messages";

if (!isISODate(date)) {
  throw new Error(ERRORS.INVALID_DATE);
}
```

### Forventet effekt
- **Linjer redusert:** ~15-20 linjer
- **Filer påvirket:** 10+ action-filer
- **Vedlikehold:** Konsistente feilmeldinger, letter fremtidig i18n
- **Ytelse:** Ingen endring
- **Risiko:** Veldig lav

---

## 7. Ting som allerede er bra sentralisert ✅

Følgende områder er **allerede godt organisert** og trenger ikke endringer:

### ✅ Dato/tid-utilities
- [lib/date-utils.ts](lib/date-utils.ts) - Server-side datooperasjoner
- [lib/time-utils.ts](lib/time-utils.ts) - Tidsstreng-behandling
- [components/calendar/calendar.utils.ts](components/calendar/calendar.utils.ts) - Kalender-spesifikk logikk

### ✅ Formatering
- [lib/formatters.ts](lib/formatters.ts) - Tall, valuta, timer formatering

### ✅ Component re-exports
Komponentene bruker korrekt pattern:
- Defineres i spesialiserte mapper (`components/calendar/`, `components/series/`)
- Re-eksporteres gjennom `components/app/` for konsistente imports
- Eksempel: [components/app/ShiftsCalendar.tsx](components/app/ShiftsCalendar.tsx) → re-eksporterer fra `../calendar/`

### ✅ Connection() calls
Alle 9 beskyttede sider kaller korrekt `connection()` fra "next/server" for å opt-e ut av prerendering.

---

## Implementeringsplan

### Fase 1: Quick Wins (1-2 timer)
1. ✅ Opprett `lib/validation/shift-validators.ts`
2. ✅ Opprett `lib/revalidation/paths.ts`
3. ✅ Opprett `lib/errors/messages.ts`
4. ✅ Erstatt duplisert kode i 5-10 filer

### Fase 2: Strukturelle forbedringer (2-3 timer)
5. ✅ Opprett `data-access/snapshots.ts`
6. ✅ Refaktorer snapshot-logikk i 6+ filer
7. ✅ Erstatt inline tier-sjekker med `checkShiftLimit`

### Fase 3: Testing & dokumentasjon (1 time)
8. ✅ Test alle påvirkede server actions
9. ✅ Oppdater CLAUDE.md med nye utilities
10. ✅ Slett denne rapporten når implementert

---

## Estimert total effekt

### Kvantitative gevinster
- **Linjer fjernet:** ~240 linjer duplisert kode
- **Funksjoner sentralisert:** 7 funksjoner
- **Filer påvirket:** 20+ filer forbedres
- **Vedlikeholdskostnad:** -40% for valideringslogikk

### Kvalitative gevinster
- ✅ **Konsistens:** Samme validering/revalidering overalt
- ✅ **Lesbarhet:** Tydeligere intent i action-filer
- ✅ **Testbarhet:** Utilities kan testes isolert
- ✅ **Skalerbarhet:** Nye actions kan gjenbruke utilities
- ✅ **Feilreduksjon:** Mindre copy-paste fører til færre bugs

### Ytelsespåvirkning
- **Server actions:** Ingen merkbar endring (samme logikk)
- **Build time:** Ingen endring
- **Bundle size:** Marginalt mindre (~1-2 KB)
- **Runtime:** Mulig forbedring fra DAL-caching av snapshots

### Risiko
- **Lav risiko** for Fase 1 (pure utilities)
- **Medium risiko** for Fase 2 (krever grundig testing)
- **Mitigering:** Omfattende testing av alle action-flows

---

## Konklusjon

Kodebasen har moderate mengder duplisering, hovedsakelig i **server actions**. Dette er typisk for rask utvikling, men skaper nå vedlikeholdsutfordringer.

**Anbefalinger:**
1. Implementer Fase 1 umiddelbart (høy verdi, lav risiko)
2. Vurder Fase 2 når tid tillater testing
3. Behold eksisterende god struktur for dato/formatering
4. Oppdater CLAUDE.md med nye utilities for fremtidig Claude-assistanse

**Vedlikeholdsgevinst:** Estimert **30-40% reduksjon** i tid brukt på endringer i validering, revalidering og feilhåndtering.
