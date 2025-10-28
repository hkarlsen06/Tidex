# Tidex TODO

## Payroll Snapshot Enhancements

### 1. Audit Trail UI
**Priority**: Medium
**Complexity**: Low-Medium

Show users when shifts are using historical (snapshotted) rates vs current settings.

**Implementation ideas:**
- Add a badge/indicator on shift cards showing "Historical rates" vs "Current rates"
- In shift details view, show both snapshot and current rates side-by-side
- Add a tooltip explaining why rates might differ

**UI mockup location:** TBD

**Files to modify:**
- `components/app/ShiftCard.tsx` - Add snapshot indicator
- `app/[locale]/(app)/shifts/[id]/page.tsx` - Show detailed comparison
- Add translation keys to dictionaries

---

### 2. Bulk Re-Snapshot Feature
**Priority**: Low-Medium
**Complexity**: Medium

Allow users to update old shifts to use current wage/supplement settings instead of historical snapshots.

**Use cases:**
- User realizes historical snapshots are wrong
- User wants to retroactively apply new tariff rates
- Testing/debugging purposes

**Implementation approach:**

**Option A: Per-shift**
- Add "Use current rates" button in shift edit modal
- Clears `hourly_wage_snapshot` and `supplement_rules_snapshot`
- Shift will recalculate using current settings

**Option B: Bulk update**
- Settings page: "Update all shifts from [date range] to current rates"
- Shows preview of changes before confirming
- Runs database update to NULL out snapshots

**Files to create/modify:**
- New action: `app/[locale]/(app)/shifts/_actions/updateShiftSnapshots.ts`
- UI component: Settings page or shifts page bulk action menu
- Add confirmation modal with change preview

**Security considerations:**
- Ensure user can only update their own shifts
- Add rate limiting to prevent abuse
- Log bulk updates for audit trail

---

### 3. Snapshot Diff Viewer
**Priority**: Low
**Complexity**: Medium-High

Visual comparison tool showing what changed between snapshot and current settings.

**Features:**
- Side-by-side comparison table
- Highlight differences (wage changes, supplement rate changes)
- Show impact on total earnings for each shift
- Filter shifts by "has differences" vs "matches current"

**Implementation:**
- Create utility function to compare snapshots with current settings
- Build comparison UI component
- Add export feature for affected shifts

**Files to create:**
- `lib/payroll/compareSnapshots.ts` - Comparison logic
- `components/app/SnapshotDiffViewer.tsx` - UI component
- `app/[locale]/(app)/shifts/snapshot-audit/page.tsx` - Dedicated page

---

## Other Features

### 4. Export Payroll Report with Snapshot Information
**Priority**: Low
**Complexity**: Low

Include snapshot metadata in PDF/CSV exports to show which rates were used.

**Files to modify:**
- `app/api/settings/data/export/route.ts`
- PDF generation logic

---

## Notes

- All snapshot-related features should maintain backward compatibility with shifts that have NULL snapshots
- Consider adding analytics to track how often users interact with snapshot features
- Document all changes in the payroll docs (`marketing/app/docs/payroll/page.tsx`)
