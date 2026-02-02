/**
 * Legal Version API Route
 *
 * Returns the current terms and privacy policy version dates.
 * This is a public endpoint used by the iOS app to check if users
 * need to re-accept terms after an update.
 *
 * Response format:
 * {
 *   termsVersionDate: "2025-01-10",
 *   privacyVersionDate: "2025-01-10"
 * }
 */

import { NextResponse } from 'next/server';
import { legalNo } from '@/lib/i18n/dictionaries/legal.no';

export async function GET() {
  return NextResponse.json({
    termsVersionDate: legalNo.terms.lastUpdatedDate,
    privacyVersionDate: legalNo.privacy.lastUpdatedDate,
  });
}
