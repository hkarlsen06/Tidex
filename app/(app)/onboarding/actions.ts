"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

interface OnboardingSettings {
  use_preset: boolean;
  current_wage_level: number | null;
  custom_wage: number | null;
  custom_bonuses: { rules: any[] } | null;
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

  // Upsert user_settings
  const settingsData = {
    user_id: user.id,
    use_preset: settings.use_preset,
    current_wage_level: settings.current_wage_level,
    custom_wage: settings.custom_wage,
    custom_bonuses: settings.custom_bonuses,
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
