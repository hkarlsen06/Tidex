"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getLatestTariffVersion } from "@/data-access/tariff";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";

// Default tariff type for HK Retail agreement
const DEFAULT_TARIFF_TYPE = "hk_retail";

interface OnboardingSettings {
  use_preset: boolean;
  current_wage_level: number | null;
  tariff_type_id: string | null;
  custom_wage: number | null;
  custom_supplements: { rules: any[] } | null;
  pause_deduction_enabled: boolean;
  pause_deduction_method: string | null;
  pause_threshold_hours: number | null;
  pause_deduction_minutes: number | null;
  tax_deduction_enabled: boolean;
  tax_percentage: number | null;
  payroll_day: number | null;
  theme: string;
  default_shifts_view: string;
  monthly_goal: number | null;
  currency: string;
}

export async function completeOnboarding(settings: OnboardingSettings) {
  const supabase = await createSupabaseServerClient();

  // Use getClaims() for performance - parses JWT locally without network request
  const { data: authData, error: authError } = await supabase.auth.getClaims();

  if (authError || !authData?.claims) {
    throw new Error("User not authenticated");
  }

  const userId = authData.claims.sub;

  // Upsert user_settings (tax/break deduction fields moved to wage_snapshots)
  const settingsData = {
    user_id: userId,
    payroll_day: settings.payroll_day,
    theme: settings.theme,
    default_shifts_view: settings.default_shifts_view,
    monthly_goal: settings.monthly_goal,
    currency: settings.currency,
    updated_at: new Date().toISOString(),
  };

  const { error: settingsError } = await supabase
    .from("user_settings")
    .upsert(settingsData as any, {
      onConflict: "user_id",
    });

  if (settingsError) {
    throw new Error(`Failed to save settings: ${settingsError.message}`);
  }

  // Create or update baseline wage snapshot (from_date = null)
  // This serves as the fallback for all shifts that don't match a dated snapshot

  let hourly_wage: number;
  let supplements: { rules: any[] };

  // Determine which tariff type to use (selected or default)
  const effectiveTariffTypeId = settings.tariff_type_id ?? DEFAULT_TARIFF_TYPE;

  if (settings.use_preset) {
    // Fetch latest tariff version - required for preset wage
    const tariffVersion = await getLatestTariffVersion(effectiveTariffTypeId);
    if (!tariffVersion) {
      throw new Error("Failed to load tariff rates. Please try again.");
    }

    hourly_wage = tariffVersion.rates[settings.current_wage_level!];
    supplements = { rules: tariffVersion.supplements?.rules ?? [] };
  } else {
    hourly_wage = settings.custom_wage!;
    supplements = settings.custom_supplements || { rules: [] };
  }

  // Check if baseline snapshot already exists (exclude soft-deleted)
  const { data: existingBaseline } = await supabase
    .from("wage_snapshots")
    .select("id")
    .eq("user_id", userId)
    .is("from_date", null)
    .is("deleted_at", null) // Exclude soft-deleted snapshots
    .maybeSingle();

  // Prepare snapshot data with tax/break deduction settings
  const snapshotData = {
    hourly_wage,
    wage_level: settings.use_preset ? settings.current_wage_level : null,
    tariff_type_id: settings.use_preset ? effectiveTariffTypeId : null,
    supplements,
    // Tax settings (moved from user_settings)
    tax_enabled: settings.tax_deduction_enabled,
    tax_percentage: settings.tax_percentage ?? 0,
    // Break deduction settings (moved from user_settings)
    break_enabled: settings.pause_deduction_enabled,
    break_method: settings.pause_deduction_method ?? "proportional",
    break_threshold_hours: settings.pause_threshold_hours ?? 5.5,
    break_deduction_minutes: settings.pause_deduction_minutes ?? 30,
  };

  if (existingBaseline) {
    // Update existing baseline snapshot
    const { error: updateError } = await supabase
      .from("wage_snapshots")
      .update(snapshotData)
      .eq("id", existingBaseline.id);

    if (updateError) {
      throw new Error(`Failed to update wage snapshot: ${updateError.message}`);
    }
  } else {
    // Create new baseline snapshot
    const { error: insertError } = await supabase
      .from("wage_snapshots")
      .insert({
        user_id: userId,
        from_date: null, // Baseline snapshot (grunntariff)
        ...snapshotData,
      });

    if (insertError) {
      throw new Error(`Failed to create wage snapshot: ${insertError.message}`);
    }
  }

  // Mark onboarding as complete in user metadata
  const { error: updateError } = await supabase.auth.updateUser({
    data: {
      finishedOnboarding: true,
    },
  });

  if (updateError) {
    throw new Error(`Failed to update user metadata: ${updateError.message}`);
  }

  // Note: We don't call refreshSession() here because server-side cookie updates
  // race with subsequent navigation. Instead, the client calls refreshSession()
  // after this action returns, which updates cookies client-side before navigating.

  // Invalidate cache since settings and wage snapshot were created/updated
  invalidateAndRevalidate(userId);

  return { success: true };
}
