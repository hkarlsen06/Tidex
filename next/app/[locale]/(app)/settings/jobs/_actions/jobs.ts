'use server';

import { verifySession } from '@/data-access/auth';
import {
  archiveJob,
  createJob,
  deleteJob,
  getUserJobs,
  updateJob,
  type CreateJobInput,
  type UpdateJobInput,
} from '@/data-access/jobs';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';
import type { Job } from '@/lib/payroll';

type ActionResult<T = void> = { success: true; data?: T } | { error: string };

function getActiveJobs(jobs: Job[]): Job[] {
  return jobs.filter((job) => !job.deleted_at && !job.archived_at);
}

async function setDefaultForUser(userId: string, jobId: string): Promise<ActionResult> {
  const supabase = await createSupabaseServerClient();

  const { data: target, error: targetError } = await supabase
    .from('jobs')
    .select('id, archived_at, deleted_at')
    .eq('id', jobId)
    .eq('user_id', userId)
    .maybeSingle();

  if (targetError || !target) {
    return { error: 'Fant ikke jobb.' };
  }

  if (target.deleted_at || target.archived_at) {
    return { error: 'Kan ikke sette arkivert eller slettet jobb som standard.' };
  }

  const { error: clearDefaultError } = await supabase
    .from('jobs')
    .update({ is_default: false })
    .eq('user_id', userId)
    .is('deleted_at', null)
    .is('archived_at', null)
    .neq('id', jobId);

  if (clearDefaultError) {
    return { error: clearDefaultError.message };
  }

  const { error: setDefaultError } = await supabase
    .from('jobs')
    .update({ is_default: true })
    .eq('id', jobId)
    .eq('user_id', userId)
    .is('deleted_at', null)
    .is('archived_at', null);

  if (setDefaultError) {
    return { error: setDefaultError.message };
  }

  invalidateAndRevalidate(userId);
  return { success: true };
}

export async function createJobAction(
  input: Omit<CreateJobInput, 'sort_order' | 'is_default'>
): Promise<ActionResult<Job>> {
  const { user } = await verifySession();
  const jobs = await getUserJobs(user.id, { includeArchived: true });
  const activeJobs = getActiveJobs(jobs);

  const name = input.name.trim();
  if (!name) {
    return { error: 'Jobbnavn kan ikke være tomt.' };
  }

  const nextSortOrder =
    activeJobs.length === 0
      ? 0
      : Math.max(...activeJobs.map((job) => job.sort_order ?? 0)) + 1;

  try {
    const created = await createJob(user.id, {
      ...input,
      name,
      sort_order: nextSortOrder,
      is_default: activeJobs.length === 0,
    });
    return { success: true, data: created };
  } catch (error: any) {
    return { error: error?.message ?? 'Kunne ikke opprette jobb.' };
  }
}

export async function updateJobAction(jobId: string, input: UpdateJobInput): Promise<ActionResult<Job>> {
  const { user } = await verifySession();

  if (input.name !== undefined && input.name.trim().length === 0) {
    return { error: 'Jobbnavn kan ikke være tomt.' };
  }

  try {
    const updated = await updateJob(user.id, jobId, {
      ...input,
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
    });
    return { success: true, data: updated };
  } catch (error: any) {
    return { error: error?.message ?? 'Kunne ikke oppdatere jobb.' };
  }
}

export async function setDefaultJobAction(jobId: string): Promise<ActionResult> {
  const { user } = await verifySession();
  return setDefaultForUser(user.id, jobId);
}

export async function reorderJobAction(
  jobId: string,
  direction: 'up' | 'down'
): Promise<ActionResult> {
  const { user } = await verifySession();
  const jobs = await getUserJobs(user.id, { includeArchived: false });
  const activeJobs = getActiveJobs(jobs);
  const index = activeJobs.findIndex((job) => job.id === jobId);

  if (index === -1) {
    return { error: 'Fant ikke jobb.' };
  }

  const swapIndex = direction === 'up' ? index - 1 : index + 1;
  if (swapIndex < 0 || swapIndex >= activeJobs.length) {
    return { success: true };
  }

  const current = activeJobs[index];
  const other = activeJobs[swapIndex];

  try {
    await updateJob(user.id, current.id, { sort_order: other.sort_order ?? 0 });
    await updateJob(user.id, other.id, { sort_order: current.sort_order ?? 0 });
    return { success: true };
  } catch (error: any) {
    return { error: error?.message ?? 'Kunne ikke endre rekkefolge.' };
  }
}

export async function archiveJobAction(jobId: string): Promise<ActionResult> {
  const { user } = await verifySession();
  const jobs = await getUserJobs(user.id, { includeArchived: true });
  const activeJobs = getActiveJobs(jobs);
  const target = activeJobs.find((job) => job.id === jobId);

  if (!target) {
    return { error: 'Fant ikke jobb.' };
  }

  if (activeJobs.length <= 1) {
    return { error: 'Du kan ikke arkivere siste aktive jobb.' };
  }

  if (target.is_default) {
    return { error: 'Sett en annen jobb som standard for du arkiverer denne.' };
  }

  try {
    await archiveJob(user.id, jobId);
    return { success: true };
  } catch (error: any) {
    return { error: error?.message ?? 'Kunne ikke arkivere jobb.' };
  }
}

export async function restoreJobAction(jobId: string): Promise<ActionResult<Job>> {
  const { user } = await verifySession();
  const jobs = await getUserJobs(user.id, { includeArchived: true });
  const activeJobs = getActiveJobs(jobs);

  const nextSortOrder =
    activeJobs.length === 0
      ? 0
      : Math.max(...activeJobs.map((job) => job.sort_order ?? 0)) + 1;

  try {
    const restored = await updateJob(user.id, jobId, {
      archived_at: null,
      sort_order: nextSortOrder,
    });
    return { success: true, data: restored };
  } catch (error: any) {
    return { error: error?.message ?? 'Kunne ikke gjenopprette jobb.' };
  }
}

export async function deleteJobAction(jobId: string): Promise<ActionResult> {
  const { user } = await verifySession();
  const jobs = await getUserJobs(user.id, { includeArchived: true });
  const nonDeletedJobs = jobs.filter((job) => !job.deleted_at);
  const activeJobs = getActiveJobs(jobs);
  const target = nonDeletedJobs.find((job) => job.id === jobId);

  if (!target) {
    return { error: 'Fant ikke jobb.' };
  }

  const isActiveTarget = !target.archived_at;
  if (isActiveTarget && activeJobs.length <= 1) {
    return { error: 'Du kan ikke slette siste aktive jobb.' };
  }

  if (target.is_default) {
    return { error: 'Sett en annen jobb som standard for du sletter denne.' };
  }

  try {
    await deleteJob(user.id, jobId);
    return { success: true };
  } catch (error: any) {
    return { error: error?.message ?? 'Kunne ikke slette jobb.' };
  }
}
