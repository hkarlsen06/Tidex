/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as account from "../account.js";
import type * as admin from "../admin.js";
import type * as appActivity from "../appActivity.js";
import type * as calendarSubscriptions from "../calendarSubscriptions.js";
import type * as crons from "../crons.js";
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
import type * as lib_notify from "../lib/notify.js";
import type * as lib_revision from "../lib/revision.js";
import type * as lib_shared_dateUtils from "../lib/shared/dateUtils.js";
import type * as lib_shared_liveActivityPayload from "../lib/shared/liveActivityPayload.js";
import type * as lib_shared_liveActivityScheduling from "../lib/shared/liveActivityScheduling.js";
import type * as lib_shared_payroll_breaks from "../lib/shared/payroll/breaks.js";
import type * as lib_shared_payroll_calc from "../lib/shared/payroll/calc.js";
import type * as lib_shared_payroll_index from "../lib/shared/payroll/index.js";
import type * as lib_shared_payroll_norwegianHolidays from "../lib/shared/payroll/norwegianHolidays.js";
import type * as lib_shared_payroll_pauseWindows from "../lib/shared/payroll/pauseWindows.js";
import type * as lib_shared_payroll_periods from "../lib/shared/payroll/periods.js";
import type * as lib_shared_payroll_presets from "../lib/shared/payroll/presets.js";
import type * as lib_shared_payroll_snapshot from "../lib/shared/payroll/snapshot.js";
import type * as lib_shared_payroll_types from "../lib/shared/payroll/types.js";
import type * as lib_shared_recurring_types from "../lib/shared/recurring/types.js";
import type * as lib_shared_recurring_utils from "../lib/shared/recurring/utils.js";
import type * as lib_shared_timeUtils from "../lib/shared/timeUtils.js";
import type * as lib_syncWrite from "../lib/syncWrite.js";
import type * as lib_validators from "../lib/validators.js";
import type * as liveActivities from "../liveActivities.js";
import type * as messages from "../messages.js";
import type * as notificationPreferences from "../notificationPreferences.js";
import type * as onboarding from "../onboarding.js";
import type * as payrollAdjustments from "../payrollAdjustments.js";
import type * as push from "../push.js";
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
  account: typeof account;
  admin: typeof admin;
  appActivity: typeof appActivity;
  calendarSubscriptions: typeof calendarSubscriptions;
  crons: typeof crons;
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
  "lib/notify": typeof lib_notify;
  "lib/revision": typeof lib_revision;
  "lib/shared/dateUtils": typeof lib_shared_dateUtils;
  "lib/shared/liveActivityPayload": typeof lib_shared_liveActivityPayload;
  "lib/shared/liveActivityScheduling": typeof lib_shared_liveActivityScheduling;
  "lib/shared/payroll/breaks": typeof lib_shared_payroll_breaks;
  "lib/shared/payroll/calc": typeof lib_shared_payroll_calc;
  "lib/shared/payroll/index": typeof lib_shared_payroll_index;
  "lib/shared/payroll/norwegianHolidays": typeof lib_shared_payroll_norwegianHolidays;
  "lib/shared/payroll/pauseWindows": typeof lib_shared_payroll_pauseWindows;
  "lib/shared/payroll/periods": typeof lib_shared_payroll_periods;
  "lib/shared/payroll/presets": typeof lib_shared_payroll_presets;
  "lib/shared/payroll/snapshot": typeof lib_shared_payroll_snapshot;
  "lib/shared/payroll/types": typeof lib_shared_payroll_types;
  "lib/shared/recurring/types": typeof lib_shared_recurring_types;
  "lib/shared/recurring/utils": typeof lib_shared_recurring_utils;
  "lib/shared/timeUtils": typeof lib_shared_timeUtils;
  "lib/syncWrite": typeof lib_syncWrite;
  "lib/validators": typeof lib_validators;
  liveActivities: typeof liveActivities;
  messages: typeof messages;
  notificationPreferences: typeof notificationPreferences;
  onboarding: typeof onboarding;
  payrollAdjustments: typeof payrollAdjustments;
  push: typeof push;
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
