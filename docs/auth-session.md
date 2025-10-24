# Authentication & Session Management

Complete documentation for authentication configuration, session refresh mechanics, and monitoring in this PWA.

---

## Current Configuration

### Access Token Settings

| Setting | Value | Location | Notes |
|---------|-------|----------|-------|
| **JWT Expiry** | `3600` seconds (1 hour) | [supabase/config.toml:127](../supabase/config.toml#L127) | Default Supabase value |
| **Max Expiry** | `604800` seconds (1 week) | Supabase limit | Cannot exceed this |
| **Override ENV** | `AUTH_ACCESS_TTL_SECONDS` | [.env.local.example:14](../.env.local.example#L14) | Commented out by default |

**Current behavior:**
- User logs in → receives access token valid for 1 hour
- After 1 hour, token expires
- If user has app open: automatic refresh via `onAuthStateChange`
- If user closed app >1 hour: wake-up refresh triggers on reopen (via visibilitychange)

---

### Refresh Token Settings

| Setting | Value | Location | Notes |
|---------|-------|----------|-------|
| **Rotation Enabled** | `true` | [supabase/config.toml:131](../supabase/config.toml#L131) | Each refresh returns new token |
| **Reuse Interval** | `10` seconds | [supabase/config.toml:134](../supabase/config.toml#L134) | Grace period for concurrent requests |
| **Token Expiry** | Does not expire | Supabase default | Refresh tokens do not expire by themselves |
| **Cookie MaxAge** | `7` days | [lib/supabase/server.ts:48](../lib/supabase/server.ts#L48) | Cookie expiry limits practical session duration |

**Important clarifications:**
- ✅ **Refresh tokens do not have an inherent expiry** - they are valid until revoked or rotated
- ✅ **Session duration is limited by cookie maxAge** (currently 7 days)
- ✅ After 7 days, the cookie expires and the refresh token is no longer sent to the server
- ✅ User activity (login, refresh) extends the session by resetting the cookie expiry
- ✅ See [Supabase User Sessions docs](https://supabase.com/docs/guides/auth/sessions) for details

**Single-use verification:**
- ✅ After successful refresh, old refresh token is invalidated
- ✅ 10-second grace period allows retry if network failed
- ✅ See [tests/manual/refresh-token-rotation-test.md](../tests/manual/refresh-token-rotation-test.md) for verification procedure

---

### Rate Limits

From [supabase/config.toml:147-161](../supabase/config.toml#L147-L161):

| Operation | Limit | Window | Impact |
|-----------|-------|--------|--------|
| **Token Refresh** | 150 requests | 5 minutes per IP | Main limit for session refresh |
| **Sign-in/Sign-up** | 30 requests | 5 minutes per IP | Login throttle |
| **Email Sent** | 2 emails | 1 hour | Password reset, verification |
| **Token Verifications** | 30 requests | 5 minutes per IP | OTP/Magic link |

**Why this matters:**
- If a bug causes refresh spam, we hit rate limits after 150 refreshes in 5 minutes
- Telemetry tracks refresh frequency to detect issues before hitting limits

---

## Supabase Studio Configuration

### Access Settings in Production

**Path in Supabase Studio:**
```
Project Dashboard
  → Authentication (left sidebar)
    → Settings (tab)
      → "Auth Settings" section
        → JWT Expiry: 3600 seconds
        → Refresh Token Rotation: Enabled
        → Refresh Token Reuse Interval: 10 seconds
```

**To verify current settings:**
1. Go to https://supabase.com/dashboard/project/YOUR_PROJECT_ID
2. Navigate to: **Authentication** → **Settings** → Scroll to "JWT Settings"
3. Confirm:
   - `JWT expiry` = `3600` (or whatever value you set)
   - `Enable refresh token rotation` = checked
   - `Refresh token reuse interval` = `10`

**⚠️ IMPORTANT:**
- Changes in Studio override `supabase/config.toml` (local only)
- For production, always update via Studio
- For local dev, edit `supabase/config.toml` then restart Supabase

---

## Session Refresh Mechanics

### Automatic Refresh (Active App)

When user has app open and interacting:

```
User logged in
  ↓
Access token expires after 1 hour
  ↓
Supabase client detects expiry
  ↓
Calls refresh automatically (via onAuthStateChange)
  ↓
New tokens saved to cookie
  ↓
App continues without interruption ✅
```

**Code:** [app/supabase-listener.tsx:21-36](../app/supabase-listener.tsx#L21-L36)

---

### Wake-Up Refresh (App Reopened)

**Problem solved:** User closes PWA for >1 hour, reopens → previously would logout

**New behavior:**

```
User closes app (token expires while closed)
  ↓
User reopens app after >1 hour
  ↓
One of these events fires:
  - visibilitychange (most browsers)
  - pageshow (iOS Safari bfcache)
  - focus (iOS standalone mode fallback)
  ↓
Event handler calls getSession()
  ↓
Supabase refreshes token automatically
  ↓
New tokens saved to cookie
  ↓
User stays logged in ✅
```

**Code:**
- Visibilitychange: [app/supabase-listener.tsx:42-63](../app/supabase-listener.tsx#L42-L63)
- Pageshow: [app/supabase-listener.tsx:68-89](../app/supabase-listener.tsx#L68-L89)
- Focus: [app/supabase-listener.tsx:94-127](../app/supabase-listener.tsx#L94-L127)
- Initial check: [components/app/AppLayoutClient.tsx:44-68](../components/app/AppLayoutClient.tsx#L44-L68)

---

### Error Recovery

If refresh fails (expired refresh token, network error, etc.):

```
API call returns 401
  ↓
handleAuthError() catches it
  ↓
Attempts ONE session refresh (withRefreshLock)
  ↓
Success? → Continue
  ↓
Failure? → Sign out + redirect to /login
```

**Code:** [lib/auth/error-recovery.ts](../lib/auth/error-recovery.ts)

---

## Telemetry & Monitoring

### Events Tracked

All session refresh attempts are logged with these events:

| Event Type | Reason Values | When Fired |
|------------|---------------|------------|
| `session_refresh_attempt` | `visibilitychange` | App becomes visible |
| | `pageshow` | iOS bfcache restore |
| | `focus` | Window focus (iOS fallback) |
| | `initial` | App first mount |
| | `error_recovery` | After 401 error |
| `session_refresh_success` | (same as above) | Refresh completed successfully |
| `session_refresh_failure` | (same as above) | Refresh failed with error (400/401) |
| `session_refresh_skipped_no_cookie` | (same as above) | Cookie missing at wake - skipped refresh |

**Important distinctions:**
- ✅ **`session_refresh_failure`**: Cookie exists, but refresh returned 400/401 error
- ✅ **`session_refresh_skipped_no_cookie`**: No auth cookie found, refresh was skipped (expected after cookie expiry or debouncing)

**Event Pairing with attemptId:**
- Each `session_refresh_attempt` generates a unique `attemptId` (UUID)
- Corresponding `session_refresh_success` or `session_refresh_failure` includes the same `attemptId`
- Success rate is calculated by matching attemptIds: `(successful attempts / completed attempts) * 100`
- This ensures accurate metrics even if events are logged out of order

**Wake Debouncing:**
- Multiple wake events (visibilitychange, pageshow, focus) can fire simultaneously on iOS
- Debounce window: 1000ms - only one refresh attempt allowed per second
- Subsequent attempts within the window are logged as `session_refresh_skipped_no_cookie`
- Prevents refresh spam and reduces unnecessary API calls

**Code:** [lib/auth/session-telemetry.ts](../lib/auth/session-telemetry.ts)

---

### Development Metrics

In development, telemetry is logged to console and stored in memory (24h window).

**View metrics in browser console:**
```javascript
// Get metrics object
window.__sessionMetrics.getMetrics()

// Print formatted metrics
window.__sessionMetrics.printMetrics()
```

**Example output:**
```
📊 Session Refresh Metrics (24h)
Total events: 45
Success rate: 97.8%
By reason: {
  visibilitychange: 20,
  initial: 15,
  pageshow: 8,
  focus: 2
}
Error codes: {
  http_401: 1
}
Avg duration: 145 ms
```

---

### Production Logging

In production, events are logged to console (visible in Vercel logs).

**To integrate with analytics:**

Edit [lib/auth/session-telemetry.ts:61-70](../lib/auth/session-telemetry.ts#L61-L70):

```typescript
// Production: Send to analytics (currently just console.log)
if (process.env.NODE_ENV === "production") {
  // TODO: Replace with your analytics service
  fetch('/api/analytics', {
    method: 'POST',
    body: JSON.stringify(event),
    keepalive: true,
  });
}
```

**Recommended services:**
- Vercel Analytics (built-in)
- PostHog (self-hosted analytics)
- Custom endpoint logging to database

---

### Success Metrics

**How to measure success in production:**

1. **Session Refresh Success Rate**
   - **Target:** >99% success rate
   - **Calculation:** `successes / attempts * 100`
   - **Alert if:** <95%

2. **401 Error Rate**
   - **Target:** <0.5% of all API requests result in 401
   - **Calculation:** `401_errors / total_requests * 100`
   - **Alert if:** >1%

3. **Average Session Duration**
   - **Target:** >24 hours (users stay logged in across days)
   - **Measurement:** Time between login and logout events
   - **Alert if:** <12 hours average

4. **Wake-Refresh Latency**
   - **Target:** <500ms average
   - **Measurement:** `duration_ms` in telemetry events
   - **Alert if:** >1000ms p95

---

## Testing

### Manual Testing

**Test 1: Simulate expired token**
```bash
# Step 1: Login and open DevTools
# Step 2: Application → Cookies → Find sb-*-auth-token
# Step 3: Edit cookie, change access_token to "invalid_token"
# Step 4: Switch to another tab, then back
# Expected: Console shows refresh, no redirect to /login
```

**Test 2: 1-hour timeout**
```bash
# Step 1: Login at 10:00 AM
# Step 2: Close browser/PWA
# Step 3: Wait 90 minutes
# Step 4: Reopen PWA
# Expected: Still logged in, console shows visibilitychange refresh
```

---

### E2E Tests (Playwright)

**Location:** [tests/e2e/auth-wake-refresh.spec.ts](../tests/e2e/auth-wake-refresh.spec.ts)

**Run tests:**
```bash
# Install browsers (first time only)
npx playwright install

# Run tests
npx playwright test

# Run tests in UI mode
npx playwright test --ui
```

**Note:** Tests require real Supabase credentials. Some tests are marked `.skip()` and require manual configuration.

---

### Refresh Token Rotation Test

**Manual verification procedure:**

See [tests/manual/refresh-token-rotation-test.md](../tests/manual/refresh-token-rotation-test.md)

**Quick test:**
```bash
# 1. Login and capture refresh token A
# 2. Trigger refresh → get new token B
# 3. Try to use token A again (should fail with 400)
# 4. Use token B (should work)
```

---

## Changing JWT Expiry

### When to Consider Increasing

Monitor metrics for 1-2 weeks. Consider increasing if:

- ✅ Success rate consistently >99%
- ✅ Zero "Invalid Refresh Token" errors
- ✅ Wake-refresh working reliably on iOS PWA
- ✅ Users not complaining about logouts

**Benefits of increasing (e.g., 1h → 8h):**
- Fewer refresh requests (reduces load)
- Less battery usage on mobile
- Smoother UX (fewer micro-interruptions)

**Risks of increasing:**
- Longer window for stolen token to be valid
- Higher impact if user needs immediate logout (e.g., compromised account)

---

### How to Change (Production)

**Method 1: Via Supabase Studio (Recommended)**

1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Navigate: **Authentication** → **Settings**
4. Scroll to "JWT Settings"
5. Change `JWT expiry` from `3600` to desired value (e.g., `28800` for 8 hours)
6. Click **Save**
7. **No deployment required** - takes effect immediately

**Method 2: Via Environment Variable (Future)**

Currently, JWT expiry is set server-side (Supabase). To implement app-level override:

1. Uncomment in `.env.local`:
   ```bash
   AUTH_ACCESS_TTL_SECONDS=28800
   ```

2. Update `supabase/config.toml`:
   ```toml
   jwt_expiry = ${AUTH_ACCESS_TTL_SECONDS:-3600}
   ```

3. Restart local Supabase:
   ```bash
   supabase stop
   supabase start
   ```

**⚠️ NOTE:** Step 2 requires Supabase CLI v1.50+. Check if your version supports env var interpolation.

---

### Recommended Incremental Approach

Don't jump from 1h → 8h immediately. Test incrementally:

| Stage | Duration | Monitor For | Duration to Test |
|-------|----------|-------------|------------------|
| **Current** | 1 hour | Baseline metrics | Already live |
| **Stage 1** | 2 hours | No increase in 401s | 1 week |
| **Stage 2** | 4 hours | Wake-refresh still reliable | 1 week |
| **Stage 3** | 8 hours | No user complaints | 2 weeks |

At each stage, verify:
- ✅ Success rate remains >99%
- ✅ No spike in 401 errors
- ✅ iOS PWA users not reporting issues

---

## Changing Cookie MaxAge

### Current Configuration

**Default:** 7 days (604800 seconds)
**Location:** [lib/supabase/server.ts:14-23](../lib/supabase/server.ts#L14-L23)
**ENV Override:** `AUTH_COOKIE_MAX_AGE_SECONDS`

### When to Consider Increasing

The cookie maxAge determines how long users stay logged in without any activity. Consider increasing from 7d to 14-30d if:

- ✅ Users frequently report being logged out after a week
- ✅ Your app has weekly usage patterns (e.g., weekend users)
- ✅ Session refresh metrics show stable >99% success rate
- ✅ `session_refresh_skipped_no_cookie` events are common

**Benefits of increasing (e.g., 7d → 14d):**
- Users stay logged in longer between app opens
- Fewer re-logins for weekly users
- Better UX for infrequent app usage

**Risks of increasing:**
- Longer exposure window if device is compromised
- Cookie storage may be purged by browser after long periods (especially iOS)

---

### How to Change (Production)

1. Uncomment in `.env.local`:
   ```bash
   AUTH_COOKIE_MAX_AGE_SECONDS=1209600  # 14 days
   ```

2. Deploy to production:
   ```bash
   git add .env.local
   git commit -m "chore: increase cookie maxAge to 14 days"
   git push
   ```

3. Monitor for 1 week:
   - Check `session_refresh_skipped_no_cookie` events
   - Verify users stay logged in longer
   - Watch for increased 401 errors (indicates premature cookie expiry)

**Recommended values:**
- **7 days (default)**: Good for daily/weekly users
- **14 days**: Good for bi-weekly users
- **30 days**: Only if metrics show users regularly go >2 weeks between opens

**⚠️ IMPORTANT:** Cookie maxAge should generally be >= JWT expiry. If JWT expires after 8h but cookie after 7d, users get auto-refresh for 7 days. If you increase JWT expiry to 1 week, consider also increasing cookie maxAge to 2-4 weeks.

---

### Telemetry: Cookie Expiry Tracking

Monitor `session_refresh_skipped_no_cookie` events to understand cookie expiry patterns:

```javascript
// In browser console
window.__sessionMetrics.printMetrics()
// Look at: skipped_no_cookie count
```

**High skipped_no_cookie count** (>10% of wake events):
- Indicates users frequently return after cookie expired
- Consider increasing cookie maxAge

**Low skipped_no_cookie count** (<5%):
- Current cookie maxAge is appropriate
- Most users return within 7 days

---

## Troubleshooting

### Issue: Users logged out after 1 hour

**Possible causes:**
1. Wake-refresh not implemented → **Fixed** (this PR)
2. Service worker caching `/auth/callback` → Check [next.config.js:36-39](../next.config.js#L36-L39)
3. iOS clearing localStorage → **Not applicable** (we use cookies)

**Verify fix:**
```javascript
// In browser console
console.log(document.addEventListener.toString());
// Should show visibilitychange, pageshow, focus listeners
```

---

### Issue: Refresh spam (multiple refreshes per second)

**Possible causes:**
1. Multiple `SupabaseListener` components mounted
2. React strict mode double-mounting without cleanup

**Verify:**
```javascript
// Check metrics
window.__sessionMetrics.printMetrics()
// Look for: by_reason with abnormally high counts (>100 per hour)
```

**Fix:**
- Ensure only one `SupabaseListener` in component tree
- Check that cleanup functions remove event listeners
- See [app/supabase-listener.tsx:123-126](../app/supabase-listener.tsx#L123-L126)

---

### Issue: "Invalid Refresh Token" errors

**Possible causes:**
1. Concurrent refresh requests (race condition)
2. Refresh token rotation reused old token

**Verify race condition:**
```javascript
// Check telemetry for multiple attempts at same timestamp
window.__sessionMetrics.getMetrics().by_reason
// If focus + visibilitychange fired <100ms apart → race condition
```

**Fix:**
- `withRefreshLock` should prevent this
- If still occurs, increase reuse interval:
  ```toml
  # supabase/config.toml
  refresh_token_reuse_interval = 20  # Increase from 10 to 20
  ```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         User Action                          │
└──────────┬──────────────────────────────────┬───────────────┘
           │                                   │
           │ Opens app                         │ Closes app >1h
           │ (cold start)                      │ then reopens
           ▼                                   ▼
    ┌──────────────┐                    ┌──────────────┐
    │   Initial    │                    │ Visibility   │
    │   Session    │                    │   Change     │
    │    Check     │                    │   Event      │
    └──────┬───────┘                    └──────┬───────┘
           │                                   │
           │ getSession()                      │ getSession()
           │                                   │
           ▼                                   ▼
    ┌──────────────────────────────────────────────────┐
    │           withRefreshLock()                       │
    │    (Prevents concurrent refresh requests)         │
    └──────┬───────────────────────────────────────────┘
           │
           │ If token expired
           ▼
    ┌──────────────────────────────────────────────────┐
    │     Supabase Auth: POST /token?grant_type=       │
    │              refresh_token                        │
    └──────┬───────────────────────────────────────────┘
           │
           ├─ Success (200) ──────┬─ New access token
           │                      ├─ New refresh token
           │                      └─ Old refresh token invalidated
           │
           └─ Failure (400/401) ──→ handleAuthError()
                                     ├─ Retry once
                                     └─ Sign out if still fails
```

---

## Files Reference

| File | Purpose |
|------|---------|
| [lib/auth/session-telemetry.ts](../lib/auth/session-telemetry.ts) | Telemetry logging & metrics |
| [lib/auth/refresh-lock.ts](../lib/auth/refresh-lock.ts) | Prevents concurrent refreshes |
| [lib/auth/error-recovery.ts](../lib/auth/error-recovery.ts) | Handles 401 errors with refresh |
| [app/supabase-listener.tsx](../app/supabase-listener.tsx) | Wake-up event listeners |
| [components/app/AppLayoutClient.tsx](../components/app/AppLayoutClient.tsx) | Initial session check |
| [supabase/config.toml](../supabase/config.toml) | JWT & refresh token config |
| [tests/e2e/auth-wake-refresh.spec.ts](../tests/e2e/auth-wake-refresh.spec.ts) | E2E tests |
| [tests/manual/refresh-token-rotation-test.md](../tests/manual/refresh-token-rotation-test.md) | Manual test procedure |

---

## Summary

### Current State (After Implementation)

✅ **Session persistence:** Users stay logged in for up to 7 days (refresh token lifetime)

✅ **Wake-up refresh:** Automatic token refresh when app reopens after >1 hour

✅ **Telemetry:** All refresh attempts tracked with reason, success/failure, and duration

✅ **Single-use refresh:** Old tokens invalidated after successful refresh (10s grace period)

✅ **Race protection:** `withRefreshLock` prevents concurrent refresh spam

✅ **Error recovery:** Automatic retry on 401, then sign out if refresh fails

✅ **ENV-ready:** Documented path to increase JWT expiry when metrics look good

### Next Steps

1. **Monitor for 1-2 weeks:**
   - Check metrics daily via Vercel logs or analytics
   - Look for success rate >99%, 401 rate <0.5%

2. **Consider increasing JWT expiry:**
   - After 2 weeks of stable metrics
   - Incrementally: 1h → 2h → 4h → 8h
   - Monitor at each stage

3. **Optional: Integrate analytics:**
   - Replace console.log in production with analytics service
   - Set up alerts for success rate <95%

---

## Changelog

### 2025-10-23: Bug Fixes & Optimizations

**9 critical fixes applied:**

1. **Fixed focus timer memory leak** - Use Set to track all timers, clear all on cleanup
2. **Fixed race condition in withRefreshLock** - Atomic check-and-set prevents concurrent refreshes
3. **Fixed success rate calculation** - AttemptId pairing ensures accurate metrics (success/completed)
4. **Added cookie value validation** - hasAuthCookie now verifies cookie has valid tokens
5. **Added cookie guard to initial session check** - Consistent with other refresh triggers
6. **Fixed hardcoded cookie name in Playwright tests** - Derives from NEXT_PUBLIC_SUPABASE_URL
7. **Fixed error serialization** - Errors properly serialized for production logging (no circular refs)
8. **Optimized metrics cleanup** - O(n) splice instead of O(n²) shift loop
9. **Added wake debounce** - 1000ms window prevents simultaneous refresh spam on iOS

**Impact:**
- More reliable session refresh (no race conditions)
- Accurate telemetry metrics (paired attemptIds)
- Better performance (optimized cleanup, debounced refreshes)
- Production-ready error logging (serialized, no PII)

---

**Last Updated:** 2025-10-23
**Configuration Version:** JWT Expiry 3600s, Rotation Enabled, Reuse Interval 10s
