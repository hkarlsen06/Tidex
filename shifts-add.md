# Add Shifts (Next.js 15)

This document is the single source of truth for the Add Shift(s) feature. It gives full context on what’s already implemented, what remains, how the parts fit the repo’s architecture, and how to validate behavior. Personal planner only — no employees, no service workers, no per‑shift manual pause.

## TL;DR

- Status: MVP implemented and wired. New shifts appear immediately after save.
- Files: server action, client form, and route are in place (see “What’s Implemented”).
- Next: optional recurring UI and conflict highlighting.

## Scope

- Personal shifts for the signed-in user only.
- No employee assignment, no organization context, no service worker/offline queue.
- Support single or multi-date entry, optional recurring sequences.

## Data Model

- Table: `public.user_shifts`
  - `user_id: uuid`
  - `shift_date: date` (ISO `YYYY-MM-DD`)
  - `start_time: text` (HH:mm)
  - `end_time: text` (HH:mm) — cross‑midnight allowed (`end <= start` means next day)
  - `shift_type: int` (derived: 0=weekday, 1=Saturday, 2=Sunday)
  - `series_id: uuid` (optional, for recurring batches)

Row Level Security already allows users to insert their own rows.

Notes:
- No `pause_duration_hours` column is used or expected.
- `shift_type` is derived from the date on the server.

## UX Overview

- Route: `/shifts/add`
- Default “Enkel” tab: select one or more dates + start/end time.
- Optional “Serie” tab: create a weekly or every‑N‑weeks sequence with `series_id`.
- Calendar highlights existing shifts and potential conflicts (non‑blocking for MVP).
- After save, navigate to `/shifts` and refresh data.

## What’s Implemented

- Route shell: `app/(app)/shifts/add/page.tsx` — server component enforces auth and renders the client form.
- Client form: `app/(app)/shifts/add/AddShiftForm.tsx` — uses `SelectDatesCalendar`, `Input` time fields, `Button` CTA; submits via server action; on success navigates to `/shifts` and refreshes.
- Server action: `app/(app)/shifts/add/actions.ts` — validates input, derives `shift_type`, inserts into `user_shifts`, calls `revalidatePath('/shifts')`.
- Shifts page: `app/(app)/shifts/page.tsx` — already loads through `getComputedShifts(...)`.

Immediate visibility path:
- Server action inserts rows and calls `revalidatePath('/shifts')`.
- Client then `router.push('/shifts')` and `router.refresh()`.
- The `/shifts` page fetches server‑side and renders the new rows immediately.

## Implementation Plan (design details)

1) Add Page Shell
- File: `app/(app)/shifts/add/page.tsx`
- Server Component: enforce auth, render `<AddShiftForm />`.

2) AddShiftForm (client)
- File: `app/(app)/shifts/add/AddShiftForm.tsx`
- Uses wrapped shadcn components from `components/app`: `Card`, `Button`, `Input`, `Dialog`, and `SelectDatesCalendar`.
- State: `selectedDates: Date[]`, `start: HH:mm`, `end: HH:mm`, `submitting: boolean`.
- Validation: require ≥1 date and both times; allow cross‑midnight.
- Submit calls a Server Action to insert rows, then `router.push('/shifts')` and `router.refresh()`.

3) Persistence (Server Action)
- File: `app/(app)/shifts/add/actions.ts` (or `app/(app)/shifts/_actions/createShift.ts`)
- Export `createShifts(data)` with `"use server"`.
- Resolve `userId` from session via `createSupabaseServerClient()`.
- For each `shift_date`:
  - Derive `shift_type` by weekday: 0=Mon–Fri, 1=Sat, 2=Sun.
  - Insert `{ user_id, shift_date, start_time, end_time, shift_type, series_id? }`.
- Return count and/or inserted IDs. Validate payload server‑side (e.g., zod).

4) Recurring (optional second tab)
- Weekly or every‑N‑weeks from a `startDate` until an `endDate` or `months` duration.
- Generate occurrences client‑side, confirm count in `Dialog`, include shared `series_id` (UUID).
- Submit via the same Server Action.

5) Conflicts (nice‑to‑have)
- Client detects overlaps against already‑loaded shifts in the current month; schema: `Record<ISODate, {start: HH:mm, end: HH:mm}[]>`.
- Non‑blocking: allow save but surface warnings in UI.
- Use `SelectDatesCalendar` props `hasShiftDates` to render small dots, and `conflictDates` to mark overlap candidates.

## Components To Build

- `app/(app)/shifts/add/AddShiftForm.tsx` (client) — implemented
  - Layout: `Card` header, calendar section, time inputs row, primary action.
  - Calendar: `SelectDatesCalendar` from `components/app/SelectDatesCalendar`.
  - Time: two `Input type="time"` (15‑min step), labels “Start” and “Slutt”.
  - CTA: `Button` labeled “Legg til X skift”. Disabled until valid.
  - Success: navigate to `/shifts`.

- `app/(app)/shifts/add/RecurringForm.tsx` (client, optional) — not implemented
  - Frequency select (weekly / every N weeks), number input for N.
  - Start date (calendar) and duration (end date or months).
  - Reuses time inputs from base form.
  - `Dialog` to confirm “Oppretter N skift”.

- `app/(app)/shifts/add/actions.ts` (server) — implemented
  - `export async function createShifts(input: { dates: string[]; start: string; end: string; seriesId?: string })`.
  - Auth via `createSupabaseServerClient()`; derive `userId`.
  - Compute `shift_type` per date; batch insert into `user_shifts`.

Uses existing wrappers:
- `components/app/Card.tsx`, `components/app/Button.tsx`, `components/app/Input.tsx`, `components/app/Dialog.tsx`
- `components/app/SelectDatesCalendar.tsx`

