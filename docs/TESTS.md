# Auth Stability Tests - Execution Guide

This document describes how to run and interpret the test suite for auth session stability fixes.

---

## Prerequisites

### 1. Install Test Dependencies

```bash
npm install -D @playwright/test
npx playwright install
```

### 2. Configure Test Environment

Create a `.env.test` file (or add to existing `.env.local`):

```bash
# Test user credentials (create a test account in your Supabase project)
TEST_USER_EMAIL=test@example.com
TEST_USER_PASSWORD=YourTestPassword123!

# Use same Supabase config as development
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your-anon-key
NEXT_PUBLIC_SUPABASE_REDIRECT_URL=http://localhost:3000/auth/callback
```

**Important**: Create a dedicated test user account in your Supabase dashboard:
1. Go to Supabase Dashboard → Authentication → Users
2. Add User → Create new user with email/password
3. Confirm the user (if auto-confirm is disabled)
4. Use these credentials in `.env.test`

---

## Running Tests

### E2E Tests (Playwright)

#### Run all auth stability tests:
```bash
npx playwright test tests/e2e/auth-stability.spec.ts
```

#### Run tests in UI mode (recommended for debugging):
```bash
npx playwright test tests/e2e/auth-stability.spec.ts --ui
```

#### Run specific test:
```bash
# Run only the theme toggle test
npx playwright test tests/e2e/auth-stability.spec.ts -g "theme toggle"

# Run only the rapid navigation test
npx playwright test tests/e2e/auth-stability.spec.ts -g "rapid route"
```

#### Run tests in headed mode (see browser):
```bash
npx playwright test tests/e2e/auth-stability.spec.ts --headed
```

#### Debug a failing test:
```bash
npx playwright test tests/e2e/auth-stability.spec.ts --debug
```

---

## Test Descriptions

### Test 1: Session Stability After Theme Toggle + Navigation

**Purpose**: Verifies that switching theme and navigating to `/shifts` doesn't invalidate session.

**Steps**:
1. Login with test credentials
2. Toggle theme (dark ↔ light)
3. Navigate to `/shifts`
4. Wait 10 seconds (allows token refresh to occur)
5. Verify still authenticated (not redirected to `/login`)
6. Verify no "Invalid Refresh Token" errors in console

**Expected Output**:
```
✓ should maintain session after theme toggle and navigation to /shifts (15s)
```

**What it tests**:
- Single client instance (no race conditions)
- Theme changes don't touch auth storage
- Token refresh doesn't cause logout

---

### Test 2: Rapid Route Navigation

**Purpose**: Verifies session stability under rapid page transitions.

**Steps**:
1. Login with test credentials
2. Navigate between `/`, `/shifts`, `/settings` (5 complete cycles)
3. End on `/shifts`
4. Verify no console errors
5. Verify still authenticated

**Expected Output**:
```
✓ should maintain session during rapid route navigation (8s)
```

**What it tests**:
- No race conditions during rapid SSR requests
- Reduced `auth.getUser()` overhead prevents token refresh conflicts

---

### Test 3: Auth Event Logging

**Purpose**: Verifies global auth event logging is working.

**Steps**:
1. Login with test credentials
2. Capture console logs containing `[SUPABASE AUTH]`
3. Verify at least one auth event was logged
4. Verify `SIGNED_IN` or `INITIAL_SESSION` event was captured

**Expected Output**:
```
✓ should log auth state changes properly (3s)
```

**What it tests**:
- Global logging is active
- Only one subscription (singleton client)

---

### Test 4: Multi-Tab Session Stability

**Purpose**: Verifies no session conflicts when using multiple tabs.

**Steps**:
1. Open first tab, login
2. Open second tab, navigate to `/shifts`
3. Navigate both tabs independently
4. Verify both remain authenticated

**Expected Output**:
```
✓ should handle multiple tabs without session conflicts (6s)
```

**What it tests**:
- Shared singleton client works across browser contexts
- No storage corruption between tabs

---

## Interpreting Results

### ✅ All Tests Pass

```
Running 4 tests using 1 worker

  ✓ should maintain session after theme toggle and navigation to /shifts (15s)
  ✓ should maintain session during rapid route navigation (8s)
  ✓ should log auth state changes properly (3s)
  ✓ should handle multiple tabs without session conflicts (6s)

  4 passed (32s)
```

**This means**: Auth stability fixes are working correctly. You can deploy to production.

---

### ❌ Test Failures

#### Failure: "Invalid Refresh Token" error detected

```
Error: expect(hasInvalidTokenError).toBe(false)
Expected: false
Received: true
```

**Diagnosis**:
- Singleton pattern not working (multiple clients created)
- Storage corruption still occurring

**Debug steps**:
1. Check browser console in `--headed` mode
2. Look for multiple `[SUPABASE AUTH] INITIAL_SESSION` logs (should only be one)
3. Verify `lib/supabase/client.ts` singleton pattern is correct
4. Check for other components calling `createSupabaseBrowserClient()` outside singleton

---

#### Failure: Test redirected to `/login`

```
Error: expect(page).toHaveURL('/shifts')
Expected: http://localhost:3000/shifts
Received: http://localhost:3000/login
```

**Diagnosis**:
- Session not persisting
- Possible issue with Supabase storage configuration

**Debug steps**:
1. Check browser's localStorage for `sb-*` keys
2. Verify `persistSession: true` in client config
3. Check Supabase Dashboard → Auth settings for JWT expiry
4. Test manual login in browser (outside Playwright) to isolate issue

