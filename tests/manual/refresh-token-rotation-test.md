# Manual Test: Single-Use Refresh Token Rotation

This document describes how to manually verify that refresh tokens are single-use and cannot be reused after a successful refresh.

## Test Configuration

From `supabase/config.toml`:
- `enable_refresh_token_rotation = true` ✅
- `refresh_token_reuse_interval = 10` (seconds)

This means:
1. Each refresh returns a NEW refresh token
2. The old refresh token is invalidated immediately
3. There's a 10-second grace period where the old token can be reused (to handle concurrent requests)

---

## Test Procedure

### Prerequisites
1. Start the dev server: `npm run dev`
2. Open browser DevTools
3. Clear all cookies and storage
4. Have Network tab open and filtered to "token"

### Step 1: Login and Capture Initial Tokens

1. Navigate to `http://localhost:3000/login`
2. Login with valid credentials
3. Open DevTools → Application → Cookies → `http://localhost:3000`
4. Find cookie named `sb-<project-ref>-auth-token`
5. Copy the entire cookie value (JSON object)
6. Parse the JSON and note:
   - `access_token` (JWT starting with `eyJ...`)
   - `refresh_token` (UUID or long string)
   - `expires_at` (Unix timestamp)

**Example:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "abc123-original-refresh-token",
  "expires_at": 1709123456
}
```

---

### Step 2: Trigger First Refresh

1. In DevTools Console, run:
   ```javascript
   // Trigger visibilitychange to force session check
   Object.defineProperty(document, 'visibilityState', { value: 'hidden', writable: true });
   document.dispatchEvent(new Event('visibilitychange'));

   await new Promise(r => setTimeout(r, 500));

   Object.defineProperty(document, 'visibilityState', { value: 'visible', writable: true });
   document.dispatchEvent(new Event('visibilitychange'));
   ```

2. Watch Network tab for:
   - POST request to `/token?grant_type=refresh_token`
   - Status: `200 OK`
   - Response body contains:
     - `access_token` (new JWT)
     - `refresh_token` (NEW token, different from original)

3. Extract the NEW refresh token from the response:
   ```json
   {
     "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
     "refresh_token": "xyz789-new-refresh-token"  ← DIFFERENT from original!
   }
   ```

**Expected:**
- ✅ Cookie updated with new `access_token` and `refresh_token`
- ✅ Console shows: `✅ [SESSION TELEMETRY] session_refresh_success`

---

### Step 3: Attempt to Reuse Old Refresh Token (Should Fail)

1. In DevTools Console, manually call Supabase refresh with the OLD token:
   ```javascript
   // Import the Supabase client
   const { supabase } = await import('@/lib/supabase/browser');

   // Get current session (to extract old refresh token from previous step)
   const oldRefreshToken = "abc123-original-refresh-token"; // From Step 1

   // Manually trigger refresh with OLD token
   const response = await fetch('https://<your-supabase-url>/auth/v1/token?grant_type=refresh_token', {
     method: 'POST',
     headers: {
       'Content-Type': 'application/json',
       'apikey': '<your-publishable-key>'
     },
     body: JSON.stringify({
       refresh_token: oldRefreshToken
     })
   });

   const result = await response.json();
   console.log('Reuse attempt:', response.status, result);
   ```

2. **Expected Result:**
   - ❌ Status: `400 Bad Request`
   - ❌ Error: `{ "error": "invalid_grant", "error_description": "Invalid Refresh Token: Refresh Token Not Found" }`

3. **If you get 200 OK:**
   - ⚠️ You tested within the 10-second reuse window
   - Wait 15 seconds and try again
   - Should fail after the reuse window expires

---

### Step 4: Verify New Token Works

1. In DevTools Console:
   ```javascript
   const { supabase } = await import('@/lib/supabase/browser');
   const { data, error } = await supabase.auth.getSession();
   console.log('Current session valid:', !!data.session, error);
   ```

2. **Expected:**
   - ✅ `Current session valid: true`
   - ✅ No error
   - ✅ Access token matches the NEW token from Step 2

---

## Test Results Template

Copy this template and fill in your results:

```
### Test Execution: YYYY-MM-DD HH:MM

**Environment:** [Development / Production]
**Browser:** [Chrome / Safari / etc.]

**Step 1: Initial Login**
- ✅ Login successful
- ✅ Refresh token captured: `abc123...` (first 10 chars)

**Step 2: First Refresh**
- ✅ Refresh request sent
- ✅ Status: 200 OK
- ✅ New refresh token received: `xyz789...`
- ✅ Cookie updated

**Step 3: Reuse Old Token**
- ⏱️ Time since first refresh: 15 seconds (outside reuse window)
- ❌ Status: 400 Bad Request
- ❌ Error: "Invalid Refresh Token: Refresh Token Not Found"
- ✅ Correctly rejected old token

**Step 4: New Token Works**
- ✅ Session valid with new token
- ✅ No errors

**Conclusion:** ✅ Single-use refresh token rotation working correctly
```

---

## Troubleshooting

### Issue: Old token still works after 15 seconds
**Cause:** `refresh_token_reuse_interval` may be set higher than 10 seconds
**Solution:** Check `supabase/config.toml` → `refresh_token_reuse_interval`

### Issue: Both tokens fail
**Cause:** Concurrent refresh requests invalidated both tokens
**Solution:** Clear cookies, login again, and re-test

### Issue: No refresh request in Network tab
**Cause:** Tokens haven't expired yet (still valid for 1 hour)
**Solution:**
- Manually corrupt the access token in the cookie
- OR wait for token to expire
- OR trigger refresh by simulating wake events

---

## Automated Test (Future)

See `tests/e2e/auth-wake-refresh.spec.ts` for automated Playwright test skeleton.

**Note:** Automated testing of refresh token rotation requires:
1. Real Supabase credentials (not mocked)
2. Ability to capture network responses
3. Time-based assertions (reuse window)

Current E2E test focuses on wake-refresh mechanics only.

---

## References

- Supabase Docs: [Refresh Token Rotation](https://supabase.com/docs/guides/auth/sessions/refresh-token-rotation)
- Config: [supabase/config.toml:131-134](../../supabase/config.toml)
- Code: [lib/auth/session-telemetry.ts](../../lib/auth/session-telemetry.ts)
