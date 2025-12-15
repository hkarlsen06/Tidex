"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PRESET_WAGE_RATES, PRESET_SUPPLEMENT_RULES } from "@/lib/payroll";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";

interface OnboardingSettings {
  use_preset: boolean;
  current_wage_level: number | null;
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

  // Get current user
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    throw new Error("User not authenticated");
  }

  // Upsert user_settings (tax/break deduction fields moved to wage_snapshots)
  const settingsData = {
    user_id: user.id,
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
  const hourly_wage = settings.use_preset
    ? PRESET_WAGE_RATES[settings.current_wage_level!]
    : settings.custom_wage!;

  const supplements = settings.use_preset
    ? { rules: PRESET_SUPPLEMENT_RULES }
    : (settings.custom_supplements || { rules: [] });

  // Check if baseline snapshot already exists
  const { data: existingBaseline } = await supabase
    .from("wage_snapshots")
    .select("id")
    .eq("user_id", user.id)
    .is("from_date", null)
    .maybeSingle();

  // Prepare snapshot data with tax/break deduction settings
  const snapshotData = {
    hourly_wage,
    wage_level: settings.use_preset ? settings.current_wage_level : null,
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
        user_id: user.id,
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

  // Invalidate cache since settings and wage snapshot were created/updated
  invalidateAndRevalidate(user.id);

  return { success: true };
}
