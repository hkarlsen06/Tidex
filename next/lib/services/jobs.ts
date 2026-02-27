import "server-only";
import { Context, Effect, Layer } from "effect";
import { AuthService } from "./auth";
import { SupabaseService } from "./supabase";
import {
  AuthError,
  DatabaseError,
  NotFoundError,
  SupabaseError,
  TimeoutError,
  ValidationError,
} from "../errors/tagged";
import type { Job } from "../payroll";

export type JobCreateInput = {
  readonly name: string;
  readonly color?: string | null;
  readonly is_default?: boolean;
  readonly sort_order?: number;
  readonly payroll_day?: number | null;
  readonly half_tax_month?: number | null;
  readonly monthly_goal?: number | null;
};

export type JobUpdateInput = {
  readonly name?: string;
  readonly color?: string | null;
  readonly is_default?: boolean;
  readonly sort_order?: number;
  readonly payroll_day?: number | null;
  readonly half_tax_month?: number | null;
  readonly monthly_goal?: number | null;
  readonly archived_at?: string | null;
};

export class JobsService extends Context.Tag("JobsService")<
  JobsService,
  {
    readonly getJobs: (
      userId: string,
      options?: { includeArchived?: boolean }
    ) => Effect.Effect<
      readonly Job[],
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    readonly getDefaultJob: (
      userId: string
    ) => Effect.Effect<
      Job | null,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    readonly createJob: (
      userId: string,
      input: JobCreateInput
    ) => Effect.Effect<
      Job,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError | ValidationError,
      never
    >;

    readonly updateJob: (
      userId: string,
      jobId: string,
      input: JobUpdateInput
    ) => Effect.Effect<
      Job,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    readonly archiveJob: (
      userId: string,
      jobId: string
    ) => Effect.Effect<
      Job,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    readonly deleteJob: (
      userId: string,
      jobId: string
    ) => Effect.Effect<
      void,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;
  }
>() {}

export const JobsServiceLive = Layer.effect(
  JobsService,
  Effect.gen(function* () {
    const auth = yield* AuthService;
    const supabase = yield* SupabaseService;

    const getJobs = (userId: string, options?: { includeArchived?: boolean }) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        const jobs = yield* supabase.query(
          async (client) => {
            let query = client
              .from("jobs")
              .select("*")
              .eq("user_id", userId)
              .is("deleted_at", null)
              .order("sort_order", { ascending: true })
              .order("created_at", { ascending: true });

            if (!options?.includeArchived) {
              query = query.is("archived_at", null);
            }

            return await query;
          },
          { retries: 2 }
        );

        return (jobs ?? []) as readonly Job[];
      });

    const getDefaultJob = (userId: string) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        const job = yield* supabase
          .query(
            async (client) =>
              await client
                .from("jobs")
                .select("*")
                .eq("user_id", userId)
                .eq("is_default", true)
                .is("deleted_at", null)
                .maybeSingle(),
            { retries: 2 }
          )
          .pipe(
            Effect.catchTag("DatabaseError", (error) => {
              if (error.code === "NO_DATA") {
                return Effect.succeed(null);
              }
              return Effect.fail(error);
            })
          );

        return job as Job | null;
      });

    const createJob = (userId: string, input: JobCreateInput) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        const name = input.name.trim();
        if (name.length === 0) {
          return yield* Effect.fail(
            new ValidationError({ message: "Job name cannot be empty" })
          );
        }

        const created = yield* supabase.query(
          async (client) =>
            await client
              .from("jobs")
              .insert({
                user_id: userId,
                name,
                color: input.color ?? null,
                is_default: input.is_default ?? false,
                sort_order: input.sort_order ?? 0,
                payroll_day: input.payroll_day ?? 15,
                half_tax_month: input.half_tax_month ?? null,
                monthly_goal: input.monthly_goal ?? 20000,
              })
              .select("*")
              .single(),
          { retries: 1 }
        );

        if (!created) {
          return yield* Effect.fail(new NotFoundError({ resource: "Job" }));
        }

        return created as Job;
      });

    const updateJob = (userId: string, jobId: string, input: JobUpdateInput) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        const patch = {
          ...input,
          ...(input.name !== undefined ? { name: input.name.trim() } : {}),
        };

        const updated = yield* supabase.query(
          async (client) =>
            await client
              .from("jobs")
              .update(patch)
              .eq("id", jobId)
              .eq("user_id", userId)
              .is("deleted_at", null)
              .select("*")
              .single(),
          { retries: 1 }
        );

        if (!updated) {
          return yield* Effect.fail(new NotFoundError({ resource: "Job", id: jobId }));
        }

        return updated as Job;
      });

    const archiveJob = (userId: string, jobId: string) =>
      updateJob(userId, jobId, { archived_at: new Date().toISOString(), is_default: false });

    const deleteJob = (userId: string, jobId: string) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        yield* supabase.query(
          async (client) =>
            await client
              .from("jobs")
              .update({ deleted_at: new Date().toISOString(), is_default: false })
              .eq("id", jobId)
              .eq("user_id", userId)
              .is("deleted_at", null),
          { retries: 1 }
        );
      });

    return {
      getJobs,
      getDefaultJob,
      createJob,
      updateJob,
      archiveJob,
      deleteJob,
    };
  })
);

export const withJobs = <A, E, R>(
  effect: Effect.Effect<A, E, R | JobsService>
): Effect.Effect<A, E, Exclude<R, JobsService> | AuthService | SupabaseService> =>
  Effect.provide(effect, JobsServiceLive);
