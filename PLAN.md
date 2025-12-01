# Shift Sharing Feature - Implementation Plan

## Overview

Implement a shift sharing feature that allows users to share their shifts with other users. The shared view shows the same UI as `/shifts`, with a dropdown to select whose shifts to view.

## UI Design

### 1. User Menu Addition
- Add "Deling"/"Sharing" menu item above Settings in UserMenu
- Icon: `Share2` from lucide-react
- Route: `/{locale}/sharing`

### 2. Sharing Page Layout (`/sharing`)
**Top section:**
- Dropdown showing users who have shared their shifts with you (no "Mine vakter" - that's what `/shifts` is for)
- Each dropdown item: Profile picture (left) + Name (right)
- "Administrer deling" button (if user has shared) OR "Del vaktene dine" button

**Main section:**
- If no one has shared with you AND you haven't shared: empty state explaining the feature
- If someone has shared with you: **reuse the existing `ShiftsView` component** in read-only mode
- Dropdown defaults to first person who shared with you

**Component Reuse (IMPORTANT):**
The `/sharing` page reuses the **exact same components** as `/shifts`:
- `components/shifts/ShiftsView.tsx` - Main container with view toggle (list/calendar)
- `components/shifts/MonthlyEarningsCalendar.tsx` - Calendar view
- `components/app/ShiftCard.tsx` - Individual shift cards in list view
- `components/shifts/ShiftDetails.tsx` - Shift detail modal (view-only when readOnly)

The only change needed is adding a `readOnly` prop to `ShiftsView` that:
- Hides the "+" add shift button
- Disables edit/delete actions on ShiftCard and ShiftDetails
- Hides copy/move functionality

### 3. Manage Sharing Modal
**Triggered by:** "Administrer deling" / "Del vaktene dine" button

**Content:**
- Header: "Deling" / "Sharing"
- List of users with access to your shifts:
  - Profile picture (left)
  - Name + email/phone (center)
  - Trash icon button (right) - removes access
- "+" button at bottom - expands to:
  - Input field for email/phone
  - Send button
- Empty state: "Du har ikke delt vaktene dine med noen ennå"

## Database Design

### New Table: `shift_shares`

```sql
CREATE TABLE shift_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Prevent duplicate shares
  UNIQUE(owner_id, viewer_id),

  -- Can't share with yourself
  CHECK (owner_id != viewer_id)
);

-- Indexes for efficient queries
CREATE INDEX idx_shift_shares_owner ON shift_shares(owner_id);
CREATE INDEX idx_shift_shares_viewer ON shift_shares(viewer_id);

-- RLS Policies
ALTER TABLE shift_shares ENABLE ROW LEVEL SECURITY;

-- Owner can see who they've shared with
CREATE POLICY "Owner can view own shares"
  ON shift_shares FOR SELECT
  USING (owner_id = auth.uid());

-- Viewer can see shares they have access to
CREATE POLICY "Viewer can view shares they received"
  ON shift_shares FOR SELECT
  USING (viewer_id = auth.uid());

-- Only owner can create shares
CREATE POLICY "Owner can create shares"
  ON shift_shares FOR INSERT
  WITH CHECK (owner_id = auth.uid());

-- Only owner can delete shares
CREATE POLICY "Owner can delete shares"
  ON shift_shares FOR DELETE
  USING (owner_id = auth.uid());
```

### RLS Policy Update: `user_shifts`

Add new policy to allow viewing shared shifts:

```sql
-- Allow viewing shifts shared with you
CREATE POLICY "Users can view shared shifts"
  ON user_shifts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM shift_shares
      WHERE shift_shares.owner_id = user_shifts.user_id
        AND shift_shares.viewer_id = auth.uid()
    )
  );
```

### RLS Policy Update: `wage_snapshots`

Add policy for viewing shared wage data (needed for payroll calculations):

```sql
CREATE POLICY "Users can view shared wage snapshots"
  ON wage_snapshots FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM shift_shares
      WHERE shift_shares.owner_id = wage_snapshots.user_id
        AND shift_shares.viewer_id = auth.uid()
    )
  );
```

### RLS Policy Update: `user_settings`

Add policy for viewing shared settings (needed for display preferences):

```sql
CREATE POLICY "Users can view shared user settings"
  ON user_settings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM shift_shares
      WHERE shift_shares.owner_id = user_settings.user_id
        AND shift_shares.viewer_id = auth.uid()
    )
  );
```

## Backend Implementation

### 1. Data Access Layer (`data-access/sharing.ts`)

```typescript
// Get users who have shared their shifts with current user
export async function getSharedWithMe(): Promise<SharedUser[]>

// Get users the current user has shared their shifts with
export async function getMyShareRecipients(): Promise<ShareRecipient[]>

// Get computed shifts for a shared user (viewer perspective)
export async function getSharedUserShifts(
  ownerId: string,
  options: ShiftLoadOptions
): Promise<ComputedShift[]>
```

### 2. Server Actions (`app/[locale]/(app)/sharing/_actions/`)

```typescript
// sharing.ts
export async function createShare(input: { identifier: string }): Promise<ActionResult>
// - Verifies subscription tier limit (free=1, pro=10, max=20)
// - Looks up user by email or phone in auth.users
// - Creates shift_shares record
// - Returns success/error (generic message to prevent enumeration)

export async function removeShare(input: { recipientId: string }): Promise<ActionResult>
// - Deletes shift_shares record
// - Returns success/error
```

### 3. API Considerations

The existing `/api/shifts` route verifies `session.user.id === userId`. For shared shifts:
- Option A: Add query param `?viewAs=<ownerId>` with share verification
- Option B: Keep API as-is, use DAL directly in server components (preferred)

**Recommendation:** Option B - Use DAL in server components to avoid API complexity.

## Frontend Implementation

### 1. New Components

**`components/sharing/`:**
- `SharingDropdown.tsx` - Dropdown to select whose shifts to view
- `ManageSharingModal.tsx` - Modal to add/remove share recipients
- `ShareRecipientList.tsx` - List of users with access
- `AddShareForm.tsx` - Input form for adding new share

**Updates to existing (add `readOnly` prop):**
- `components/app/UserMenu.tsx` - Add sharing link
- `components/shifts/ShiftsView.tsx` - Add `readOnly` prop, pass down to children
- `components/app/ShiftCard.tsx` - Hide edit/delete/copy actions when readOnly
- `components/shifts/ShiftDetails.tsx` - Hide edit/delete buttons when readOnly
- `components/shifts/MonthlyEarningsCalendar.tsx` - Hide add shift functionality when readOnly (if applicable)

### 2. Page Structure

**`app/[locale]/(app)/sharing/page.tsx`:**
```typescript
export default async function SharingPage({ params, searchParams }) {
  const { user } = await verifySession();
  const viewAs = searchParams?.viewAs; // Whose shifts to view

  // Get list of users who have shared with me
  const sharedWithMe = await getSharedWithMe();

  // Get my share recipients (for manage modal)
  const myRecipients = await getMyShareRecipients();

  // Determine which user's shifts to show (default to first sharer, or none)
  const selectedUserId = viewAs && sharedWithMe.some(u => u.id === viewAs)
    ? viewAs
    : sharedWithMe[0]?.id ?? null;

  // Only fetch shifts if someone has shared with us
  const shifts = selectedUserId
    ? await getSharedUserShifts(selectedUserId, options)
    : [];

  return (
    <I18nProvider>
      <SharingHeader
        sharedWithMe={sharedWithMe}
        selectedUserId={selectedUserId}
        myRecipients={myRecipients}
        hasShared={myRecipients.length > 0}
      />
      {selectedUserId ? (
        <ShiftsView shifts={shifts} readOnly />
      ) : (
        <EmptyState hasShared={myRecipients.length > 0} />
      )}
    </I18nProvider>
  );
}
```

### 3. Translations

Add to dictionary files:

```json
{
  "sharing": {
    "title": "Deling",
    "myShifts": "Mine vakter",
    "manageSharing": "Administrer deling",
    "shareYourShifts": "Del vaktene dine",
    "sharedWithYou": "Delt med deg",
    "addPerson": "Legg til person",
    "emailOrPhone": "E-post eller telefonnummer",
    "removeAccess": "Fjern tilgang",
    "noShares": "Du har ikke delt vaktene dine med noen ennå",
    "noSharedWithYou": "Ingen har delt vaktene sine med deg ennå",
    "userNotFound": "Fant ingen bruker med denne e-posten eller telefonnummeret",
    "alreadyShared": "Du deler allerede vaktene dine med denne brukeren",
    "shareAdded": "Deling lagt til",
    "shareRemoved": "Deling fjernet"
  }
}
```

## Security Considerations

### 1. Authorization Checks
- **DAL level:** Verify `viewer_id` exists in `shift_shares` before returning shared data
- **Server actions:** Verify ownership before creating/deleting shares
- **RLS policies:** Database-level enforcement as final safety net

### 2. Data Exposure
- Shared users see: Shifts, computed wages, shift details
- Shared users do NOT see: Settings page, other private data
- Read-only access: No edit/delete operations on shared shifts

### 3. User Lookup
- When adding a share by email/phone:
  - Lookup must be done server-side
  - Don't expose whether an email/phone exists (privacy)
  - Return generic "Added if user exists" message
  - Rate limit to prevent enumeration

### 4. Input Validation
- Validate email format or phone number format
- Sanitize inputs before database queries
- Use parameterized queries (Supabase handles this)

## Implementation Order

### Phase 1: Database (Migration)
1. Create `shift_shares` table with indexes
2. Add RLS policies to `shift_shares`
3. Add RLS policies to `user_shifts`, `wage_snapshots`, `user_settings`

### Phase 2: Backend
1. Create `data-access/sharing.ts` with DAL functions
2. Create server actions for create/remove share
3. Add translations to dictionary files
4. Update cache invalidation utilities

### Phase 3: Frontend - Basic
1. Add UserMenu item for Sharing
2. Create sharing page with dropdown
3. Integrate existing ShiftsView with `readOnly` prop

### Phase 4: Frontend - Modal
1. Create ManageSharingModal component
2. Create ShareRecipientList component
3. Create AddShareForm component
4. Wire up to server actions

### Phase 5: Polish
1. Add loading states and skeletons
2. Add error handling UI
3. Add toast notifications for actions
4. Test all flows end-to-end

## File Structure (New Files)

```
supabase/migrations/
  └── YYYYMMDDHHMMSS_add_shift_shares.sql

data-access/
  └── sharing.ts

lib/services/
  └── sharing.ts (Effect-based service)

app/[locale]/(app)/sharing/
  ├── page.tsx
  ├── loading.tsx
  └── _actions/
      └── sharing.ts

components/sharing/
  ├── SharingDropdown.tsx
  ├── ManageSharingModal.tsx
  ├── ShareRecipientList.tsx
  └── AddShareForm.tsx

lib/i18n/dictionaries/
  ├── en.json (update)
  └── no.json (update)
```

## Decisions Made

1. ✅ **Profile pictures:** `user_settings.profile_picture_url` exists - use this, with fallback to initials
2. ✅ **Notifications:** No - silent sharing. Recipients can view freely without notifying owner.
3. ✅ **Expiration:** No expiration. Shares persist until explicitly revoked. Simpler UX, can add later if needed.
4. ✅ **Limits by subscription tier:**
   - Free: 1 share recipient
   - Pro: up to 10 share recipients
   - Max: up to 20 share recipients
5. ✅ **Lookup methods:** Support both email AND phone. Works with OAuth users (they have email in `auth.users`).

## User Lookup Strategy

For finding users by email or phone to share with:
- Query `auth.users` via service role key (server-side only)
- `auth.users.email` - works for all users (OAuth, email/password, magic link)
- `auth.users.phone` - works for users who added phone number
- Rate limit at application layer to prevent enumeration attacks

**Implementation:** Create a server action that:
1. Accepts email OR phone as input
2. Uses Supabase admin client to query `auth.users`
3. Returns user_id if found (don't expose whether email/phone exists to prevent enumeration)
4. Checks subscription tier limit before creating share
