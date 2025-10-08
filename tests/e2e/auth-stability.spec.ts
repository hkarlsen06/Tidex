/**
 * E2E Tests for Auth Session Stability
 *
 * These tests verify that user sessions remain stable during:
 * - Theme switching (dark/light mode)
 * - Route navigation (especially to /shifts)
 * - Rapid page transitions
 *
 * To run these tests:
 * 1. Install Playwright: npm install -D @playwright/test
 * 2. Run tests: npx playwright test tests/e2e/auth-stability.spec.ts
 */

import { test, expect } from '@playwright/test';

// Test user credentials (update with your test credentials)
const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'test@example.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'testpassword123';

test.describe('Auth Session Stability', () => {
  test.beforeEach(async ({ page }) => {
    // Start fresh
    await page.goto('/login');
  });

  test('should maintain session after theme toggle and navigation to /shifts', async ({ page, context }) => {
    // 1. Login
    await page.fill('input[name="email"]', TEST_EMAIL);
    await page.fill('input[name="password"]', TEST_PASSWORD);
    await page.click('button[type="submit"]');

    // Wait for redirect to home
    await page.waitForURL('/');

    // 2. Toggle to dark mode
    const themeToggle = page.locator('button:has-text("Mørk modus"), button:has-text("Lys modus")');
    await themeToggle.click();

    // Wait a moment for theme to apply
    await page.waitForTimeout(500);

    // 3. Navigate to /shifts
    await page.goto('/shifts');
    await page.waitForLoadState('networkidle');

    // 4. Wait 10 seconds to allow for potential token refresh
    await page.waitForTimeout(10000);

    // 5. Verify session is still valid
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    // Check that we're still on /shifts (not redirected to /login)
    await expect(page).toHaveURL('/shifts');

    // Verify no "Invalid Refresh Token" errors in console
    const hasInvalidTokenError = consoleErrors.some(err =>
      err.includes('Invalid Refresh Token') || err.includes('Refresh Token Not Found')
    );
    expect(hasInvalidTokenError).toBe(false);

    // Verify session is valid by checking for authenticated content
    // (adjust selector based on your app's UI)
    await expect(page.locator('[data-testid="authenticated-content"]').or(page.locator('main'))).toBeVisible();
  });

  test('should maintain session during rapid route navigation', async ({ page }) => {
    // 1. Login
    await page.fill('input[name="email"]', TEST_EMAIL);
    await page.fill('input[name="password"]', TEST_PASSWORD);
    await page.click('button[type="submit"]');

    await page.waitForURL('/');

    // 2. Setup console error tracking
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    // 3. Rapidly navigate between routes
    for (let i = 0; i < 5; i++) {
      await page.goto('/');
      await page.waitForLoadState('domcontentloaded');

      await page.goto('/shifts');
      await page.waitForLoadState('domcontentloaded');

      await page.goto('/settings');
      await page.waitForLoadState('domcontentloaded');
    }

    // 4. Final check - should still be authenticated
    await page.goto('/shifts');
    await page.waitForLoadState('networkidle');

    // Verify no invalid token errors
    const hasInvalidTokenError = consoleErrors.some(err =>
      err.includes('Invalid Refresh Token') || err.includes('Refresh Token Not Found')
    );
    expect(hasInvalidTokenError).toBe(false);

    // Verify still on authenticated route
    await expect(page).toHaveURL('/shifts');
  });

  test('should log auth state changes properly', async ({ page }) => {
    // Track console logs for auth events
    const authLogs: string[] = [];
    page.on('console', (msg) => {
      const text = msg.text();
      if (text.includes('[SUPABASE AUTH]')) {
        authLogs.push(text);
      }
    });

    // Login
    await page.fill('input[name="email"]', TEST_EMAIL);
    await page.fill('input[name="password"]', TEST_PASSWORD);
    await page.click('button[type="submit"]');

    await page.waitForURL('/');
    await page.waitForTimeout(2000);

    // Verify auth events are being logged
    expect(authLogs.length).toBeGreaterThan(0);

    // Verify SIGNED_IN event was logged
    const hasSignedInEvent = authLogs.some(log =>
      log.includes('SIGNED_IN') || log.includes('INITIAL_SESSION')
    );
    expect(hasSignedInEvent).toBe(true);
  });

  test('should handle multiple tabs without session conflicts', async ({ browser }) => {
    const context = await browser.newContext();

    // Open first tab and login
    const page1 = await context.newPage();
    await page1.goto('/login');
    await page1.fill('input[name="email"]', TEST_EMAIL);
    await page1.fill('input[name="password"]', TEST_PASSWORD);
    await page1.click('button[type="submit"]');
    await page1.waitForURL('/');

    // Open second tab
    const page2 = await context.newPage();
    await page2.goto('/shifts');
    await page2.waitForLoadState('networkidle');

    // Navigate in both tabs
    await page1.goto('/shifts');
    await page2.goto('/settings');
    await page1.goto('/');

    // Both should still be authenticated
    await expect(page1).not.toHaveURL('/login');
    await expect(page2).not.toHaveURL('/login');

    await context.close();
  });
});
