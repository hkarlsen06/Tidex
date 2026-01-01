/**
 * Settings Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * Uses SettingsService for user settings and profile management.
 *
 * Migration status: Using Effect-based SettingsService internally
 */

'use server';

import { cacheTag } from 'next/cache';
import { Effect } from 'effect';
import { SettingsService } from '@/lib/services/settings';
import { AuthSettingsLive } from '@/lib/layers/app';
import { logger } from '@/lib/logger';
import type { AuthError, DatabaseError, NotFoundError, SupabaseError, TimeoutError } from '@/lib/errors/tagged';

/**
 * Get user settings for the authenticated user
 * - Automatically verifies user session matches provided userId
 *
 * Promise wrapper around Effect-based SettingsService
 */
export async function getUserSettings(userId: string) {
  'use cache: private';
  cacheTag(`user-${userId}`, 'user-settings');

  const program = Effect.gen(function* () {
    const settings = yield* SettingsService;
    const userSettings = yield* settings.getUserSettings(userId);
    return userSettings;
  }).pipe(
    Effect.provide(AuthSettingsLive),
    // Handle specific error types with catchTags for better error visibility
    Effect.catchTags({
      DatabaseError: (error: DatabaseError) => {
        logger.error('Database error fetching user settings:', error);
        return Effect.succeed(null);
      },
      AuthError: (error: AuthError) => {
        logger.error('Auth error fetching user settings:', error);
        return Effect.succeed(null);
      },
      NotFoundError: (_error: NotFoundError) => {
        // User has no settings yet - this is expected
        return Effect.succeed(null);
      },
      TimeoutError: (error: TimeoutError) => {
        logger.error('Timeout fetching user settings:', error);
        return Effect.succeed(null);
      },
      SupabaseError: (error: SupabaseError) => {
        logger.error('Supabase error fetching user settings:', error);
        return Effect.succeed(null);
      },
    }),
    Effect.scoped
  );

  return await Effect.runPromise(program);
}

/**
 * Get user profile information including authentication methods
 * - Automatically verifies user session matches provided userId
 *
 * Promise wrapper around Effect-based SettingsService
 */
export async function getUserProfile(userId: string) {
  'use cache: private';
  cacheTag(`user-${userId}`, 'user-profile');

  // Default profile for error cases
  const defaultProfile = {
    firstName: '',
    email: '',
    profilePictureUrl: null,
    hasGoogleConnected: false,
    hasAppleConnected: false,
    hasPhoneConnected: false,
    phoneNumber: null,
    hasPassword: false,
    canUnlinkPhone: false,
    canDisconnectGoogle: false,
    canDisconnectApple: false,
    isPhoneOnly: false,
    isOAuthOnly: false,
  } as const;

  const program = Effect.gen(function* () {
    const settings = yield* SettingsService;
    const profile = yield* settings.getUserProfile(userId);
    return profile;
  }).pipe(
    Effect.provide(AuthSettingsLive),
    // Handle specific error types with catchTags for better error visibility
    Effect.catchTags({
      DatabaseError: (error: DatabaseError) => {
        logger.error('Database error fetching user profile:', error);
        return Effect.succeed(defaultProfile);
      },
      AuthError: (error: AuthError) => {
        logger.error('Auth error fetching user profile:', error);
        return Effect.succeed(defaultProfile);
      },
      NotFoundError: (error: NotFoundError) => {
        logger.error('User profile not found:', error);
        return Effect.succeed(defaultProfile);
      },
      TimeoutError: (error: TimeoutError) => {
        logger.error('Timeout fetching user profile:', error);
        return Effect.succeed(defaultProfile);
      },
      SupabaseError: (error: SupabaseError) => {
        logger.error('Supabase error fetching user profile:', error);
        return Effect.succeed(defaultProfile);
      },
    }),
    Effect.scoped
  );

  return await Effect.runPromise(program);
}
