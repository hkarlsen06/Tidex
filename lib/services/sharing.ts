/**
 * Sharing Service Layer
 *
 * Effect-based service for shift sharing functionality with:
 * - Share management (create, delete, list shares)
 * - User lookup by email/phone (admin operations)
 * - Subscription tier limit enforcement
 *
 * Usage:
 * ```typescript
 * const program = Effect.gen(function* () {
 *   const sharing = yield* SharingService
 *   const sharers = yield* sharing.getUsersWhoSharedWithMe(userId)
 *   return sharers
 * }).pipe(
 *   Effect.provide(SharingServiceLive)
 * )
 * ```
 */

import "server-only";
import { Context, Effect, Layer } from "effect";
import { AuthService } from "./auth";
import { SupabaseService } from "./supabase";
import { SubscriptionService } from "./subscription";
import {
  DatabaseError,
  AuthError,
  NotFoundError,
  TimeoutError,
  SupabaseError,
  ConflictError,
  ValidationError,
} from "../errors/tagged";
import { logger } from "../logger";
import { createClient } from "@supabase/supabase-js";

/**
 * Notification frequency options for a share relationship
 * - instant: Notifications sent immediately (within 1-2 minutes)
 * - summary: Daily digest at user-defined time (default 18:00)
 * - muted: No notifications from this sender
 */
export type NotificationFrequency = "instant" | "summary" | "muted";

/**
 * User who has shared their shifts with the current user
 */
export type SharedUser = {
  readonly id: string;
  readonly email: string | null;
  readonly phone: string | null;
  readonly firstName: string | null;
  readonly profilePictureUrl: string | null;
  /** OAuth provider avatar (Google, etc.) - used as fallback when profilePictureUrl is null */
  readonly oauthAvatarUrl: string | null;
  readonly sharedAt: string;
  /** Whether this user allows you to see their earnings (true) or only hours (false) */
  readonly showEarnings: boolean;
  /** Notification frequency for this sharer's notifications (instant/summary/muted) */
  readonly notificationFrequency: NotificationFrequency;
};

/**
 * User the current user has shared their shifts with
 */
export type ShareRecipient = {
  readonly id: string;
  readonly email: string | null;
  readonly phone: string | null;
  readonly firstName: string | null;
  readonly profilePictureUrl: string | null;
  /** OAuth provider avatar (Google, etc.) - used as fallback when profilePictureUrl is null */
  readonly oauthAvatarUrl: string | null;
  readonly sharedAt: string;
  /** Whether this recipient can see your earnings (true) or only hours (false) */
  readonly showEarnings: boolean;
};

/**
 * Share limits by subscription tier
 * Grandfathered users (before_paywall) get the same limit as pro tier
 */
const SHARE_LIMITS = {
  free: 1,
  grandfathered: 10,
  pro: 10,
  max: 20,
} as const;

type SubscriptionTier = keyof typeof SHARE_LIMITS;

/**
 * Sharing Service Interface
 */