---

#### Failure: No auth events logged

```
Error: expect(authLogs.length).toBeGreaterThan(0)
Expected: > 0
Received: 0
```

**Diagnosis**:
- Global logging not working
- Possible issue with console capture

**Debug steps**:
1. Check `app/supabase-listener.tsx` has `console.log` statement
2. Run test in `--headed` mode and check browser DevTools console
3. Verify `SupabaseListener` component is mounted (check React DevTools)

---

## Manual Testing Checklist

In addition to automated tests, perform these manual checks:

### Pre-Deployment Checklist

- [ ] **Login flow**: Login with real credentials, verify successful redirect
- [ ] **Theme toggle**: Toggle dark/light mode 3x, verify no logout
- [ ] **Route navigation**: Navigate to all routes (`/`, `/shifts`, `/settings`, `/shifts/add`), verify no logout
- [ ] **Token refresh**: Wait 60 minutes after login, refresh page, verify still authenticated
- [ ] **Logout**: Click logout, verify redirect to `/login`
- [ ] **Browser console**: Check for `[SUPABASE AUTH]` logs on page load
- [ ] **Mobile Safari**: Repeat above tests on iOS device
- [ ] **Android Chrome**: Repeat above tests on Android device

### Expected Console Logs

After login, you should see:
```
[SUPABASE AUTH] SIGNED_IN { hasSession: true, userId: "abc-123-...", timestamp: "..." }
[SUPABASE AUTH] INITIAL_SESSION { hasSession: true, userId: "abc-123-...", timestamp: "..." }
```

After ~50 minutes (if JWT expiry is 1 hour), you should see:
```
[SUPABASE AUTH] TOKEN_REFRESHED { hasSession: true, userId: "abc-123-...", timestamp: "..." }
```

After logout:
```
[SUPABASE AUTH] SIGNED_OUT { hasSession: false, userId: undefined, timestamp: "..." }
```

**❌ BAD**: If you see unexpected `SIGNED_OUT` events during normal usage, something is still wrong.

---

## Continuous Integration (CI)

To run tests in CI (e.g., GitHub Actions):

### Example Workflow (`.github/workflows/test.yml`)

```yaml
name: E2E Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: '22'

      - name: Install dependencies
        run: npm ci

      - name: Install Playwright
        run: npx playwright install --with-deps

      - name: Run dev server
        run: npm run dev &
        env:
          NEXT_PUBLIC_SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: ${{ secrets.SUPABASE_KEY }}
          NEXT_PUBLIC_SUPABASE_REDIRECT_URL: http://localhost:3000/auth/callback

      - name: Wait for dev server
        run: npx wait-on http://localhost:3000

      - name: Run E2E tests
        run: npx playwright test tests/e2e/auth-stability.spec.ts
        env:
          TEST_USER_EMAIL: ${{ secrets.TEST_USER_EMAIL }}
          TEST_USER_PASSWORD: ${{ secrets.TEST_USER_PASSWORD }}

      - name: Upload test results
        if: failure()
        uses: actions/upload-artifact@v3
        with:
          name: playwright-report
          path: playwright-report/
```

**Required GitHub Secrets**:
- `SUPABASE_URL`
- `SUPABASE_KEY`
- `TEST_USER_EMAIL`
- `TEST_USER_PASSWORD`

---

## Troubleshooting

### Test hangs on login

**Symptom**: Test gets stuck waiting for redirect after login.

**Solution**:
1. Verify test credentials are correct
2. Check Supabase Dashboard → Authentication → Users to confirm user exists
3. Verify user is confirmed (check email confirmation status)
4. Try logging in manually in browser with same credentials

---

### "Target page, context or browser has been closed" error

**Symptom**: Test crashes with context closed error.

**Solution**:
1. Increase timeouts in test config:
```ts
test.setTimeout(60000); // 60 seconds
```
2. Check if `npm run dev` is running and accessible at `http://localhost:3000`

---

### Tests pass locally but fail in CI

**Symptom**: Tests work on your machine but fail in GitHub Actions.

**Solution**:
1. Verify all environment variables are set in GitHub Secrets
2. Check CI logs for `NEXT_PUBLIC_SUPABASE_URL` and other env vars
3. Ensure test user exists in the Supabase project used by CI
4. Add `--retries=2` to Playwright command for flaky network issues

---

## Performance Benchmarks

Expected test execution times (on M1 MacBook Pro):

| Test | Duration |
|------|----------|
| Theme toggle + navigation | ~15s |
| Rapid route navigation | ~8s |
| Auth event logging | ~3s |
| Multi-tab stability | ~6s |
| **Total** | **~32s** |

In CI (GitHub Actions), expect ~50-60s total due to slower VM.

---

## Next Steps After Tests Pass

1. **Deploy to staging**: Run tests against staging environment
2. **Monitor production logs**: Watch for `[SUPABASE AUTH]` logs and any errors
3. **Set up error tracking**: Integrate Sentry/LogRocket to catch any auth errors in production
4. **User acceptance testing**: Have 2-3 real users test auth flows on mobile devices

---

## Additional Resources

- [Playwright Documentation](https://playwright.dev/docs/intro)
- [Supabase Auth Documentation](https://supabase.com/docs/guides/auth)
- [Project REPORT.md](REPORT.md) - Full root cause analysis
- [Project Issue Tracker](https://github.com/your-repo/issues) - Report new auth issues here

---

**Document Version**: 1.0
**Last Updated**: 2025-10-08
**Author**: Claude Code
