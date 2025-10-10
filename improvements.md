# Code Quality & Security Improvements

This document outlines potential coding mistakes, security risks, and user experience issues identified in the codebase.

## Critical Security Issues

### ~~1. Open Redirect Vulnerability in OAuth Callback~~ ✅ FIXED
**Location:** [app/auth/callback/route.ts:10-11](app/auth/callback/route.ts#L10-L11)

**Issue:** The `next` query parameter is taken directly from the URL and used for redirection without validation. An attacker could craft a malicious URL like `yourdomain.com/auth/callback?next=https://evil.com` to redirect users to phishing sites.

**Risk Level:** 🔴 High

**Recommendation:**
```typescript
// Validate that redirect URL is relative or same-origin
const next = requestUrl.searchParams.get("next") ?? "/";
const isRelative = !next.startsWith("http");
const isSameOrigin = next.startsWith(requestUrl.origin);
const safeNext = (isRelative || isSameOrigin) ? next : "/";
const redirectUrl = new URL(safeNext, requestUrl.origin);
```

---

### ~~2. Missing .env Files in .gitignore~~ ✅ FIXED
**Location:** [.gitignore](.gitignore)

**Issue:** The `.gitignore` file doesn't explicitly ignore environment files (`.env`, `.env.local`, `.env.production`, etc.). While Next.js might ignore some by default, this creates risk of accidentally committing secrets to version control.

**Risk Level:** 🔴 High

**Recommendation:** Add to `.gitignore`:
```
# local env files
.env*.local
.env
.env.development
.env.production
```

---

### ~~3. Weak Password Requirements~~ ✅ FIXED
**Location:**
- [app/(auth)/signup/page.tsx:43](app/(auth)/signup/page.tsx#L43)
- [app/(auth)/reset-password/page.tsx:105](app/(auth)/reset-password/page.tsx#L105)

**Issue:** Minimum password length is only 6 characters with no complexity requirements (no uppercase, numbers, or special characters). This makes accounts vulnerable to brute force attacks.

**Risk Level:** 🟡 Medium

**Recommendation:**
```typescript
// Increase minimum to 8-10 characters
if (password.length < 8) {
  setMessage({
    type: "error",
    text: "Passordet må være minst 8 tegn langt.",
  });
  return;
}

// Optional: Add complexity check
const hasUpperCase = /[A-Z]/.test(password);
const hasLowerCase = /[a-z]/.test(password);
const hasNumbers = /\d/.test(password);
if (!hasUpperCase || !hasLowerCase || !hasNumbers) {
  setMessage({
    type: "error",
    text: "Passordet må inneholde store og små bokstaver samt tall.",
  });
  return;
}
```

---

### ~~4. Static CSRF Token~~ ✅ FIXED
**Location:** [app/auth/callback/route.ts:30](app/auth/callback/route.ts#L30)

**Issue:** The CSRF token `"auth-sync"` is a hardcoded string rather than a randomly generated token. While this provides some protection, any script that knows this value can make requests.

**Risk Level:** 🟡 Medium

**Solution Implemented:**
- Created middleware ([middleware.ts](middleware.ts)) that generates cryptographically secure CSRF tokens using Web Crypto API
- Tokens are stored in httpOnly cookies and validated on every auth sync request
- Created CSRF utility library ([lib/csrf.ts](lib/csrf.ts)) with token validation using constant-time comparison
- Created CSRFProvider ([components/app/CSRFProvider.tsx](components/app/CSRFProvider.tsx)) to pass tokens to client components
- Updated all auth pages to use dynamic CSRF tokens via `useCSRF()` hook

---

## User Experience Issues

### ~~5. Race Condition in Post-Auth Navigation~~ ✅ FIXED
**Location:**
- [app/(auth)/login/page.tsx:86-87](app/(auth)/login/page.tsx#L86-L87)
- [app/(auth)/signup/page.tsx:95-96](app/(auth)/signup/page.tsx#L95-L96)

**Issue:** Code calls `router.replace()` immediately followed by `router.refresh()`. The refresh might fire before replace completes, causing UI flicker or inconsistent state. The "microtask tick" (`await Promise.resolve()`) provides insufficient protection.

**Risk Level:** 🟡 Medium (UX degradation)

**Solution Implemented:**
- Removed redundant `router.refresh()` calls - Next.js automatically refreshes server components on route navigation
- Added proper error handling for failed session sync
- Wait for `fetch()` response and check `response.ok` before navigating
- This ensures auth state is fully synced before navigation occurs

---

### ~~6. Theme Flash on Initial Load~~ ✅ FIXED
**Location:** [app/layout.tsx:38-47](app/layout.tsx#L38-L47)

**Issue:** The inline script prevents FOUC using localStorage, but if the user has a different DB preference, there will be a visible flash when `ThemeProvider` runs client-side and updates it.

**Risk Level:** 🟢 Low (minor annoyance)

**Solution Implemented:**
- Changed `ThemeProvider` to use `useLayoutEffect` instead of `useEffect` for synchronous theme application before browser paint
- Added documentation comments to inline script explaining relationship with ThemeProvider
- ThemeProvider now syncs serverTheme to localStorage on first load to prevent future flashes
- Minimizes visible flash when DB theme differs from localStorage

---

### ~~7. No Loading State During OAuth Redirect~~ ✅ FIXED
**Location:** [app/(auth)/login/page.tsx:90-111](app/(auth)/login/page.tsx#L90-L111)

**Issue:** While `isOAuthRedirecting` is set to `true`, the user stays on the login page. If the OAuth provider is slow to respond, this creates confusion.

**Risk Level:** 🟢 Low (UX polish)

**Solution Implemented:**
- Added full-screen loading overlay with backdrop blur when `isOAuthRedirecting` is true
- Shows animated spinner and "Sender deg videre til Google..." message
- Uses high z-index (z-50) to ensure overlay appears above all content
- Provides clear visual feedback during OAuth redirect transition

---

### ~~8. Fragile Redirect Timeouts~~ ✅ FIXED
**Location:**
- [app/(auth)/signup/page.tsx:94-97](app/(auth)/signup/page.tsx#L94-L97)
- [app/(auth)/reset-password/page.tsx:133-136](app/(auth)/reset-password/page.tsx#L133-L136)

**Issue:** Using `setTimeout` for navigation is fragile. If session sync takes longer than 1.5s, the redirect happens anyway, potentially navigating before auth state is synced.

**Risk Level:** 🟡 Medium (could cause auth failures)

**Solution Implemented:**
- Removed all `setTimeout` calls from auth navigation
- Now properly awaits `fetch()` response for session sync
- Checks `response.ok` before proceeding with navigation
- Added error handling to show user-friendly messages if sync fails
- This ensures navigation only happens after successful authentication

---

## Data & Logic Issues

### ~~9. Date/Timezone Inconsistency Risk~~ ✅ FIXED
**Location:**
- [app/(app)/_data/getMonthlyTotal.ts:31-41](app/(app)/_data/getMonthlyTotal.ts#L31-L41)
- [app/(app)/stats/_data/getStatsData.ts:27-62](app/(app)/stats/_data/getStatsData.ts#L27-L62)

**Issue:** Uses `new Date()` to get current month on server, but shifts use local dates (`shift_date` as YYYY-MM-DD). If server timezone differs from user timezone, monthly totals could be off near month boundaries.

**Risk Level:** 🟡 Medium (data accuracy)

**Solution Implemented:**
- Created comprehensive date utility library ([lib/date-utils.ts](lib/date-utils.ts)) with UTC-based date handling
- All shift dates are now parsed consistently as UTC dates using `parseDateAsUTC()`
- Created helper functions: `getCurrentYearMonth()`, `getPreviousYearMonth()`, `isDateInMonth()`
- Updated both `getMonthlyTotal.ts` and `getStatsData.ts` to use these utilities
- Added detailed documentation explaining timezone handling approach
- Ensures consistent date comparisons regardless of server timezone

---

### ~~10. Misleading Percentage Change Calculation~~ ✅ FIXED
**Location:** [app/(app)/_data/getMonthlyTotal.ts:74-77](app/(app)/_data/getMonthlyTotal.ts#L74-L77)

**Issue:** If last month's earnings were 0 but current month has earnings, percentage change is `undefined` rather than showing meaningful growth indicator.

**Risk Level:** 🟢 Low (UX polish)

**Solution Implemented:**
- Updated return type to accept `number | ".." | undefined` for percentage change
- When earnings go from 0 to positive, now returns ".." indicator instead of undefined
- Provides clearer UX when starting to earn after a zero-earnings month

---

### ~~11. Missing Error Handling in Data Loaders~~ ✅ FIXED
**Location:** [app/(app)/settings/_data/getSettings.ts:14](app/(app)/settings/_data/getSettings.ts#L14)

**Issue:** The `getUserSettings` function throws errors directly. Database errors will crash the entire page rather than showing a friendly error message.

**Risk Level:** 🟡 Medium (poor UX)

**Recommendation:**
```typescript
export async function getUserSettings(userId: string) {
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase
      .from('user_settings')
      .select('*')
      .eq('user_id', userId)
      .single();

    if (error) {
      console.error('Failed to fetch user settings:', error);
      return null; // Or return default settings
    }
    return data;
  } catch (error) {
    console.error('Unexpected error fetching settings:', error);
    return null;
  }
}
```

---

### ~~12. Silent Settings Load Failures~~ ✅ FIXED
**Location:** [app/(app)/shifts/_data/getShifts.ts:36](app/(app)/shifts/_data/getShifts.ts#L36)

**Issue:** Settings fetch errors are logged but silently ignored with empty object fallback. Users won't know their settings failed to load, leading to incorrect wage calculations.

**Risk Level:** 🟡 Medium (data accuracy)

**Recommendation:** Either throw the error (and show error page) or show a warning banner to user that default settings are being used.

---

### ~~13. No Validation in updatePaySettings~~ ✅ FIXED
**Location:** [app/(app)/settings/_actions/updateSettings.ts:50-82](app/(app)/settings/_actions/updateSettings.ts#L50-L82)

**Issue:** The `custom_bonuses` field accepts `any` type and is passed directly to database without validation. Malicious input could cause issues during payroll calculations.

**Risk Level:** 🟡 Medium

**Recommendation:**
```typescript
// Add schema validation
import { z } from 'zod';

const BonusRuleSchema = z.object({
  days: z.array(z.number().min(1).max(7)),
  from: z.string().regex(/^\d{2}:\d{2}$/),
  to: z.string().regex(/^\d{2}:\d{2}$/),
  rate: z.number().optional(),
  percent: z.number().optional(),
});

const CustomBonusesSchema = z.object({
  rules: z.array(BonusRuleSchema),
});

// In updatePaySettings:
if (data.custom_bonuses !== undefined) {
  try {
    CustomBonusesSchema.parse(data.custom_bonuses);
  } catch (error) {
    throw new Error('Invalid bonus configuration');
  }
}
```

---

## Performance & Optimization Issues

### ~~14. Excessive revalidatePath Calls~~ ✅ FIXED
**Location:** [app/(app)/settings/_actions/updateSettings.ts:45-46](app/(app)/settings/_actions/updateSettings.ts#L45-L46)

**Issue:** `clearAllShifts` calls `revalidatePath` for both `/shifts` and `/settings/profile`. Multiple revalidations could cause unnecessary re-renders.

**Risk Level:** 🟢 Low (performance)

**Solution Implemented:**
- Removed unnecessary `revalidatePath('/settings/profile')` call from `clearAllShifts`
- Profile page only displays user metadata (name, picture), which isn't affected by deleting shifts
- Now only revalidates `/shifts` which is the actual affected route
- Reduces unnecessary server component re-renders

---

### ~~15. No Debouncing on Theme Toggle~~ ✅ FIXED
**Location:** [components/app/ThemeToggle.tsx:17-27](components/app/ThemeToggle.tsx#L17-L27)

**Issue:** Every theme toggle immediately writes to localStorage AND makes a database call. Rapid toggling could queue multiple database requests.

**Risk Level:** 🟢 Low (performance)

**Solution Implemented:**
- Added debouncing to theme database sync using `setTimeout` with 1-second delay
- Uses `useRef` to track debounce timer and clear previous timeouts on rapid toggles
- Added cleanup in `useLayoutEffect` to clear timer on component unmount
- UI still updates immediately (localStorage + DOM), but DB sync is debounced
- Prevents multiple database requests when user rapidly toggles theme

---

### ~~16. Duplicate Theme State Management~~ ✅ FIXED
**Location:**
- [components/app/ThemeProvider.tsx:8-43](components/app/ThemeProvider.tsx#L8-L43)
- [components/app/ThemeToggle.tsx:7-27](components/app/ThemeToggle.tsx#L7-L27)

**Issue:** Both components maintain independent theme state and localStorage logic. This could lead to state desync.

**Risk Level:** 🟢 Low (code quality)

**Solution Implemented:**
- Created new `ThemeContext.tsx` with React Context for shared theme state
- ThemeProvider now exports a `useTheme()` hook for consuming components
- Refactored ThemeToggle to use `useTheme()` hook instead of maintaining its own state
- All theme logic (state, localStorage, DB sync, debouncing) centralized in ThemeContext
- ThemeProvider.tsx now re-exports from ThemeContext for backward compatibility
- Eliminates duplicate state management and prevents desync issues

---

## Code Quality Issues

### ~~17. Magic Numbers in Payroll Calculations~~ ✅ FIXED
**Location:** [lib/payroll/calc.ts:71-74](lib/payroll/calc.ts#L71-L74)

**Issue:** Uses `Math.round(...* 1000) / 1000` and `Math.round(...* 100) / 100` without explaining why. Magic numbers hurt maintainability.

**Risk Level:** 🟢 Low (maintainability)

**Solution Implemented:**
- Added named constants `HOUR_DECIMAL_PRECISION = 1000` and `CURRENCY_PRECISION = 100`
- Replaced all magic number instances with these constants
- Added inline comments explaining precision (3 decimal places for hours, 2 for currency)

---

### ~~18. Inconsistent Error Messages~~ ✅ PARTIALLY FIXED
**Location:** Throughout codebase

**Issue:** Some errors are in Norwegian ("Ugyldig dato"), while Supabase errors are in English. Creates inconsistent UX.

**Risk Level:** 🟢 Low (UX polish)

**Solution Implemented:**
- Created `lib/errors/translate.ts` utility with common Supabase error translations to Norwegian
- Updated login page to use `translateError()` for all auth error messages
- Supports both exact matches and partial string replacement
- Falls back to original English message if no translation available
- **Note:** Other auth pages (signup, reset-password) should also be updated with this utility for full consistency

---

### ~~19. Production Console Logs~~ ✅ FIXED
**Location:**
- [app/supabase-listener.tsx:23-33](app/supabase-listener.tsx#L23-L33)
- [lib/env.ts:8](lib/env.ts#L8)

**Issue:** Multiple `console.log` and `console.error` statements run in production, potentially leaking sensitive information.

**Risk Level:** 🟡 Medium (security/performance)

**Recommendation:**
```typescript
// Create a logger utility
const logger = {
  log: (...args: any[]) => {
    if (process.env.NODE_ENV === 'development') {
      console.log(...args);
    }
  },
  error: (...args: any[]) => {
    // Always log errors but sanitize in production
    console.error(...args);
  },
};
```

---

### ~~20. Incomplete Features Exposed to Users~~ ✅ FIXED
**Location:** [components/settings/data/DataForm.tsx:16-33](components/settings/data/DataForm.tsx#L16-L33)

**Issue:** Export and import buttons exist in UI but are TODOs that do nothing. Creates false expectations.

**Risk Level:** 🟢 Low (UX)

**Current State:** Already properly handled
- Buttons have `disabled` attribute
- Entire section has `opacity-50 pointer-events-none` styling
- Prominent "Kommer snart" warning card visible to users
- No false expectations created

---

## Minor Issues

### ~~21. sessionStorage for Modal Dismissal~~ ✅ FIXED
**Location:** [app/(app)/_components/OnboardingPromptModal.tsx:32-51](app/(app)/_components/OnboardingPromptModal.tsx#L32-L51)

**Issue:** Uses `sessionStorage` to track dismissed state, so modal re-appears every browser session until user completes onboarding. Could be annoying.

**Risk Level:** 🟢 Low (UX)

**Solution Implemented:**
- Added three dismiss options with different persistence levels:
  1. "Start oppsett" - Navigates to onboarding
  2. "Gjør det senere" - Dismisses for current session only (sessionStorage)
  3. "Ikke vis dette igjen" - Permanently dismisses (localStorage)
- Modal checks both localStorage and sessionStorage before showing
- Gives users control over dismissal behavior without being annoying

---

### ~~22. No Input Sanitization on User Metadata~~ ✅ FIXED
**Location:** [app/(app)/layout.tsx:35-45](app/(app)/layout.tsx#L35-L45)

**Issue:** User metadata from OAuth providers (`first_name`, `full_name`, etc.) is used directly without sanitization. While React auto-escapes, this could be risky in non-React contexts.

**Risk Level:** 🟢 Low (defense in depth)

**Solution Implemented:**
- Created `lib/sanitize.ts` with sanitization utilities for user input
- `sanitizeDisplayName()` - Removes control characters, normalizes whitespace, validates contains letters/numbers
- `sanitizeUrl()` - Validates URLs and ensures only http/https protocols
- `sanitizeUserInput()` - General-purpose sanitizer with length limits
- Updated app layout to sanitize all user metadata (userName, avatarUrl) before use
- Provides defense-in-depth protection even though React auto-escapes in JSX

---

### ~~23. Missing Documentation for Cookie Flags~~ ✅ FIXED
**Location:** [lib/supabase/server.ts:10](lib/supabase/server.ts#L10)

**Issue:** Cookie `secure` flag only applies in production. During development with HTTP, cookies aren't secure. This is fine but could confuse developers.

**Risk Level:** 🟢 Low (documentation)

**Solution Implemented:**
- Added inline comment explaining secure flag behavior
- Documents that HTTPS is required for secure cookies
- Clarifies that in development (HTTP), secure cookies are rejected by browsers

---

## Summary

**Priority Order for Fixes:**

1. 🔴 **Critical:** ~~#1 (Open redirect)~~ ✅, ~~#2 (.gitignore)~~ ✅, ~~#3 (Weak passwords)~~ ✅
2. 🟡 **High:** ~~#11 (Error handling)~~ ✅, ~~#12 (Silent failures)~~ ✅, ~~#13 (Input validation)~~ ✅, ~~#19 (Console logs)~~ ✅
3. 🟡 **Medium:** #4 (CSRF), #5 (Race conditions), #8 (Timeouts), #9 (Timezone), #14 (Revalidation)
4. 🟢 **Low:** All others (polish and maintainability improvements)

Most issues are fixable with relatively small changes that would significantly improve security, reliability, and user experience.