export class SharingService extends Context.Tag("SharingService")<
  SharingService,
  {
    /**
     * Get users who have shared their shifts with the current user
     */
    readonly getUsersWhoSharedWithMe: (
      userId: string
    ) => Effect.Effect<
      readonly SharedUser[],
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get users the current user has shared their shifts with
     */
    readonly getMyShareRecipients: (
      userId: string
    ) => Effect.Effect<
      readonly ShareRecipient[],
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Create a share (add recipient)
     * Returns the recipient user ID if successful
     */
    readonly createShare: (
      userId: string,
      identifier: string,
      options?: { showEarnings?: boolean }
    ) => Effect.Effect<
      { recipientId: string },
      | DatabaseError
      | AuthError
      | NotFoundError
      | TimeoutError
      | SupabaseError
      | ConflictError
      | ValidationError,
      never
    >;

    /**
     * Create a share directly by user ID (for share-back feature)
     * Skips identifier lookup since we already know the user ID
     */
    readonly createShareById: (
      userId: string,
      recipientId: string,
      options?: { showEarnings?: boolean }
    ) => Effect.Effect<
      void,
      | DatabaseError
      | AuthError
      | NotFoundError
      | TimeoutError
      | SupabaseError
      | ConflictError
      | ValidationError,
      never
    >;

    /**
     * Remove a share (revoke recipient access)
     */
    readonly removeShare: (
      userId: string,
      recipientId: string
    ) => Effect.Effect<
      void,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Check if user can add more share recipients (based on subscription tier)
     */
    readonly canAddMoreRecipients: (
      userId: string
    ) => Effect.Effect<
      { canAdd: boolean; currentCount: number; limit: number },
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Check if viewer has access to owner's shifts
     */
    readonly hasShareAccess: (
      viewerId: string,
      ownerId: string
    ) => Effect.Effect<boolean, DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError, never>;

    /**
     * Update share settings (e.g., toggle earnings visibility)
     */
    readonly updateShareSettings: (
      userId: string,
      recipientId: string,
      settings: { showEarnings: boolean }
    ) => Effect.Effect<
      void,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get share settings for a specific viewer/owner pair
     * Used to determine if earnings should be shown when viewing shared shifts
     */
    readonly getShareSettings: (
      viewerId: string,
      ownerId: string
    ) => Effect.Effect<
      { showEarnings: boolean } | null,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Block a sharer (hide their shifts from viewer's list)
     */
    readonly blockSharer: (
      viewerId: string,
      ownerId: string
    ) => Effect.Effect<
      void,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Unblock a sharer (restore their shifts to viewer's list)
     */
    readonly unblockSharer: (
      viewerId: string,
      ownerId: string
    ) => Effect.Effect<
      void,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get blocked sharers for a viewer
     */
    readonly getBlockedSharers: (
      viewerId: string
    ) => Effect.Effect<
      readonly SharedUser[],
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get all sharers including blocked ones (for unified friends list)
     * Returns SharedUser with additional blocked field
     */
    readonly getAllSharersIncludingBlocked: (
      viewerId: string
    ) => Effect.Effect<
      readonly (SharedUser & { blocked: boolean })[],
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Update notification frequency for a specific sharer
     * Controls how often the viewer receives notifications about this sharer's shifts
     */
    readonly updateNotificationFrequency: (
      viewerId: string,
      ownerId: string,
      frequency: NotificationFrequency
    ) => Effect.Effect<
      void,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Remove a sharer as a viewer (delete the share row where you are the viewer)
     * Used when a user wants to remove someone who only shares with them (not mutual)
     * from their friends list entirely
     */
    readonly removeSharerAsViewer: (
      viewerId: string,
      ownerId: string
    ) => Effect.Effect<
      void,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;
  }
>() {}

/**
 * Live implementation of SharingService
 */
export const SharingServiceLive = Layer.effect(
  SharingService,
  Effect.gen(function* () {
    const auth = yield* AuthService;
    const supabase = yield* SupabaseService;
    const subscription = yield* SubscriptionService;

    /**
     * Helper to get subscription tier from price_id and grandfathered status
     * Paid tiers (pro/max) take priority, then grandfathered, then free
     */
    const getTier = (priceId: string | null | undefined, beforePaywall?: boolean): SubscriptionTier => {
      const proPriceId = process.env.NEXT_PUBLIC_PRO_PRICE_ID;
      const maxPriceId = process.env.NEXT_PUBLIC_MAX_PRICE_ID;
      const proYearlyId = process.env.NEXT_PUBLIC_PRO_YEARLY_ID;
      const maxYearlyId = process.env.NEXT_PUBLIC_MAX_YEARLY_ID;

      // Paid subscriptions take priority
      if (priceId === maxPriceId || priceId === maxYearlyId) return "max";
      if (priceId === proPriceId || priceId === proYearlyId) return "pro";

      // Grandfathered users (before_paywall) get 10 friends
      if (beforePaywall) return "grandfathered";

      return "free";
    };

    /**
     * Helper to create admin client for user lookup
     */
    const getAdminClient = () => {
      const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

      if (!url || !serviceRoleKey) {
        return null;
      }

      return createClient(url, serviceRoleKey, {
        auth: { persistSession: false },
      });
    };

    /**
     * Look up user by email or phone using admin client
     *
     * NOTE: This implementation fetches up to 1000 users and filters in memory.
     * For apps with >1000 users, consider using Supabase database functions or
     * a dedicated user lookup table. The current approach is suitable for small
     * to medium user bases.
     */
    const lookupUserByIdentifier = (
      identifier: string
    ): Effect.Effect<
      { id: string; email: string | null; phone: string | null } | null,
      ValidationError,
      never
    > =>
      Effect.gen(function* () {
        const adminClient = getAdminClient();
        if (!adminClient) {
          return yield* Effect.fail(
            new ValidationError({
              field: "config",
              message: "Admin client not configured",
            })
          );
        }

        const trimmed = identifier.trim().toLowerCase();

        // Check if it looks like an email
        const isEmail = trimmed.includes("@");

        // Check if it looks like a phone (Norwegian format)
        const isPhone = /^(\+47)?[0-9]{8}$/.test(trimmed.replace(/\s/g, ""));

        if (!isEmail && !isPhone) {
          return yield* Effect.fail(
            new ValidationError({
              field: "identifier",
              message: "Must be a valid email or phone number",
            })
          );
        }

        // Wrap the async admin lookup in Effect.tryPromise
        const result = yield* Effect.tryPromise({
          try: async () => {
            if (isEmail) {
              // For email lookup, we need to iterate through users
              // Supabase doesn't have direct email lookup in admin API
              const { data, error } = await adminClient.auth.admin.listUsers({
                page: 1,
                perPage: 1000, // Get more users to search through
              });

              if (error) {
                logger.error("Admin user lookup failed:", error);
                return null;
              }

              // Find user by email (case-insensitive)
              const user = data.users.find(
                (u) => u.email?.toLowerCase() === trimmed
              );

              if (!user) return null;

              return {
                id: user.id,
                email: user.email ?? null,
                phone: user.phone ?? null,
              };
            } else {
              // Phone lookup - normalize to 8-digit Norwegian number
              const inputDigits = trimmed.replace(/\D/g, "");
              // Extract the 8-digit local number (strip country code 47 if present)
              const getLocalNumber = (digits: string): string => {
                if (digits.length === 10 && digits.startsWith("47")) {
                  return digits.slice(2); // 4712345678 → 12345678
                }
                if (digits.length === 8) {
                  return digits; // Already 8 digits
                }
                return digits; // Return as-is for other formats
              };

              const normalizedInput = getLocalNumber(inputDigits);

              const { data, error } = await adminClient.auth.admin.listUsers({
                page: 1,
                perPage: 1000, // Get more users to search through
              });

              if (error) {
                logger.error("Admin user lookup failed:", error);
                return null;
              }

              // Find user by comparing normalized 8-digit numbers
              const user = data.users.find((u) => {
                if (!u.phone) return false;
                const storedDigits = u.phone.replace(/\D/g, "");
                const normalizedStored = getLocalNumber(storedDigits);
                return normalizedStored === normalizedInput;
              });

              if (!user) return null;

              return {
                id: user.id,
                email: user.email ?? null,
                phone: user.phone ?? null,
              };
            }
          },
          catch: (error) => {
            logger.error("User lookup error:", error);
            // Return null on error (wrapped in a way that doesn't fail the effect)
            return null as any; // This won't be reached since we catch below
          },
        }).pipe(
          Effect.catchAll(() => Effect.succeed(null))
        );

        return result;
      });

    return {
      /**
       * Get users who have shared their shifts with me
       */
      getUsersWhoSharedWithMe: (userId: string) =>
        Effect.gen(function* () {
          // Verify user is authenticated
          yield* auth.verifyUserId(userId);

          // Query shift_shares where viewer_id = userId and not blocked
          const sharesResult = yield* supabase.query(
            async (client) =>
              await client
                .from("shift_shares")
                .select("owner_id, created_at, show_earnings, notification_frequency")
                .eq("viewer_id", userId)
                .eq("blocked", false)
                .order("created_at", { ascending: false }),
            { retries: 2 }
          );

          const shares = (sharesResult as any[]) ?? [];
          if (shares.length === 0) {
            return [] as readonly SharedUser[];
          }

          // Get profile pictures from user_settings separately
          const ownerIds = shares.map((s) => s.owner_id);
          const settingsResult = yield* supabase.query(
            async (client) =>
              await client
                .from("user_settings")
                .select("user_id, profile_picture_url")
                .in("user_id", ownerIds),
            { retries: 2 }
          );

          const settings = (settingsResult as any[]) ?? [];
          const settingsMap = new Map(
            settings.map((s) => [s.user_id, s.profile_picture_url])
          );

          // Get email/phone/name/avatar from admin client (name and avatar are in user_metadata)
          const adminClient = getAdminClient();
          type AuthUserInfo = { email: string | null; phone: string | null; firstName: string | null; oauthAvatarUrl: string | null };
          const usersMap = new Map<string, AuthUserInfo>();

          if (adminClient) {
            type AdminUser = { id: string; email?: string; phone?: string; user_metadata?: Record<string, unknown> };
            const adminResult = yield* Effect.tryPromise({
              try: async () => {
                const { data, error } = await adminClient.auth.admin.listUsers({
                  page: 1,
                  perPage: 1000,
                });
                if (error) {
                  logger.error("Admin lookup for sharers failed:", error);
                  return [] as AdminUser[];
                }
                return data.users as AdminUser[];
              },
              catch: () => [] as AdminUser[],
            }).pipe(Effect.catchAll(() => Effect.succeed([] as AdminUser[])));

            for (const user of adminResult) {
              if (ownerIds.includes(user.id)) {
                const metadata = user.user_metadata ?? {};
                usersMap.set(user.id, {
                  email: user.email ?? null,
                  phone: user.phone ?? null,
                  firstName: (metadata.full_name as string) ?? (metadata.name as string) ?? null,
                  oauthAvatarUrl: (metadata.avatar_url as string) ?? (metadata.picture as string) ?? null,
                });
              }
            }
          }

          return shares.map((share) => {
            const profilePictureUrl = settingsMap.get(share.owner_id) ?? null;
            const authUser = usersMap.get(share.owner_id);
            return {
              id: share.owner_id,
              email: authUser?.email ?? null,
              phone: authUser?.phone ?? null,
              firstName: authUser?.firstName ?? null,
              profilePictureUrl,
              oauthAvatarUrl: authUser?.oauthAvatarUrl ?? null,
              sharedAt: share.created_at,
              showEarnings: share.show_earnings ?? true,
              notificationFrequency: (share.notification_frequency ?? "instant") as NotificationFrequency,
            };
          }) as readonly SharedUser[];
        }).pipe(
          Effect.catchTag("DatabaseError", (error) => {
            if (error.code === "NO_DATA") {
              return Effect.succeed([] as readonly SharedUser[]);
            }
            return Effect.fail(error);
          })
        ),

      /**
       * Get users I have shared my shifts with
       */
      getMyShareRecipients: (userId: string) =>
        Effect.gen(function* () {
          // Verify user is authenticated
          yield* auth.verifyUserId(userId);

          // Query shift_shares where owner_id = userId
          const sharesResult = yield* supabase.query(
            async (client) =>
              await client
                .from("shift_shares")
                .select("viewer_id, created_at, show_earnings")
                .eq("owner_id", userId)
                .order("created_at", { ascending: false }),
            { retries: 2 }
          );

          const shares = (sharesResult as any[]) ?? [];
          if (shares.length === 0) {
            return [] as readonly ShareRecipient[];
          }

          // Get profile pictures from user_settings separately
          const viewerIds = shares.map((s) => s.viewer_id);
          const settingsResult = yield* supabase.query(
            async (client) =>
              await client
                .from("user_settings")
                .select("user_id, profile_picture_url")
                .in("user_id", viewerIds),
            { retries: 2 }
          );

          const settings = (settingsResult as any[]) ?? [];
          const settingsMap = new Map(
            settings.map((s) => [s.user_id, s.profile_picture_url])
          );

          // Get email/phone/name/avatar from admin client (name and avatar are in user_metadata)
          const adminClient = getAdminClient();
          type AuthUserInfo = { email: string | null; phone: string | null; firstName: string | null; oauthAvatarUrl: string | null };
          const usersMap = new Map<string, AuthUserInfo>();

          if (adminClient) {
            type AdminUser = { id: string; email?: string; phone?: string; user_metadata?: Record<string, unknown> };
            const adminResult = yield* Effect.tryPromise({
              try: async () => {
                const { data, error } = await adminClient.auth.admin.listUsers({
                  page: 1,
                  perPage: 1000,
                });
                if (error) {
                  logger.error("Admin lookup for recipients failed:", error);
                  return [] as AdminUser[];
                }
                return data.users as AdminUser[];
              },
              catch: () => [] as AdminUser[],
            }).pipe(Effect.catchAll(() => Effect.succeed([] as AdminUser[])));

            for (const user of adminResult) {
              if (viewerIds.includes(user.id)) {
                const metadata = user.user_metadata ?? {};
                usersMap.set(user.id, {
                  email: user.email ?? null,
                  phone: user.phone ?? null,
                  firstName: (metadata.full_name as string) ?? (metadata.name as string) ?? null,
                  oauthAvatarUrl: (metadata.avatar_url as string) ?? (metadata.picture as string) ?? null,
                });
              }
            }
          }

          return shares.map((share) => {
            const profilePictureUrl = settingsMap.get(share.viewer_id) ?? null;
            const authUser = usersMap.get(share.viewer_id);
            return {
              id: share.viewer_id,
              email: authUser?.email ?? null,
              phone: authUser?.phone ?? null,
              firstName: authUser?.firstName ?? null,
              profilePictureUrl,
              oauthAvatarUrl: authUser?.oauthAvatarUrl ?? null,
              sharedAt: share.created_at,
              showEarnings: share.show_earnings ?? true,
            };
          }) as readonly ShareRecipient[];
        }).pipe(
          Effect.catchTag("DatabaseError", (error) => {
            if (error.code === "NO_DATA") {
              return Effect.succeed([] as readonly ShareRecipient[]);
            }
            return Effect.fail(error);
          })
        ),

      /**
       * Create a new share
       */
      createShare: (userId: string, identifier: string, options?: { showEarnings?: boolean }) =>
        Effect.gen(function* () {
          // Verify user is authenticated
          yield* auth.verifyUserId(userId);

          // Check subscription tier limit (including grandfathered status)
          const { subscription: sub, profile } = yield* subscription.getUserSubscriptionData(userId);
          const tier = getTier(sub?.price_id, profile?.before_paywall);
          const limit = SHARE_LIMITS[tier];

          // Count current shares using query method
          const countResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .select("*", { count: "exact", head: true })
                .eq("owner_id", userId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "QUERY_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          const currentCount = countResult.count ?? 0;

          if (currentCount >= limit) {
            return yield* Effect.fail(
              new ValidationError({
                field: "limit",
                message: `Share limit reached (${limit} for ${tier} tier)`,
              })
            );
          }

          // Look up the recipient user
          const recipientUser = yield* lookupUserByIdentifier(identifier);

          if (!recipientUser) {
            // Generic message to prevent enumeration
            return yield* Effect.fail(
              new NotFoundError({
                resource: "User",
              })
            );
          }

          // Can't share with yourself
          if (recipientUser.id === userId) {
            return yield* Effect.fail(
              new ValidationError({
                field: "identifier",
                message: "Cannot share with yourself",
              })
            );
          }

          // Create the share (earnings sharing off by default)
          const insertResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client.from("shift_shares").insert({
                owner_id: userId,
                viewer_id: recipientUser.id,
                show_earnings: options?.showEarnings ?? false,
              });
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "INSERT_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (insertResult.error) {
            if (insertResult.error.code === "23505") {
              // Unique constraint violation
              return yield* Effect.fail(
                new ConflictError({
                  resource: "Share",
                  field: "viewer_id",
                })
              );
            }
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: insertResult.error.code,
                errorMessage: insertResult.error.message,
                cause: insertResult.error,
              })
            );
          }

          return { recipientId: recipientUser.id };
        }),

      /**
       * Create a share directly by user ID (for share-back feature)
       */
      createShareById: (userId: string, recipientId: string, options?: { showEarnings?: boolean }) =>
        Effect.gen(function* () {
          // Verify user is authenticated
          yield* auth.verifyUserId(userId);

          // Can't share with yourself
          if (recipientId === userId) {
            return yield* Effect.fail(
              new ValidationError({
                field: "recipientId",
                message: "Cannot share with yourself",
              })
            );
          }

          // Check subscription tier limit (including grandfathered status)
          const { subscription: sub, profile } = yield* subscription.getUserSubscriptionData(userId);
          const tier = getTier(sub?.price_id, profile?.before_paywall);
          const limit = SHARE_LIMITS[tier];

          // Count current shares
          const countResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .select("*", { count: "exact", head: true })
                .eq("owner_id", userId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "QUERY_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          const currentCount = countResult.count ?? 0;

          if (currentCount >= limit) {
            return yield* Effect.fail(
              new ValidationError({
                field: "limit",
                message: `Share limit reached (${limit} for ${tier} tier)`,
              })
            );
          }

          // Create the share (earnings sharing off by default)
          const insertResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client.from("shift_shares").insert({
                owner_id: userId,
                viewer_id: recipientId,
                show_earnings: options?.showEarnings ?? false,
              });
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "INSERT_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (insertResult.error) {
            if (insertResult.error.code === "23505") {
              // Unique constraint violation - already shared
              return yield* Effect.fail(
                new ConflictError({
                  resource: "Share",
                  field: "viewer_id",
                })
              );
            }
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: insertResult.error.code,
                errorMessage: insertResult.error.message,
                cause: insertResult.error,
              })
            );
          }
        }),

      /**
       * Remove a share
       */
      removeShare: (userId: string, recipientId: string) =>
        Effect.gen(function* () {
          // Verify user is authenticated
          yield* auth.verifyUserId(userId);

          const deleteResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .delete()
                .eq("owner_id", userId)
                .eq("viewer_id", recipientId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "DELETE_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (deleteResult.error) {
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: deleteResult.error.code,
                errorMessage: deleteResult.error.message,
                cause: deleteResult.error,
              })
            );
          }
        }),

      /**
       * Check if user can add more share recipients
       */
      canAddMoreRecipients: (userId: string) =>
        Effect.gen(function* () {
          // Verify user is authenticated
          yield* auth.verifyUserId(userId);

          // Get subscription tier (including grandfathered status)
          const { subscription: sub, profile } = yield* subscription.getUserSubscriptionData(userId);
          const tier = getTier(sub?.price_id, profile?.before_paywall);
          const limit = SHARE_LIMITS[tier];

          // Count current shares
          const countResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .select("*", { count: "exact", head: true })
                .eq("owner_id", userId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "QUERY_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (countResult.error) {
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: countResult.error.code,
                errorMessage: countResult.error.message,
                cause: countResult.error,
              })
            );
          }

          const currentCount = countResult.count ?? 0;

          return {
            canAdd: currentCount < limit,
            currentCount,
            limit,
          };
        }),

      /**
       * Check if viewer has access to owner's shifts
       */
      hasShareAccess: (viewerId: string, ownerId: string) =>
        Effect.gen(function* () {
          // Verify viewer is authenticated
          yield* auth.verifyUserId(viewerId);

          const selectResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .select("id")
                .eq("owner_id", ownerId)
                .eq("viewer_id", viewerId)
                .maybeSingle();
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "QUERY_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (selectResult.error) {
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: selectResult.error.code,
                errorMessage: selectResult.error.message,
                cause: selectResult.error,
              })
            );
          }

          return selectResult.data !== null;
        }),

      /**
       * Update share settings (e.g., toggle earnings visibility)
       */
      updateShareSettings: (
        userId: string,
        recipientId: string,
        settings: { showEarnings: boolean }
      ) =>
        Effect.gen(function* () {
          // Verify user is authenticated
          yield* auth.verifyUserId(userId);

          const updateResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .update({ show_earnings: settings.showEarnings })
                .eq("owner_id", userId)
                .eq("viewer_id", recipientId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "UPDATE_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (updateResult.error) {
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: updateResult.error.code,
                errorMessage: updateResult.error.message,
                cause: updateResult.error,
              })
            );
          }
        }),

      /**
       * Get share settings for a specific viewer/owner pair
       */
      getShareSettings: (viewerId: string, ownerId: string) =>
        Effect.gen(function* () {
          // Verify viewer is authenticated
          yield* auth.verifyUserId(viewerId);

          const selectResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .select("show_earnings")
                .eq("owner_id", ownerId)
                .eq("viewer_id", viewerId)
                .maybeSingle();
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "QUERY_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (selectResult.error) {
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: selectResult.error.code,
                errorMessage: selectResult.error.message,
                cause: selectResult.error,
              })
            );
          }

          if (!selectResult.data) {
            return null;
          }

          return {
            showEarnings: selectResult.data.show_earnings ?? true,
          };
        }),

      /**
       * Block a sharer (hide their shifts from viewer's list)
       */
      blockSharer: (viewerId: string, ownerId: string) =>
        Effect.gen(function* () {
          // Verify viewer is authenticated
          yield* auth.verifyUserId(viewerId);

          const updateResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .update({ blocked: true })
                .eq("owner_id", ownerId)
                .eq("viewer_id", viewerId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "UPDATE_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (updateResult.error) {
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: updateResult.error.code,
                errorMessage: updateResult.error.message,
                cause: updateResult.error,
              })
            );
          }
        }),

      /**
       * Unblock a sharer (restore their shifts to viewer's list)
       */
      unblockSharer: (viewerId: string, ownerId: string) =>
        Effect.gen(function* () {
          // Verify viewer is authenticated
          yield* auth.verifyUserId(viewerId);

          const updateResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .update({ blocked: false })
                .eq("owner_id", ownerId)
                .eq("viewer_id", viewerId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "UPDATE_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (updateResult.error) {
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: updateResult.error.code,
                errorMessage: updateResult.error.message,
                cause: updateResult.error,
              })
            );
          }
        }),

      /**
       * Get blocked sharers for a viewer
       */
      getBlockedSharers: (viewerId: string) =>
        Effect.gen(function* () {
          // Verify viewer is authenticated
          yield* auth.verifyUserId(viewerId);

          // Query shift_shares where viewer_id = userId and blocked = true
          const sharesResult = yield* supabase.query(
            async (client) =>
              await client
                .from("shift_shares")
                .select("owner_id, created_at, show_earnings, notification_frequency")
                .eq("viewer_id", viewerId)
                .eq("blocked", true)
                .order("created_at", { ascending: false }),
            { retries: 2 }
          );

          const shares = (sharesResult as any[]) ?? [];
          if (shares.length === 0) {
            return [] as readonly SharedUser[];
          }

          // Get profile pictures from user_settings separately
          const ownerIds = shares.map((s) => s.owner_id);
          const settingsResult = yield* supabase.query(
            async (client) =>
              await client
                .from("user_settings")
                .select("user_id, profile_picture_url")
                .in("user_id", ownerIds),
            { retries: 2 }
          );

          const settings = (settingsResult as any[]) ?? [];
          const settingsMap = new Map(
            settings.map((s) => [s.user_id, s.profile_picture_url])
          );

          // Get email/phone/name/avatar from admin client
          const adminClient = getAdminClient();
          type AuthUserInfo = { email: string | null; phone: string | null; firstName: string | null; oauthAvatarUrl: string | null };
          const usersMap = new Map<string, AuthUserInfo>();

          if (adminClient) {
            type AdminUser = { id: string; email?: string; phone?: string; user_metadata?: Record<string, unknown> };
            const adminResult = yield* Effect.tryPromise({
              try: async () => {
                const { data, error } = await adminClient.auth.admin.listUsers({
                  page: 1,
                  perPage: 1000,
                });
                if (error) {
                  logger.error("Admin lookup for blocked sharers failed:", error);
                  return [] as AdminUser[];
                }
                return data.users as AdminUser[];
              },
              catch: () => [] as AdminUser[],
            }).pipe(Effect.catchAll(() => Effect.succeed([] as AdminUser[])));

            for (const user of adminResult) {
              if (ownerIds.includes(user.id)) {
                const metadata = user.user_metadata ?? {};
                usersMap.set(user.id, {
                  email: user.email ?? null,
                  phone: user.phone ?? null,
                  firstName: (metadata.full_name as string) ?? (metadata.name as string) ?? null,
                  oauthAvatarUrl: (metadata.avatar_url as string) ?? (metadata.picture as string) ?? null,
                });
              }
            }
          }

          return shares.map((share) => {
            const profilePictureUrl = settingsMap.get(share.owner_id) ?? null;
            const authUser = usersMap.get(share.owner_id);
            return {
              id: share.owner_id,
              email: authUser?.email ?? null,
              phone: authUser?.phone ?? null,
              firstName: authUser?.firstName ?? null,
              profilePictureUrl,
              oauthAvatarUrl: authUser?.oauthAvatarUrl ?? null,
              sharedAt: share.created_at,
              showEarnings: share.show_earnings ?? true,
              notificationFrequency: (share.notification_frequency ?? "instant") as NotificationFrequency,
            };
          }) as readonly SharedUser[];
        }).pipe(
          Effect.catchTag("DatabaseError", (error) => {
            if (error.code === "NO_DATA") {
              return Effect.succeed([] as readonly SharedUser[]);
            }
            return Effect.fail(error);
          })
        ),

      /**
       * Get all sharers including blocked ones (for unified friends list)
       */
      getAllSharersIncludingBlocked: (viewerId: string) =>
        Effect.gen(function* () {
          // Verify viewer is authenticated
          yield* auth.verifyUserId(viewerId);

          // Query ALL shift_shares where viewer_id = userId (no blocked filter)
          const sharesResult = yield* supabase.query(
            async (client) =>
              await client
                .from("shift_shares")
                .select("owner_id, created_at, show_earnings, blocked, notification_frequency")
                .eq("viewer_id", viewerId)
                .order("created_at", { ascending: false }),
            { retries: 2 }
          );

          const shares = (sharesResult as any[]) ?? [];
          if (shares.length === 0) {
            return [] as readonly (SharedUser & { blocked: boolean })[];
          }

          // Get profile pictures from user_settings separately
          const ownerIds = shares.map((s) => s.owner_id);
          const settingsResult = yield* supabase.query(
            async (client) =>
              await client
                .from("user_settings")
                .select("user_id, profile_picture_url")
                .in("user_id", ownerIds),
            { retries: 2 }
          );

          const settings = (settingsResult as any[]) ?? [];
          const settingsMap = new Map(
            settings.map((s) => [s.user_id, s.profile_picture_url])
          );

          // Get email/phone/name/avatar from admin client
          const adminClient = getAdminClient();
          type AuthUserInfo = { email: string | null; phone: string | null; firstName: string | null; oauthAvatarUrl: string | null };
          const usersMap = new Map<string, AuthUserInfo>();

          if (adminClient) {
            type AdminUser = { id: string; email?: string; phone?: string; user_metadata?: Record<string, unknown> };
            const adminResult = yield* Effect.tryPromise({
              try: async () => {
                const { data, error } = await adminClient.auth.admin.listUsers({
                  page: 1,
                  perPage: 1000,
                });
                if (error) {
                  logger.error("Admin lookup for all sharers failed:", error);
                  return [] as AdminUser[];
                }
                return data.users as AdminUser[];
              },
              catch: () => [] as AdminUser[],
            }).pipe(Effect.catchAll(() => Effect.succeed([] as AdminUser[])));

            for (const user of adminResult) {
              if (ownerIds.includes(user.id)) {
                const metadata = user.user_metadata ?? {};
                usersMap.set(user.id, {
                  email: user.email ?? null,
                  phone: user.phone ?? null,
                  firstName: (metadata.full_name as string) ?? (metadata.name as string) ?? null,
                  oauthAvatarUrl: (metadata.avatar_url as string) ?? (metadata.picture as string) ?? null,
                });
              }
            }
          }

          return shares.map((share) => {
            const profilePictureUrl = settingsMap.get(share.owner_id) ?? null;
            const authUser = usersMap.get(share.owner_id);
            return {
              id: share.owner_id,
              email: authUser?.email ?? null,
              phone: authUser?.phone ?? null,
              firstName: authUser?.firstName ?? null,
              profilePictureUrl,
              oauthAvatarUrl: authUser?.oauthAvatarUrl ?? null,
              sharedAt: share.created_at,
              showEarnings: share.show_earnings ?? true,
              notificationFrequency: (share.notification_frequency ?? "instant") as NotificationFrequency,
              blocked: share.blocked ?? false,
            };
          }) as readonly (SharedUser & { blocked: boolean })[];
        }).pipe(
          Effect.catchTag("DatabaseError", (error) => {
            if (error.code === "NO_DATA") {
              return Effect.succeed([] as readonly (SharedUser & { blocked: boolean })[]);
            }
            return Effect.fail(error);
          })
        ),

      /**
       * Update notification frequency for a specific sharer
       */
      updateNotificationFrequency: (
        viewerId: string,
        ownerId: string,
        frequency: NotificationFrequency
      ) =>
        Effect.gen(function* () {
          // Verify viewer is authenticated
          yield* auth.verifyUserId(viewerId);

          // Update the share's notification_frequency
          const updateResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .update({ notification_frequency: frequency })
                .eq("viewer_id", viewerId)
                .eq("owner_id", ownerId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "UPDATE_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (updateResult.error) {
            yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: updateResult.error.code,
                errorMessage: updateResult.error.message,
                cause: updateResult.error,
              })
            );
          }

          logger.info(`Updated notification frequency for viewer=${viewerId} owner=${ownerId} to ${frequency}`);
        }).pipe(
          Effect.catchTag("DatabaseError", (error) => {
            logger.error("Failed to update notification frequency:", error);
            return Effect.fail(error);
          })
        ),

      /**
       * Remove a sharer as a viewer (delete the share row where you are the viewer)
       */
      removeSharerAsViewer: (viewerId: string, ownerId: string) =>
        Effect.gen(function* () {
          // Verify viewer is authenticated
          yield* auth.verifyUserId(viewerId);

          const deleteResult = yield* Effect.tryPromise({
            try: async () => {
              const client = await Effect.runPromise(supabase.getClient());
              return client
                .from("shift_shares")
                .delete()
                .eq("owner_id", ownerId)
                .eq("viewer_id", viewerId);
            },
            catch: (error) =>
              new DatabaseError({
                table: "shift_shares",
                code: "DELETE_ERROR",
                errorMessage: String(error),
                cause: error,
              }),
          });

          if (deleteResult.error) {
            return yield* Effect.fail(
              new DatabaseError({
                table: "shift_shares",
                code: deleteResult.error.code,
                errorMessage: deleteResult.error.message,
                cause: deleteResult.error,
              })
            );
          }

          logger.info(`Viewer ${viewerId} removed sharer ${ownerId} from their friends list`);
        }),
    };
  })
);