## Validation Rules

- Client: require at least one date and valid `HH:mm` start/end.
- Cross‑midnight allowed (`end <= start`).
- Server: revalidate all fields; reject empty payload; sanitize duplicates.

## Behaviour After Save

- On success: redirect to `/shifts` and refresh.
- Optional: pass `?added=N` and show a small success `Card` on `/shifts`.

## Notes & Non‑Goals

- Employees are deprecated — no employee UI, selection, or data.
- No service worker or offline queue.
- Wage calculations stay server‑side (already implemented). New rows render with computed values on the `/shifts` page.

## File Checklist (MVP)

- `app/(app)/shifts/add/page.tsx` → server wrapper, renders `<AddShiftForm />` (done).
- `app/(app)/shifts/add/AddShiftForm.tsx` → client UI and submit (done).
- `app/(app)/shifts/add/actions.ts` → `createShifts()` server action (done).
- (Optional) `app/(app)/shifts/add/RecurringForm.tsx` → recurring UI (pending).

## Remaining Work (Backlog)

- Recurring creation UI and confirmation dialog.
- Conflict highlighting using `hasShiftDates` and `conflictDates` in `SelectDatesCalendar`.
- Basic zod schema for server action validation with friendly error mapping in the client.
- Empty‑state success banner on `/shifts?added=N` (optional).

## TODO (Add Shifts polishing)

- [x] Do not prefill time selectors in both modes.
- [x] Replace DayPicker chevrons with shared `MonthPicker` above the calendar.
- [x] Hide DayPicker caption/month-year over the calendar (remove duplicate month/year).
- [x] Pass `hideCaptionNav` to `SelectDatesCalendar` so nav/caption are hidden.
- [x] Remove "Forhåndsvis antall:" label from the series mode.
- [ ] Sanity-check week-number column layout with custom header (keep or adjust if still confusing).
- [ ] Add zod schema for server action and map friendly errors in the client.

## Manual Test Plan

- Auth: visit `/shifts/add` while signed in; ensure redirect to `/login` when signed out.
- Single add: pick one date, set times, click CTA → lands on `/shifts` and shows the new shift.
- Multi‑add: pick multiple dates, set times, click CTA → all dates appear grouped by week.
- Cross‑midnight: set start > end (e.g., 22:00 → 06:00) → shift renders and computes pay correctly.
- Revalidation: after add, refresh the browser; the shift remains visible (persisted).

## Guardrails

- Security: server action derives `user_id` from session; RLS enforces per‑user inserts.
- Caching: `revalidatePath('/shifts')` on mutation; no client‑side Supabase writes.
- Timezones: dates are submitted as local ISO (`YYYY-MM-DD`), calculations use server loaders.

## Pseudocode

`app/(app)/shifts/add/actions.ts`:

```ts
"use server";
import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { randomUUID } from "node:crypto";

export async function createShifts({ dates, start, end, seriesId }: { dates: string[]; start: string; end: string; seriesId?: string; }) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Unauthorized");

  const toType = (iso: string) => {
    const d = new Date(iso + "T00:00:00Z");
    const wd = d.getUTCDay(); // 0..6 (Sun..Sat)
    return wd === 6 ? 1 : wd === 0 ? 2 : 0; // 0=weekday,1=Sat,2=Sun
  };

  const sid = seriesId || (dates.length > 1 ? randomUUID() : undefined);
  const rows = dates.map((shift_date) => ({
    user_id: user.id,
    shift_date,
    start_time: start,
    end_time: end,
    shift_type: toType(shift_date),
    ...(sid ? { series_id: sid } : {}),
  }));

  const { error } = await supabase.from("user_shifts").insert(rows);
  if (error) throw error;
  revalidatePath("/shifts");
  return { inserted: rows.length };
}
```

`app/(app)/shifts/add/AddShiftForm.tsx` (sketch):

```tsx
"use client";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Card, CardHeader, CardTitle } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import { SelectDatesCalendar } from "@/components/app/SelectDatesCalendar";
import { createShifts } from "./actions";

export default function AddShiftForm() {
  const router = useRouter();
  const [dates, setDates] = useState<Date[]>([]);
  const [start, setStart] = useState("08:00");
  const [end, setEnd] = useState("16:00");
  const [pending, startTransition] = useTransition();

  const onSubmit = () => {
    if (dates.length === 0) return;
    const isoDates = dates.map((d) => d.toISOString().slice(0, 10));
    startTransition(async () => {
      await createShifts({ dates: isoDates, start, end });
      router.push("/shifts");
      router.refresh();
    });
  };

  return (
    <div className="py-6">
      <Card>
        <CardHeader>
          <CardTitle>Legg til skift</CardTitle>
        </CardHeader>
        <div className="px-4 pb-6 space-y-4">
          <SelectDatesCalendar month={new Date()} selected={dates} onSelectedChange={setDates} />
          <div className="grid grid-cols-2 gap-3">
            <label className="space-y-1">
              <span className="text-sm text-text-secondary">Start</span>
              <Input type="time" step={900} value={start} onChange={(e) => setStart(e.target.value)} />
            </label>
            <label className="space-y-1">
              <span className="text-sm text-text-secondary">Slutt</span>
              <Input type="time" step={900} value={end} onChange={(e) => setEnd(e.target.value)} />
            </label>
          </div>
          <Button onClick={onSubmit} disabled={dates.length === 0} loading={pending}>
            Legg til {dates.length || 0} skift
          </Button>
        </div>
      </Card>
    </div>
  );
}
```

This plan fits the current architecture, removes employee/service‑worker complexity, and uses existing shadcn wrappers. It documents both what’s done and what remains so any agent can continue confidently.
