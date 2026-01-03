"use client";

import { HomeContent } from "./HomeContent";
import type { ShiftWithComputations, UserSettings } from "@/lib/payroll";
import type { PayoutTaxSettings } from "@/data-access/shifts";

type HomeContentWrapperProps = {
  shifts: ShiftWithComputations[];
  settings: UserSettings;
  payoutTaxSettings?: PayoutTaxSettings;
  cacheKey: string;
  preloadedMonths?: string[];
};

/**
 * Wrapper component for HomeContent.
 *
 * Note: We previously used a key based on selectedMonth to force remounts,
 * but this caused fetched months to be lost on every navigation. Now that
 * HomeContent uses proper reference equality checks (prevInitialShiftsRef)
 * to handle cacheComponents reveals, the key is no longer needed.
 */
export function HomeContentWrapper(props: HomeContentWrapperProps) {
  return <HomeContent {...props} />;
}
