#!/usr/bin/env node

/**
 * Screenshot capture script for PWA manifest
 * Captures screenshots of the app at specified dimensions
 *
 * Usage: node scripts/capture-screenshots.mjs
 *
 * Prerequisites:
 * - Dev server running on http://localhost:3000
 * - Playwright installed (npx playwright install chromium)
 */

import { chromium } from 'playwright';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = 'http://localhost:3000';
const OUTPUT_DIR = join(__dirname, '../public/screenshots');

// Use English locale for screenshots
const LOCALE = 'en';

const screenshots = [
  {
    name: 'mobile-home',
    url: `${BASE_URL}/${LOCALE}`,
    width: 750,
    height: 1334,
    description: 'Home screen (mobile)',
  },
  {
    name: 'mobile-shifts',
    url: `${BASE_URL}/${LOCALE}/shifts`,
    width: 750,
    height: 1334,
    description: 'Shifts page (mobile)',
  },
  {
    name: 'mobile-stats',
    url: `${BASE_URL}/${LOCALE}/stats`,
    width: 750,
    height: 1334,
    description: 'Statistics page (mobile)',
  },
  {
    name: 'desktop-home',
    url: `${BASE_URL}/${LOCALE}`,
    width: 1920,
    height: 1080,
    description: 'Home screen (desktop)',
  },
];

async function captureScreenshots() {
  console.log('🎬 Starting screenshot capture...\n');

  const browser = await chromium.launch({
    headless: true,
  });

  try {
    for (const screenshot of screenshots) {
      console.log(`📸 Capturing: ${screenshot.description}`);
      console.log(`   URL: ${screenshot.url}`);
      console.log(`   Size: ${screenshot.width}x${screenshot.height}`);

      const context = await browser.newContext({
        viewport: { width: screenshot.width, height: screenshot.height },
        deviceScaleFactor: 2, // Retina display
        colorScheme: 'dark', // Use dark mode for screenshots
      });

      const page = await context.newPage();

      // Navigate to page
      await page.goto(screenshot.url, {
        waitUntil: 'networkidle',
        timeout: 30000,
      });

      // Wait a bit for any animations to settle
      await page.waitForTimeout(2000);

      // Take screenshot
      const outputPath = join(OUTPUT_DIR, `${screenshot.name}.png`);
      await page.screenshot({
        path: outputPath,
        type: 'png',
        fullPage: false,
      });

      console.log(`   ✅ Saved to: ${outputPath}\n`);

      await context.close();
    }

    console.log('✨ All screenshots captured successfully!');
  } catch (error) {
    console.error('❌ Error capturing screenshots:', error);
    throw error;
  } finally {
    await browser.close();
  }
}

// Run the capture
captureScreenshots().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
