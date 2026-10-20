/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as appActivity from "../appActivity.js";
import type * as events from "../events.js";
import type * as jobs from "../jobs.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_clerk from "../lib/clerk.js";
import type * as lib_columns from "../lib/columns.js";
import type * as lib_revision from "../lib/revision.js";
import type * as lib_syncWrite from "../lib/syncWrite.js";
import type * as lib_validators from "../lib/validators.js";
import type * as notificationPreferences from "../notificationPreferences.js";
import type * as payrollAdjustments from "../payrollAdjustments.js";
import type * as recurringShifts from "../recurringShifts.js";
import type * as sync from "../sync.js";
import type * as userSettings from "../userSettings.js";
import type * as userShifts from "../userShifts.js";
import type * as users from "../users.js";
import type * as wageSnapshots from "../wageSnapshots.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  appActivity: typeof appActivity;
  events: typeof events;
  jobs: typeof jobs;
  "lib/auth": typeof lib_auth;
  "lib/clerk": typeof lib_clerk;
  "lib/columns": typeof lib_columns;
  "lib/revision": typeof lib_revision;
  "lib/syncWrite": typeof lib_syncWrite;
  "lib/validators": typeof lib_validators;
  notificationPreferences: typeof notificationPreferences;
  payrollAdjustments: typeof payrollAdjustments;
  recurringShifts: typeof recurringShifts;
  sync: typeof sync;
  userSettings: typeof userSettings;
  userShifts: typeof userShifts;
  users: typeof users;
  wageSnapshots: typeof wageSnapshots;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
