"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { PRESET_WAGE_RATES, PRESET_SUPPLEMENT_RULES } from "@/lib/payroll";

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

  // Upsert user_settings (without wage fields - those go to wage_snapshots)
  const settingsData = {
    user_id: user.id,
    pause_deduction_enabled: settings.pause_deduction_enabled,
    pause_deduction_method: settings.pause_deduction_method,
    pause_threshold_hours: settings.pause_threshold_hours,
    pause_deduction_minutes: settings.pause_deduction_minutes,
    tax_deduction_enabled: settings.tax_deduction_enabled,
    tax_percentage: settings.tax_percentage,
    payroll_day: settings.payroll_day,
    theme: settings.theme,
    default_shifts_view: settings.default_shifts_view,
    monthly_goal: settings.monthly_goal,
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

  // Create initial wage snapshot
  const today = new Date().toISOString().split('T')[0];
  const hourly_wage = settings.use_preset
    ? PRESET_WAGE_RATES[settings.current_wage_level!]
    : settings.custom_wage!;

  const supplements = settings.use_preset
    ? { rules: PRESET_SUPPLEMENT_RULES }
    : (settings.custom_supplements || { rules: [] });

  const { error: snapshotError } = await supabase
    .from("wage_snapshots")
    .insert({
      user_id: user.id,
      from_date: today,
      hourly_wage,
      wage_level: settings.use_preset ? settings.current_wage_level : null,
      supplements,
    });

  if (snapshotError) {
    throw new Error(`Failed to create wage snapshot: ${snapshotError.message}`);
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

  // Revalidate paths
  revalidatePath("/");
  revalidatePath("/onboarding");

  return { success: true };
}
