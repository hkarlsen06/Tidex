import "server-only";
import { cache } from "react";
import { cacheTag } from "next/cache";
import { Effect } from "effect";
import { verifySession } from "@/data-access/auth";
import { JobsService } from "@/lib/services/jobs";
import { JobsLive } from "@/lib/layers/app";
import { invalidateUserCache } from "@/data-access/cache";
import type { Job } from "@/lib/payroll";

export type { Job };

export type CreateJobInput = {
  name: string;
  color?: string | null;
  is_default?: boolean;
  sort_order?: number;
  payroll_day?: number | null;
  half_tax_month?: number | null;
  monthly_goal?: number | null;
};

export type UpdateJobInput = {
  name?: string;
  color?: string | null;
  is_default?: boolean;
  sort_order?: number;
  payroll_day?: number | null;
  half_tax_month?: number | null;
  monthly_goal?: number | null;
  archived_at?: string | null;
};

async function runJobsEffect<A>(effect: Effect.Effect<A, any, JobsService>) {
  return await Effect.runPromise(effect.pipe(Effect.provide(JobsLive), Effect.scoped));
}

export const getUserJobs = cache(async (userId: string, options?: { includeArchived?: boolean }): Promise<Job[]> => {
  "use cache: private";
  const { user } = await verifySession();
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  cacheTag(`user-${userId}`, "user-jobs");

  const jobs = await runJobsEffect(
    Effect.gen(function* () {
      const service = yield* JobsService;
      return yield* service.getJobs(userId, options);
    })
  );

  return [...jobs];
});

export const getDefaultJob = cache(async (userId: string): Promise<Job | null> => {
  "use cache: private";
  const { user } = await verifySession();
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  cacheTag(`user-${userId}`, "user-jobs");

  return await runJobsEffect(
    Effect.gen(function* () {
      const service = yield* JobsService;
      return yield* service.getDefaultJob(userId);
    })
  );
});

export async function createJob(userId: string, input: CreateJobInput): Promise<Job> {
  const { user } = await verifySession();
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  const created = await runJobsEffect(
    Effect.gen(function* () {
      const service = yield* JobsService;
      return yield* service.createJob(userId, input);
    })
  );

  invalidateUserCache(userId);
  return created;
}

export async function updateJob(userId: string, jobId: string, input: UpdateJobInput): Promise<Job> {
  const { user } = await verifySession();
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  const updated = await runJobsEffect(
    Effect.gen(function* () {
      const service = yield* JobsService;
      return yield* service.updateJob(userId, jobId, input);
    })
  );

  invalidateUserCache(userId);
  return updated;
}

export async function archiveJob(userId: string, jobId: string): Promise<Job> {
  const { user } = await verifySession();
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  const archived = await runJobsEffect(
    Effect.gen(function* () {
      const service = yield* JobsService;
      return yield* service.archiveJob(userId, jobId);
    })
  );

  invalidateUserCache(userId);
  return archived;
}

export async function deleteJob(userId: string, jobId: string): Promise<void> {
  const { user } = await verifySession();
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  await runJobsEffect(
    Effect.gen(function* () {
      const service = yield* JobsService;
      return yield* service.deleteJob(userId, jobId);
    })
  );

  invalidateUserCache(userId);
}
