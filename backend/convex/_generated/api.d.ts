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
import type * as calendarSubscriptions from "../calendarSubscriptions.js";
import type * as devices from "../devices.js";
import type * as diagnostics from "../diagnostics.js";
import type * as events from "../events.js";
import type * as feedback from "../feedback.js";
import type * as http from "../http.js";
import type * as jobs from "../jobs.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_clerk from "../lib/clerk.js";
import type * as lib_columns from "../lib/columns.js";
import type * as lib_messaging from "../lib/messaging.js";
import type * as lib_revision from "../lib/revision.js";
import type * as lib_syncWrite from "../lib/syncWrite.js";
import type * as lib_validators from "../lib/validators.js";
import type * as messages from "../messages.js";
import type * as notificationPreferences from "../notificationPreferences.js";
import type * as onboarding from "../onboarding.js";
import type * as payrollAdjustments from "../payrollAdjustments.js";
import type * as recurringShifts from "../recurringShifts.js";
import type * as sharing from "../sharing.js";
import type * as sync from "../sync.js";
import type * as tariffs from "../tariffs.js";
import type * as threads from "../threads.js";
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
  calendarSubscriptions: typeof calendarSubscriptions;
  devices: typeof devices;
  diagnostics: typeof diagnostics;
  events: typeof events;
  feedback: typeof feedback;
  http: typeof http;
  jobs: typeof jobs;
  "lib/auth": typeof lib_auth;
  "lib/clerk": typeof lib_clerk;
  "lib/columns": typeof lib_columns;
  "lib/messaging": typeof lib_messaging;
  "lib/revision": typeof lib_revision;
  "lib/syncWrite": typeof lib_syncWrite;
  "lib/validators": typeof lib_validators;
  messages: typeof messages;
  notificationPreferences: typeof notificationPreferences;
  onboarding: typeof onboarding;
  payrollAdjustments: typeof payrollAdjustments;
  recurringShifts: typeof recurringShifts;
  sharing: typeof sharing;
  sync: typeof sync;
  tariffs: typeof tariffs;
  threads: typeof threads;
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
