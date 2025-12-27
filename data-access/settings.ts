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
    Effect.catchAll((error) => {
      logger.error('Failed to fetch user settings:', error);
      return Effect.succeed(null);
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

  const program = Effect.gen(function* () {
    const settings = yield* SettingsService;
    const profile = yield* settings.getUserProfile(userId);
    return profile;
  }).pipe(
    Effect.provide(AuthSettingsLive),
    Effect.catchAll((error) => {
      logger.error('Failed to fetch user profile:', error);
      // Return default profile on error
      return Effect.succeed({
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
      });
    }),
    Effect.scoped
  );

  return await Effect.runPromise(program);
}
