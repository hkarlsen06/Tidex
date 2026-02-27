'use server';

import { verifySession } from '@/data-access/auth';
import { updateJob } from '@/data-access/jobs';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';
import { logger } from '@/lib/logger';

type JobPaySettingsInput = {
  monthly_goal?: number | null;
  payroll_day?: number | null;
  half_tax_month?: number | null;
};

export async function updateJobPaySettingsAction(
  jobId: string | null | undefined,
  data: JobPaySettingsInput
) {
  const { user } = await verifySession();

  if (jobId) {
    await updateJob(user.id, jobId, {
      monthly_goal: data.monthly_goal ?? null,
      payroll_day: data.payroll_day ?? null,
      half_tax_month: data.half_tax_month ?? null,
    });
    invalidateAndRevalidate(user.id);
    return { success: true };
  }

  // Compatibility fallback during rollout: keep legacy user_settings writable.
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase
    .from('user_settings')
    .update({
      monthly_goal: data.monthly_goal ?? null,
      payroll_day: data.payroll_day ?? null,
      half_tax_month: data.half_tax_month ?? null,
    })
    .eq('user_id', user.id);

  if (error) {
    logger.error('Failed to update fallback pay settings:', error);
    throw error;
  }

  invalidateAndRevalidate(user.id);
  return { success: true };
}
