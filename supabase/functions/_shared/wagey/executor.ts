import type { WageyRequestContext } from "./context.ts";
import {
  archiveJob,
  beginWageyTurn,
  blockSharer,
  clearShiftSnapshots,
  convertRecurringShiftToStandalone,
  copyShifts,
  createJob,
  createRecurringShift,
  createShare,
  createShifts,
  deleteJob,
  deleteRecurringShift,
  deleteShift,
  draftRecurringShift,
  getAllFriends,
  getComputedShiftsForApi,
  getSharedUserShifts,
  getSharerShiftPreviews,
  getShiftIdentityRowsForApi,
  getStatistics,
  getTariffTypes,
  getTariffVersionForDate,
  getLatestTariffVersion,
  getUserCurrency,
  getUserFeedback,
  getUserJobs,
  getUserSettings,
  moveRecurringShift,
  removeShare,
  removeSharer,
  shareBack,
  submitFeedback,
  toggleSharerMuted,
  toggleShareEarnings,
  unblockSharer,
  updateCustomSupplements,
  updateDisplaySettings,
  updateJob,
  updatePaySettings,
  updatePreferencesSettings,
  updateProfileSettings,
  updateRecurringShift,
  updateShift,
} from "./data.ts";
import { maxIterationsReached, toolResults as tr } from "./i18n.ts";
import type {
  CalculateEarningsInput,
  CalculateWagesInput,
  ConfirmRecurringShiftInput,
  DraftRecurringShiftInput,
  GetStatisticsInput,
  GetWageInfoInput,
  ListFriendsInput,
  ListWorkplacesInput,
  ManageFeedbackInput,
  ManageFriendSharingInput,
  ManageProfileInput,
  ManageRecurringExclusionInput,
  ManageRecurringShiftInput,
  ManageSettingsInput,
  ManageShiftAdvancedInput,
  ManageShiftInput,
  ManageWageSnapshotsInput,
  ManageWorkplaceInput,
  QueryFriendFeaturedShiftInput,
  QueryFriendShiftsInput,
  QueryShiftsInput,
  ToolName,
  ToolResult,
} from "./tools.ts";
import {
  calculateEarningsSchema,
  calculateWagesSchema,
  confirmRecurringShiftSchema,
  draftRecurringShiftSchema,
  getStatisticsSchema,
  getWageInfoSchema,
  listFriendsSchema,
  listWorkplacesSchema,
  manageFeedbackSchema,
  manageFriendSharingSchema,
  manageProfileSchema,
  manageRecurringExclusionSchema,
  manageRecurringShiftSchema,
  manageSettingsSchema,
  manageShiftAdvancedSchema,
  manageShiftSchema,
  manageWageSnapshotsSchema,
  manageWorkplaceSchema,
  queryFriendFeaturedShiftSchema,
  queryFriendShiftsSchema,
  queryShiftsSchema,
  tools as toolDefinitions,
} from "./tools.ts";
import { computeShift, PRESET_SUPPLEMENT_RULES } from "./payroll/index.ts";

type TariffVersion = {
  rates?: Record<string, number> | null;
};

function t(template: string, params: Record<string, string | number> = {}): string {
  return template.replace(/{(\w+)}/g, (_, key) => String(params[key] ?? `{${key}}`));
}

function toShortId(uuid: string): string {
  return uuid.slice(0, 5);
}

function toDisplayShiftId(shiftId: string): string {
  if (shiftId.startsWith("virtual-")) {
    const parts = shiftId.split("-");
    if (parts.length >= 9) {
      const recurringId = parts.slice(1, 6).join("-");
      const date = parts.slice(6).join("-");
      return `virtual-${toShortId(recurringId)}-${date}`;
    }
  }
  return toShortId(shiftId);
}

function isShortId(id: string): boolean {
  return /^[a-f0-9]{4,8}$/i.test(id) && !id.includes("-");
}

function formatDateCompact(isoDate: string): string {
  const date = new Date(`${isoDate}T12:00:00Z`);
  const monthKeys = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"] as const;
  return `${date.getUTCDate()} ${tr.months[monthKeys[date.getUTCMonth()]]}`;
}

function getWeekdayAbbr(isoDate: string): string {
  const date = new Date(`${isoDate}T12:00:00Z`);
  const weekdayKeys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as const;
  return tr.weekdays[weekdayKeys[date.getUTCDay()]];
}

function sortShiftsByDateDesc<T extends { shift_date: string; start_time: string }>(shifts: T[]): T[] {
  return shifts.sort((a, b) => {
    const dateDiff = b.shift_date.localeCompare(a.shift_date);
    if (dateDiff !== 0) return dateDiff;
    return b.start_time.localeCompare(a.start_time);
  });
}

function resolveShortIdFromShifts(shortOrFullId: string, shifts: { id: string }[]): string | null {
  if (shortOrFullId.startsWith("virtual-")) {
    if (shortOrFullId.split("-").length === 5) {
      const [, shortRecurringId, year, month, day] = shortOrFullId.split("-");
      const targetDate = `${year}-${month}-${day}`;
      const matches = shifts.filter((shift) => {
        if (!shift.id.startsWith("virtual-")) return false;
        const parts = shift.id.split("-");
        const recurringId = parts.slice(1, 6).join("-");
        const date = parts.slice(6).join("-");
        return recurringId.toLowerCase().startsWith(shortRecurringId.toLowerCase()) && date === targetDate;
      });
      return matches.length === 1 ? matches[0].id : null;
    }
    return shortOrFullId;
  }

  if (!isShortId(shortOrFullId)) return shortOrFullId;
  const matches = shifts.filter((shift) => shift.id.toLowerCase().startsWith(shortOrFullId.toLowerCase()));
  return matches.length === 1 ? matches[0].id : null;
}

function resolveShortIdsFromShifts(ids: string[], shifts: { id: string }[]): string[] {
  return ids
    .map((id) => resolveShortIdFromShifts(id, shifts))
    .filter((id): id is string => Boolean(id));
}

async function resolveRecurringId(
  ctx: WageyRequestContext,
  shortOrFullId: string,
): Promise<string | null> {
  if (!isShortId(shortOrFullId)) return shortOrFullId;
  const { data, error } = await ctx.supabase
    .from("recurring_shifts")
    .select("id")
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  const matches = (data ?? []).filter((row) => row.id.toLowerCase().startsWith(shortOrFullId.toLowerCase()));
  return matches.length === 1 ? matches[0].id : null;
}

async function resolveSnapshotId(ctx: WageyRequestContext, shortOrFullId: string): Promise<string | null> {
  if (!isShortId(shortOrFullId)) return shortOrFullId;
  const { data, error } = await ctx.supabase
    .from("wage_snapshots")
    .select("id")
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  const matches = (data ?? []).filter((row) => row.id.toLowerCase().startsWith(shortOrFullId.toLowerCase()));
  return matches.length === 1 ? matches[0].id : null;
}

function getCurrentWeekRange(): { startDate: string; endDate: string } {
  const now = new Date();
  const day = now.getUTCDay();
  const diffToMonday = day === 0 ? -6 : 1 - day;
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + diffToMonday));
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 6);
  return {
    startDate: start.toISOString().slice(0, 10),
    endDate: end.toISOString().slice(0, 10),
  };
}

function calculateNetPay(
  gross: number,
  taxSettings: { tax_enabled?: boolean; tax_percentage?: number },
  halfTaxMonth: number | null | undefined,
  shiftDate: string,
): number {
  if (!taxSettings.tax_enabled || !taxSettings.tax_percentage) {
    return gross;
  }
  let taxRate = taxSettings.tax_percentage / 100;
  if (halfTaxMonth) {
    const shiftMonth = new Date(`${shiftDate}T12:00:00Z`).getUTCMonth() + 1;
    const payoutMonth = shiftMonth === 12 ? 1 : shiftMonth + 1;
    if (payoutMonth === halfTaxMonth) {
      taxRate = taxRate / 2;
    }
  }
  return gross - gross * taxRate;
}

function getFriendDisplayName(friend: any): string {
  return friend.firstName?.trim() || friend.email || friend.phone || friend.id;
}

function frequencyToIntervalWeeks(frequency: string): 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 {
  switch (frequency) {
    case "weekly":
      return 0;
    case "biweekly":
      return 1;
    case "every_3_weeks":
      return 2;
    case "every_4_weeks":
      return 3;
    default:
      return 0;
  }
}

function intervalWeeksToFrequency(intervalWeeks: number): string {
  switch (intervalWeeks) {
    case 0:
      return "weekly";
    case 1:
      return "biweekly";
    case 2:
      return "every_3_weeks";
    case 3:
      return "every_4_weeks";
    default:
      return "weekly";
  }
}

function convertEndCondition(endType: string, endValue?: number | string): unknown {
  switch (endType) {
    case "never":
      return null;
    case "after_months":
      return { type: "months", value: typeof endValue === "number" ? endValue : 1 };
    case "after_years":
      return { type: "years", value: typeof endValue === "number" ? endValue : 1 };
    case "on_date":
      return { type: "end_date", date: typeof endValue === "string" ? endValue : "", end_time: "23:59:59" };
    default:
      return null;
  }
}

function weekdaysArrayToSelectedDays(
  weekdays: Array<{ day: number; anchorDate: string }>,
): Record<"0" | "1" | "2" | "3" | "4" | "5" | "6", string> {
  return weekdays.reduce((acc, { day, anchorDate }) => {
    acc[String(day) as keyof typeof acc] = anchorDate;
    return acc;
  }, {} as Record<"0" | "1" | "2" | "3" | "4" | "5" | "6", string>);
}

function formatEndConditionForAI(endCondition: any): { endType: string; endValue?: number | string } {
  if (endCondition === null) return { endType: "never" };
  switch (endCondition.type) {
    case "months":
      return { endType: "after_months", endValue: endCondition.value };
    case "years":
      return { endType: "after_years", endValue: endCondition.value };
    case "end_date":
      return { endType: "on_date", endValue: "date" in endCondition ? endCondition.date : endCondition.value };
    default:
      return { endType: "never" };
  }
}

function formatRecurringDescription(recurring: { selected_days?: Record<string, string>; start_time: string; end_time: string }): string {
  const weekdayKeys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as const;
  const dayNums = Object.keys(recurring.selected_days ?? {})
    .map(Number)
    .sort((a, b) => a - b);
  const daysStr = dayNums.map((day) => tr.weekdays[weekdayKeys[day]]).join("/");
  return `${daysStr} ${String(recurring.start_time).slice(0, 5)}-${String(recurring.end_time).slice(0, 5)}`;
}

function formatRecurringForAI(recurring: any): any {
  const weekdays = Object.entries(recurring.selected_days || {})
    .map(([day, anchorDate]) => ({ day: Number(day), anchorDate }))
    .sort((a, b) => a.day - b.day);
  const { endType, endValue } = formatEndConditionForAI(recurring.end_condition);
  return {
    recurringId: toShortId(recurring.id),
    weekdays,
    start: String(recurring.start_time).slice(0, 5),
    end: String(recurring.end_time).slice(0, 5),
    frequency: intervalWeeksToFrequency(recurring.repeat_interval_weeks),
    endType,
    endValue,
    exclusions: recurring.exclusions || [],
    createdAt: recurring.created_at,
  };
}

const KNOWN_TOOL_NAMES: ToolName[] = toolDefinitions.map((tool) => tool.name as ToolName);

function normalizeToolName(toolName: string): ToolName | null {
  const trimmed = toolName.trim();
  if (KNOWN_TOOL_NAMES.includes(trimmed as ToolName)) {
    return trimmed as ToolName;
  }
  return KNOWN_TOOL_NAMES.find((name) => trimmed.replace(/\s+/g, "").includes(name)) ?? null;
}

function sanitizeToolArgs(value: unknown): unknown {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length === 0 ? undefined : trimmed;
  }
  if (Array.isArray(value)) {
    return value.map(sanitizeToolArgs).filter((entry) => entry !== undefined);
  }
  if (value && typeof value === "object") {
    const sanitized: Record<string, unknown> = {};
    for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
      const next = sanitizeToolArgs(raw);
      if (next !== undefined) sanitized[key] = next;
    }
    return sanitized;
  }
  return value;
}

export async function executeTool(
  ctx: WageyRequestContext,
  toolName: string,
  argumentsJson: string,
): Promise<ToolResult> {
  try {
    const normalizedToolName = normalizeToolName(toolName);
    if (!normalizedToolName) {
      return { success: false, message: t(tr.unknownTool, { name: toolName }) };
    }

    const parsedArgs = argumentsJson.trim() === "" ? {} : JSON.parse(argumentsJson);
    const args = sanitizeToolArgs(parsedArgs);

    switch (normalizedToolName) {
      case "manage_shift":
        return await executeManageShift(ctx, args);
      case "query_shifts":
        return await executeQueryShifts(ctx, args);
      case "calculate_wages":
        return await executeCalculateWages(ctx, args);
      case "draft_recurring_shift":
        return await executeDraftRecurringShift(ctx, args);
      case "confirm_recurring_shift":
        return await executeConfirmRecurringShift(ctx, args);
      case "manage_recurring_shift":
        return await executeManageRecurringShift(ctx, args);
      case "manage_recurring_exclusion":
        return await executeManageRecurringExclusion(ctx, args);
      case "get_statistics":
        return await executeGetStatistics(ctx, args);
      case "manage_settings":
        return await executeManageSettings(ctx, args);
      case "manage_workplace":
        return await executeManageWorkplace(ctx, args);
      case "get_wage_info":
        return await executeGetWageInfo(ctx, args);
      case "manage_wage_snapshots":
        return await executeManageWageSnapshots(ctx, args);
      case "calculate_earnings":
        return await executeCalculateEarnings(ctx, args);
      case "list_workplaces":
        return await executeListWorkplaces(ctx, args);
      case "list_friends":
        return await executeListFriends(ctx, args);
      case "manage_friend_sharing":
        return await executeManageFriendSharing(ctx, args);
      case "query_friend_shifts":
        return await executeQueryFriendShifts(ctx, args);
      case "query_friend_featured_shift":
        return await executeQueryFriendFeaturedShift(ctx, args);
      case "manage_shift_advanced":
        return await executeManageShiftAdvanced(ctx, args);
      case "manage_feedback":
        return await executeManageFeedback(ctx, args);
      case "manage_profile":
        return await executeManageProfile(ctx, args);
      default:
        return { success: false, message: t(tr.unknownTool, { name: toolName }) };
    }
  } catch (error) {
    return {
      success: false,
      message: t(tr.failedAfterAttempts, {
        count: 1,
        error: error instanceof Error ? error.message : "Unknown error",
      }),
    };
  }
}

async function executeManageShift(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageShiftSchema.safeParse(args);
  if (!parsed.success) {
    return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  }

  const input = parsed.data as ManageShiftInput;
  switch (input.action) {
    case "create": {
      if (!input.dates || !input.start || !input.end) {
        return { success: false, message: t(tr.missingFields, { fields: "dates, start, end" }) };
      }
      const result = await createShifts(ctx, {
        dates: input.dates,
        start: input.start,
        end: input.end,
        jobId: input.jobId,
      });
      return {
        success: true,
        message: result.inserted === 1 ? t(tr.createdShift, { count: result.inserted }) : t(tr.createdShifts, { count: result.inserted }),
        data: result,
      };
    }
    case "update": {
      if (!input.shiftId) return { success: false, message: tr.missingShiftId };
      if (!input.date && !input.start && !input.end) return { success: false, message: tr.mustProvideDateStartEnd };
      const shifts = await getShiftIdentityRowsForApi(ctx, ctx.user.id, { limit: 1000 });
      const fullShiftId = resolveShortIdFromShifts(input.shiftId, shifts);
      if (!fullShiftId) return { success: false, message: t(tr.shiftNotFound, { id: input.shiftId }) };
      const shift = shifts.find((entry) => entry.id === fullShiftId);
      if (!shift) return { success: false, message: t(tr.shiftNotFound, { id: input.shiftId }) };
      await updateShift(ctx, {
        id: fullShiftId,
        shift_date: input.date || shift.shift_date,
        start: input.start || shift.start_time,
        end: input.end || shift.end_time,
        recurring_id: shift.recurring_id ?? undefined,
      });
      return { success: true, message: t(tr.updatedShift, { date: formatDateCompact(input.date || shift.shift_date) }) };
    }
    case "delete": {
      const shifts = await getShiftIdentityRowsForApi(ctx, ctx.user.id, { limit: 1000 });
      if (input.shiftIds && input.shiftIds.length > 0) {
        const fullIds = resolveShortIdsFromShifts(input.shiftIds, shifts);
        await Promise.all(fullIds.map((id) => deleteShift(ctx, id)));
        return { success: true, message: fullIds.length === 1 ? t(tr.deletedShift, { date: "" }).replace(" on ", " ") : t(tr.deletedShifts, { count: fullIds.length }) };
      }
      if (!input.shiftId) return { success: false, message: tr.missingShiftIdOrIds };
      const fullShiftId = resolveShortIdFromShifts(input.shiftId, shifts);
      if (!fullShiftId) return { success: false, message: t(tr.shiftNotFound, { id: input.shiftId }) };
      const shift = shifts.find((entry) => entry.id === fullShiftId);
      await deleteShift(ctx, fullShiftId);
      return { success: true, message: t(tr.deletedShift, { date: shift ? formatDateCompact(shift.shift_date) : tr.unknownDate }) };
    }
    default:
      return { success: false, message: t(tr.unknownAction, { action: input.action }) };
  }
}

async function executeQueryShifts(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = queryShiftsSchema.safeParse(args);
  if (!parsed.success) {
    return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  }
  const input = parsed.data as QueryShiftsInput;
  const weekRange = getCurrentWeekRange();
  const result = await getComputedShiftsForApi(ctx, ctx.user.id, {
    startDate: input.startDate ?? weekRange.startDate,
    endDate: input.endDate ?? weekRange.endDate,
    limit: 1000,
    jobId: input.jobId,
  });
  const jobMap = new Map(result.jobs.map((job) => [job.id, job.name]));
  let filtered = result.shifts;
  if (input.minTime) filtered = filtered.filter((shift) => shift.start_time >= input.minTime!);
  if (input.maxTime) filtered = filtered.filter((shift) => shift.start_time <= input.maxTime!);
  if (input.weekdays?.length) {
    filtered = filtered.filter((shift) => input.weekdays!.includes(new Date(`${shift.shift_date}T12:00:00Z`).getUTCDay()));
  }
  if (input.sortBy === "earnings") filtered = filtered.sort((a, b) => b.computed.gross - a.computed.gross);
  else if (input.sortBy === "hours") filtered = filtered.sort((a, b) => b.computed.paidHours - a.computed.paidHours);
  else if (input.sortBy === "date_earliest") filtered = filtered.sort((a, b) => a.shift_date.localeCompare(b.shift_date) || a.start_time.localeCompare(b.start_time));
  else filtered = sortShiftsByDateDesc(filtered);
  const limited = filtered.slice(0, input.limit || 30);
  const currency = await getUserCurrency(ctx);
  const hasTaxDeduction = limited.some((shift) => shift.tax_enabled && shift.tax_percentage);
  const data = limited.map((shift) => {
    const base = {
      id: toDisplayShiftId(shift.id),
      date: shift.shift_date,
      day: getWeekdayAbbr(shift.shift_date),
      start: shift.start_time,
      end: shift.end_time,
      hours: Number(shift.computed.paidHours.toFixed(2)),
      gross: Number(shift.computed.gross.toFixed(2)),
      workplace: shift.job_id ? (jobMap.get(shift.job_id) ?? null) : null,
    };
    if (!hasTaxDeduction) return base;
    return {
      ...base,
      net: Number(calculateNetPay(shift.computed.gross, { tax_enabled: shift.tax_enabled, tax_percentage: shift.tax_percentage }, result.settings.half_tax_month, shift.shift_date).toFixed(2)),
    };
  });
  const totalHours = limited.reduce((sum, shift) => sum + shift.computed.paidHours, 0);
  const totalGross = limited.reduce((sum, shift) => sum + shift.computed.gross, 0);
  const totalNet = limited.reduce((sum, shift) => sum + calculateNetPay(shift.computed.gross, { tax_enabled: shift.tax_enabled, tax_percentage: shift.tax_percentage }, result.settings.half_tax_month, shift.shift_date), 0);
  const shiftCount = limited.length;
  return {
    success: true,
    message: data.length === 1 ? t(tr.foundShift, { count: data.length }) : t(tr.foundShifts, { count: data.length }),
    data,
    summary: {
      shiftCount,
      totalHours: Number(totalHours.toFixed(2)),
      totalGross: Number(totalGross.toFixed(2)),
      totalNet: Number(totalNet.toFixed(2)),
      avgHoursPerShift: shiftCount > 0 ? Number((totalHours / shiftCount).toFixed(2)) : 0,
      avgGrossPerShift: shiftCount > 0 ? Number((totalGross / shiftCount).toFixed(2)) : 0,
    },
    currency,
  };
}

async function executeCalculateWages(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = calculateWagesSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as CalculateWagesInput;
  const result = await getComputedShiftsForApi(ctx, ctx.user.id, {
    startDate: input.startDate,
    endDate: input.endDate,
    limit: 1000,
    jobId: input.jobId,
  });
  const currency = await getUserCurrency(ctx);
  if (result.shifts.length === 0) {
    const period = input.startDate === input.endDate ? input.startDate : `${input.startDate} - ${input.endDate}`;
    return {
      success: true,
      message: t(tr.noShiftsFound, { period }),
      data: { totalShifts: 0, totalHours: 0, totalGross: 0, totalNet: 0, taxDeducted: 0 },
      currency,
    };
  }
  const totalHours = result.shifts.reduce((sum, shift) => sum + shift.computed.paidHours, 0);
  const totalGross = result.shifts.reduce((sum, shift) => sum + shift.computed.gross, 0);
  const totalNet = result.shifts.reduce((sum, shift) => sum + calculateNetPay(shift.computed.gross, { tax_enabled: shift.tax_enabled, tax_percentage: shift.tax_percentage }, result.settings.half_tax_month, shift.shift_date), 0);
  return {
    success: true,
    message: t(tr.calculatedWages, { count: result.shifts.length }),
    data: {
      totalShifts: result.shifts.length,
      totalHours: Number(totalHours.toFixed(2)),
      totalGross: Number(totalGross.toFixed(2)),
      totalNet: Number(totalNet.toFixed(2)),
      taxDeducted: Number((totalGross - totalNet).toFixed(2)),
    },
    currency,
  };
}

async function executeListWorkplaces(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = listWorkplacesSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ListWorkplacesInput;
  const jobs = await getUserJobs(ctx, ctx.user.id, { includeArchived: input.includeArchived });
  const archivedCount = jobs.filter((job) => job.archived_at).length;
  return {
    success: true,
    message: input.includeArchived
      ? t(tr.foundWorkplacesIncludingArchived, { count: jobs.length, archived: archivedCount })
      : jobs.length === 1
      ? t(tr.foundWorkplace, { count: jobs.length })
      : t(tr.foundWorkplaces, { count: jobs.length }),
    data: jobs.map((job) => ({
      id: job.id,
      name: job.name,
      color: job.color ?? null,
      isDefault: job.is_default,
      isArchived: Boolean(job.archived_at),
      archivedAt: job.archived_at ?? null,
    })),
  };
}

async function executeManageWorkplace(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageWorkplaceSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageWorkplaceInput;
  const jobs = await getUserJobs(ctx, ctx.user.id, { includeArchived: true });

  switch (input.action) {
    case "create": {
      const activeJobs = jobs.filter((job) => !job.archived_at);
      const created = await createJob(ctx, ctx.user.id, {
        name: input.name!.trim(),
        color: input.color ?? null,
        payroll_day: input.payrollDay ?? null,
        half_tax_month: input.halfTaxMonth ?? null,
        monthly_goal: input.monthlyGoal ?? null,
        sort_order: activeJobs.length === 0 ? 0 : Math.max(...activeJobs.map((job) => job.sort_order ?? 0)) + 1,
        is_default: activeJobs.length === 0,
      } as any);
      return {
        success: true,
        message: t(tr.createdWorkplaceNeedsWageSetup, { name: created.name }),
        data: { id: created.id, name: created.name, color: created.color ?? null, isDefault: created.is_default, isArchived: Boolean(created.archived_at) },
      };
    }
    case "update": {
      if (!input.jobId) return { success: false, message: tr.missingWorkplaceId };
      const updated = await updateJob(ctx, ctx.user.id, input.jobId, {
        ...(input.name !== undefined ? { name: input.name.trim() } : {}),
        ...(input.color !== undefined ? { color: input.color } : {}),
        ...(input.payrollDay !== undefined ? { payroll_day: input.payrollDay } : {}),
        ...(input.halfTaxMonth !== undefined ? { half_tax_month: input.halfTaxMonth } : {}),
        ...(input.monthlyGoal !== undefined ? { monthly_goal: input.monthlyGoal } : {}),
      } as any);
      return { success: true, message: t(tr.updatedWorkplace, { name: updated.name }), data: updated };
    }
    case "archive": {
      if (!input.jobId) return { success: false, message: tr.missingWorkplaceId };
      const target = jobs.find((job) => job.id === input.jobId);
      if (!target) return { success: false, message: t(tr.workplaceNotFound, { id: input.jobId }) };
      if (target.is_default) return { success: false, message: tr.cannotArchiveDefaultWorkplace };
      const activeCount = jobs.filter((job) => !job.archived_at).length;
      if (activeCount <= 1) return { success: false, message: tr.cannotArchiveLastActiveWorkplace };
      await archiveJob(ctx, ctx.user.id, input.jobId);
      return { success: true, message: t(tr.archivedWorkplace, { name: target.name }) };
    }
    case "unarchive": {
      if (!input.jobId) return { success: false, message: tr.missingWorkplaceId };
      const target = jobs.find((job) => job.id === input.jobId);
      if (!target) return { success: false, message: t(tr.workplaceNotFound, { id: input.jobId }) };
      const activeJobs = jobs.filter((job) => !job.archived_at);
      const updated = await updateJob(ctx, ctx.user.id, input.jobId, {
        archived_at: null,
        sort_order: activeJobs.length === 0 ? 0 : Math.max(...activeJobs.map((job) => job.sort_order ?? 0)) + 1,
      } as any);
      return { success: true, message: t(tr.unarchivedWorkplace, { name: target.name }), data: updated };
    }
    case "set_default": {
      if (!input.jobId) return { success: false, message: tr.missingWorkplaceId };
      const target = jobs.find((job) => job.id === input.jobId);
      if (!target) return { success: false, message: t(tr.workplaceNotFound, { id: input.jobId }) };
      await Promise.all(
        jobs.filter((job) => job.is_default && job.id !== input.jobId).map((job) => updateJob(ctx, ctx.user.id, job.id, { is_default: false } as any)),
      );
      await updateJob(ctx, ctx.user.id, input.jobId, { is_default: true } as any);
      return { success: true, message: t(tr.setDefaultWorkplace, { name: target.name }) };
    }
    case "reorder": {
      if (!input.jobId || !input.direction) return { success: false, message: !input.jobId ? tr.missingWorkplaceId : tr.missingDirection };
      const activeJobs = jobs.filter((job) => !job.archived_at).sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0));
      const index = activeJobs.findIndex((job) => job.id === input.jobId);
      if (index === -1) return { success: false, message: t(tr.workplaceNotFound, { id: input.jobId }) };
      const swapIndex = input.direction === "up" ? index - 1 : index + 1;
      if (swapIndex < 0 || swapIndex >= activeJobs.length) {
        return { success: true, message: t(tr.workplaceAlreadyAtEdge, { direction: input.direction }) };
      }
      const reordered = [...activeJobs];
      [reordered[index], reordered[swapIndex]] = [reordered[swapIndex], reordered[index]];
      await Promise.all(reordered.map((job, order) => updateJob(ctx, ctx.user.id, job.id, { sort_order: order } as any)));
      return { success: true, message: t(tr.reorderedWorkplace, { name: activeJobs[index].name, direction: input.direction }) };
    }
    case "delete": {
      if (!input.jobId) return { success: false, message: tr.missingWorkplaceId };
      const target = jobs.find((job) => job.id === input.jobId);
      if (!target) return { success: false, message: t(tr.workplaceNotFound, { id: input.jobId }) };
      if (target.is_default) return { success: false, message: tr.cannotDeleteDefaultWorkplace };
      if (jobs.filter((job) => !job.archived_at).length <= 1 && !target.archived_at) {
        return { success: false, message: tr.cannotDeleteLastActiveWorkplace };
      }
      await deleteJob(ctx, ctx.user.id, input.jobId);
      return { success: true, message: t(tr.deletedWorkplace, { name: target.name }) };
    }
    default:
      return { success: false, message: t(tr.unknownAction, { action: input.action }) };
  }
}

async function executeListFriends(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = listFriendsSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ListFriendsInput;
  const friends = await getAllFriends(ctx);
  const visible = input.includeBlocked ? friends : friends.filter((friend) => !(friend.sharesWithMe?.blocked ?? false));
  return {
    success: true,
    message: visible.length === 1 ? t(tr.foundFriend, { count: visible.length }) : t(tr.foundFriends, { count: visible.length }),
    data: visible.map((friend) => ({
      id: friend.id,
      name: getFriendDisplayName(friend),
      email: friend.email,
      phone: friend.phone,
      sharesWithMe: Boolean(friend.sharesWithMe),
      blocked: friend.sharesWithMe ? friend.sharesWithMe.blocked : null,
      showEarningsToMe: friend.sharesWithMe ? friend.sharesWithMe.showEarningsToMe : null,
      iShareWith: Boolean(friend.iShareWith),
    })),
  };
}

async function executeQueryFriendShifts(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = queryFriendShiftsSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as QueryFriendShiftsInput;
  const friends = await getAllFriends(ctx);
  const friend = friends.find((entry) => entry.id === input.friendId);
  if (!friend || !friend.sharesWithMe) {
    return { success: true, message: tr.friendNoAccess, data: { access: "no_access", friendId: input.friendId } };
  }
  const weekRange = getCurrentWeekRange();
  const shared = await getSharedUserShifts(ctx, input.friendId, {
    startDate: input.startDate ?? weekRange.startDate,
    endDate: input.endDate ?? weekRange.endDate,
    limit: 1000,
  });
  let filtered = shared.shifts;
  if (input.jobId) filtered = filtered.filter((shift) => shift.job_id === input.jobId);
  if (input.minTime) filtered = filtered.filter((shift) => shift.start_time >= input.minTime!);
  if (input.maxTime) filtered = filtered.filter((shift) => shift.start_time <= input.maxTime!);
  if (input.weekdays?.length) filtered = filtered.filter((shift) => input.weekdays!.includes(new Date(`${shift.shift_date}T12:00:00Z`).getUTCDay()));
  if (input.sortBy === "earnings") filtered = filtered.sort((a, b) => b.computed.gross - a.computed.gross);
  else if (input.sortBy === "hours") filtered = filtered.sort((a, b) => b.computed.paidHours - a.computed.paidHours);
  else if (input.sortBy === "date_earliest") filtered = filtered.sort((a, b) => a.shift_date.localeCompare(b.shift_date) || a.start_time.localeCompare(b.start_time));
  else filtered = sortShiftsByDateDesc(filtered);
  const limited = filtered.slice(0, input.limit || 30);
  const canShowEarnings = shared.showEarnings && friend.sharesWithMe.showEarningsToMe;
  const jobMap = new Map(shared.jobs.map((job) => [job.id, job.name]));
  const rows = limited.map((shift) => {
    const base = {
      id: toDisplayShiftId(shift.id),
      date: shift.shift_date,
      day: getWeekdayAbbr(shift.shift_date),
      start: shift.start_time,
      end: shift.end_time,
      hours: Number(shift.computed.paidHours.toFixed(2)),
      workplace: shift.job_id ? (jobMap.get(shift.job_id) ?? null) : null,
    };
    if (!canShowEarnings) return base;
    return {
      ...base,
      gross: Number(shift.computed.gross.toFixed(2)),
      net: Number(calculateNetPay(shift.computed.gross, { tax_enabled: shift.tax_enabled, tax_percentage: shift.tax_percentage }, shared.settings.half_tax_month, shift.shift_date).toFixed(2)),
    };
  });
  return {
    success: true,
    message: rows.length === 1 ? t(tr.foundFriendShift, { count: rows.length }) : t(tr.foundFriendShifts, { count: rows.length }),
    data: {
      friend: { id: friend.id, name: getFriendDisplayName(friend) },
      showEarningsToMe: canShowEarnings,
      shifts: rows,
      summary: {
        shiftCount: rows.length,
        totalHours: Number(limited.reduce((sum, shift) => sum + shift.computed.paidHours, 0).toFixed(2)),
        totalEarnings: canShowEarnings ? Number(limited.reduce((sum, shift) => sum + shift.computed.gross, 0).toFixed(2)) : null,
      },
    },
    currency: shared.settings.currency || "NOK",
  };
}

async function executeQueryFriendFeaturedShift(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = queryFriendFeaturedShiftSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as QueryFriendFeaturedShiftInput;
  const friends = await getAllFriends(ctx);
  const friend = friends.find((entry) => entry.id === input.friendId);
  if (!friend || !friend.sharesWithMe) {
    return { success: true, message: tr.friendNoAccess, data: { access: "no_access", friendId: input.friendId } };
  }
  const [preview] = await getSharerShiftPreviews(ctx, [input.friendId]);
  const canShowEarnings = Boolean(preview?.showEarnings && friend.sharesWithMe.showEarningsToMe);
  if (!preview?.shift) {
    return {
      success: true,
      message: tr.noFeaturedFriendShift,
      data: { access: "ok", friend: { id: friend.id, name: getFriendDisplayName(friend) }, status: preview?.status ?? null, showEarningsToMe: canShowEarnings, featuredShift: null },
    };
  }
  const base = {
    id: toDisplayShiftId(preview.shift.id),
    date: preview.shift.shift_date,
    day: getWeekdayAbbr(preview.shift.shift_date),
    start: preview.shift.start_time,
    end: preview.shift.end_time,
    hours: Number(preview.shift.computed.paidHours.toFixed(2)),
  };
  return {
    success: true,
    message: t(tr.foundFeaturedFriendShift, { status: preview.status ?? "none" }),
    data: {
      access: "ok",
      friend: { id: friend.id, name: getFriendDisplayName(friend) },
      status: preview.status,
      showEarningsToMe: canShowEarnings,
      featuredShift: canShowEarnings ? { ...base, gross: Number(preview.shift.computed.gross.toFixed(2)) } : base,
    },
  };
}

async function executeManageFriendSharing(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageFriendSharingSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageFriendSharingInput;
  const friends = await getAllFriends(ctx);
  const friend = input.friendId ? friends.find((entry) => entry.id === input.friendId) : null;

  switch (input.action) {
    case "share_by_identifier": {
      if (!input.identifier) return { success: false, message: tr.missingIdentifier };
      const result = await createShare(ctx, input.identifier, { showEarnings: input.showEarnings ?? false });
      return result.success ? { success: true, message: tr.friendShareCreated } : { success: false, message: result.error ?? tr.failedToManageFriendSharing };
    }
    case "share_back": {
      if (!input.friendId) return { success: false, message: tr.missingFriendId };
      if (!friend?.sharesWithMe) return { success: false, message: tr.friendMustShareWithMeFirst };
      const result = await shareBack(ctx, input.friendId);
      return result.success ? { success: true, message: t(tr.friendSharedBack, { name: getFriendDisplayName(friend) }) } : { success: false, message: result.error ?? tr.failedToManageFriendSharing };
    }
    case "remove_recipient": {
      if (!input.friendId) return { success: false, message: tr.missingFriendId };
      if (!friend?.iShareWith) return { success: false, message: tr.friendMustBeRecipient };
      await removeShare(ctx, input.friendId);
      return { success: true, message: t(tr.friendRecipientRemoved, { name: getFriendDisplayName(friend) }) };
    }
    case "toggle_recipient_earnings": {
      if (!input.friendId) return { success: false, message: tr.missingFriendId };
      if (input.showEarnings === undefined) return { success: false, message: tr.missingShowEarnings };
      if (!friend?.iShareWith) return { success: false, message: tr.friendMustBeRecipient };
      await toggleShareEarnings(ctx, input.friendId, input.showEarnings);
      return { success: true, message: input.showEarnings ? t(tr.friendRecipientEarningsEnabled, { name: getFriendDisplayName(friend) }) : t(tr.friendRecipientEarningsDisabled, { name: getFriendDisplayName(friend) }) };
    }
    case "block_sharer": {
      if (!input.friendId) return { success: false, message: tr.missingFriendId };
      if (!friend?.sharesWithMe) return { success: false, message: tr.friendMustBeSharer };
      await blockSharer(ctx, input.friendId);
      return { success: true, message: t(tr.friendSharerBlocked, { name: getFriendDisplayName(friend) }) };
    }
    case "unblock_sharer": {
      if (!input.friendId) return { success: false, message: tr.missingFriendId };
      await unblockSharer(ctx, input.friendId);
      return { success: true, message: t(tr.friendSharerUnblocked, { name: getFriendDisplayName(friend ?? { id: input.friendId }) }) };
    }
    case "set_sharer_muted": {
      if (!input.friendId) return { success: false, message: tr.missingFriendId };
      if (input.muted === undefined) return { success: false, message: tr.missingMuted };
      if (!friend?.sharesWithMe) return { success: false, message: tr.friendMustBeSharer };
      await toggleSharerMuted(ctx, input.friendId, input.muted);
      return { success: true, message: input.muted ? t(tr.friendSharerMuted, { name: getFriendDisplayName(friend ?? { id: input.friendId }) }) : t(tr.friendSharerUnmuted, { name: getFriendDisplayName(friend ?? { id: input.friendId }) }) };
    }
    case "remove_sharer": {
      if (!input.friendId) return { success: false, message: tr.missingFriendId };
      if (!friend?.sharesWithMe) return { success: false, message: tr.friendMustBeSharer };
      await removeSharer(ctx, input.friendId);
      return { success: true, message: t(tr.friendSharerRemoved, { name: getFriendDisplayName(friend ?? { id: input.friendId }) }) };
    }
    default:
      return { success: false, message: t(tr.unknownAction, { action: input.action }) };
  }
}

async function executeManageShiftAdvanced(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageShiftAdvancedSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageShiftAdvancedInput;
  switch (input.action) {
    case "copy_shifts": {
      if (!input.shiftIds?.length || !input.targetDate) return { success: false, message: t(tr.missingFields, { fields: "shiftIds, targetDate" }) };
      const result = await copyShifts(ctx, { shiftIds: input.shiftIds, targetDate: input.targetDate });
      return { success: true, message: t(tr.copiedShifts, { count: result.copied }), data: result };
    }
    case "update_custom_supplements": {
      if (!input.shiftId) return { success: false, message: tr.missingShiftId };
      const shifts = await getComputedShiftsForApi(ctx, ctx.user.id, { limit: 2000 });
      const fullShiftId = resolveShortIdFromShifts(input.shiftId, shifts.shifts);
      if (!fullShiftId) return { success: false, message: t(tr.shiftNotFound, { id: input.shiftId }) };
      const shift = shifts.shifts.find((entry) => entry.id === fullShiftId);
      if (!shift) return { success: false, message: t(tr.shiftNotFound, { id: input.shiftId }) };
      const result = await updateCustomSupplements(ctx, {
        shiftId: fullShiftId,
        customSupplements: input.customSupplements ?? null,
        recurringId: shift.recurring_id,
        shiftDate: shift.shift_date,
      });
      return { success: true, message: tr.updatedCustomSupplements, data: result };
    }
    case "convert_recurring_to_standalone": {
      if (!input.shiftId) return { success: false, message: tr.missingShiftId };
      const shifts = await getComputedShiftsForApi(ctx, ctx.user.id, { limit: 2000 });
      const fullShiftId = resolveShortIdFromShifts(input.shiftId, shifts.shifts);
      const shift = shifts.shifts.find((entry) => entry.id === fullShiftId);
      if (!fullShiftId || !shift || !shift.recurring_id) return { success: false, message: t(tr.shiftNotFound, { id: input.shiftId }) };
      await convertRecurringShiftToStandalone(ctx, {
        recurringId: shift.recurring_id,
        shiftDate: shift.shift_date,
        startTime: shift.start_time,
        endTime: shift.end_time,
      });
      return { success: true, message: tr.convertedRecurringShift };
    }
    case "move_recurring_occurrence": {
      if (!input.shiftId || !input.targetDate) return { success: false, message: t(tr.missingFields, { fields: "shiftId, targetDate" }) };
      const shifts = await getComputedShiftsForApi(ctx, ctx.user.id, { limit: 2000 });
      const fullShiftId = resolveShortIdFromShifts(input.shiftId, shifts.shifts);
      const shift = shifts.shifts.find((entry) => entry.id === fullShiftId);
      if (!fullShiftId || !shift || !shift.recurring_id) return { success: false, message: t(tr.shiftNotFound, { id: input.shiftId }) };
      await moveRecurringShift(ctx, {
        recurringId: shift.recurring_id,
        sourceDate: shift.shift_date,
        targetDate: input.targetDate,
        startTime: shift.start_time,
        endTime: shift.end_time,
      });
      return { success: true, message: tr.movedRecurringShift };
    }
    case "clear_shift_snapshots": {
      if (!input.shiftId) return { success: false, message: tr.missingShiftId };
      const shifts = await getShiftIdentityRowsForApi(ctx, ctx.user.id, { limit: 2000 });
      const fullShiftId = resolveShortIdFromShifts(input.shiftId, shifts);
      if (!fullShiftId) return { success: false, message: t(tr.shiftNotFound, { id: input.shiftId }) };
      const result = await clearShiftSnapshots(ctx, fullShiftId);
      return { success: true, message: tr.clearedShiftSnapshots, data: result };
    }
    default:
      return { success: false, message: t(tr.unknownAction, { action: input.action }) };
  }
}

async function executeManageFeedback(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageFeedbackSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageFeedbackInput;
  if (input.action === "submit") {
    if (!input.message?.trim()) return { success: false, message: tr.missingFeedbackMessage };
    await submitFeedback(ctx, input.message);
    return { success: true, message: tr.submittedFeedback };
  }
  const items = await getUserFeedback(ctx);
  return { success: true, message: t(tr.listedFeedback, { count: items.length }), data: items };
}

async function executeManageProfile(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageProfileSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageProfileInput;
  if (input.action === "view") {
    const metadata = ctx.user.user_metadata ?? {};
    return {
      success: true,
      message: tr.retrievedProfile,
      data: {
        id: ctx.user.id,
        firstName: (metadata.full_name as string) ?? (metadata.name as string) ?? null,
        email: ctx.user.email ?? null,
        phone: ctx.user.phone ?? null,
      },
    };
  }
  if (!input.firstName?.trim()) return { success: false, message: tr.emptyProfileName };
  await updateProfileSettings(ctx, { firstName: input.firstName.trim() });
  return { success: true, message: t(tr.updatedProfileName, { name: input.firstName.trim() }) };
}

async function executeDraftRecurringShift(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = draftRecurringShiftSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as DraftRecurringShiftInput;
  const result = await draftRecurringShift(ctx, {
    selected_days: weekdaysArrayToSelectedDays(input.weekdays),
    start_time: input.start,
    end_time: input.end,
    repeat_interval_weeks: frequencyToIntervalWeeks(input.frequency),
    end_condition: convertEndCondition(input.endType, input.endValue),
    exclusions: [],
  });
  return {
    success: true,
    message: result.conflictCount === 0 ? t(tr.validatedRecurring, { count: result.projectedShiftCount }) : t(tr.validatedRecurringConflicts, { count: result.projectedShiftCount, conflicts: result.conflictCount }),
    data: result,
  };
}

async function executeConfirmRecurringShift(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = confirmRecurringShiftSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ConfirmRecurringShiftInput;
  const result = await createRecurringShift(
    ctx,
    {
      selected_days: weekdaysArrayToSelectedDays(input.weekdays),
      start_time: input.start,
      end_time: input.end,
      repeat_interval_weeks: frequencyToIntervalWeeks(input.frequency),
      end_condition: convertEndCondition(input.endType, input.endValue),
      exclusions: [],
    },
    { conflictResolution: input.conflictResolution === "skip_conflicts" ? "exclude_conflicts" : "keep_existing" },
  );
  return { success: true, message: input.conflictResolution === "skip_conflicts" ? tr.recurringCreatedSkipped : tr.recurringCreatedKept, data: result };
}

async function executeManageRecurringShift(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageRecurringShiftSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageRecurringShiftInput;
  switch (input.action) {
    case "list": {
      if (input.recurringId) {
        const fullRecurringId = await resolveRecurringId(ctx, input.recurringId);
        if (!fullRecurringId) return { success: false, message: t(tr.recurringNotFound, { id: input.recurringId }) };
        const { data, error } = await ctx.supabase
          .from("recurring_shifts")
          .select("*")
          .eq("id", fullRecurringId)
          .eq("user_id", ctx.user.id)
          .is("deleted_at", null)
          .single();
        if (error || !data) return { success: false, message: t(tr.recurringNotFound, { id: input.recurringId }) };
        return { success: true, message: t(tr.foundRecurring, { description: formatRecurringDescription(data) }), data: [formatRecurringForAI(data)] };
      }
      const { data, error } = await ctx.supabase
        .from("recurring_shifts")
        .select("*")
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null)
        .order("created_at", { ascending: false });
      if (error) throw new Error(error.message);
      return { success: true, message: t(tr.foundRecurringCount, { count: (data ?? []).length }), data: (data ?? []).map(formatRecurringForAI) };
    }
    case "update": {
      if (!input.recurringId) return { success: false, message: tr.missingRecurringId };
      const fullRecurringId = await resolveRecurringId(ctx, input.recurringId);
      if (!fullRecurringId) return { success: false, message: t(tr.recurringNotFound, { id: input.recurringId }) };
      const { data: current, error } = await ctx.supabase
        .from("recurring_shifts")
        .select("*")
        .eq("id", fullRecurringId)
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null)
        .single();
      if (error || !current) return { success: false, message: t(tr.recurringNotFound, { id: input.recurringId }) };
      const selectedDays = input.weekdays ? weekdaysArrayToSelectedDays(input.weekdays) : current.selected_days;
      const updatedStartTime = input.start ?? String(current.start_time).slice(0, 5);
      const updatedEndTime = input.end ?? String(current.end_time).slice(0, 5);
      await updateRecurringShift(ctx, {
        id: fullRecurringId,
        selected_days: selectedDays,
        start_time: updatedStartTime,
        end_time: updatedEndTime,
        repeat_interval_weeks: input.frequency ? frequencyToIntervalWeeks(input.frequency) : current.repeat_interval_weeks,
        end_condition: input.endType !== undefined ? convertEndCondition(input.endType, input.endValue) : current.end_condition,
        exclusions: current.exclusions || [],
      });
      return { success: true, message: t(tr.updatedRecurring, { description: formatRecurringDescription({ selected_days: selectedDays, start_time: updatedStartTime, end_time: updatedEndTime }) }) };
    }
    case "delete": {
      if (!input.recurringId) return { success: false, message: tr.missingRecurringId };
      const fullRecurringId = await resolveRecurringId(ctx, input.recurringId);
      if (!fullRecurringId) return { success: false, message: t(tr.recurringNotFound, { id: input.recurringId }) };
      const { data } = await ctx.supabase
        .from("recurring_shifts")
        .select("selected_days, start_time, end_time")
        .eq("id", fullRecurringId)
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null)
        .single();
      await deleteRecurringShift(ctx, fullRecurringId);
      return { success: true, message: t(tr.deletedRecurring, { description: data ? formatRecurringDescription(data) : "unknown" }) };
    }
    default:
      return { success: false, message: t(tr.unknownAction, { action: input.action }) };
  }
}

async function executeManageRecurringExclusion(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageRecurringExclusionSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageRecurringExclusionInput;
  const fullRecurringId = await resolveRecurringId(ctx, input.recurringId);
  if (!fullRecurringId) return { success: false, message: t(tr.recurringNotFound, { id: input.recurringId }) };
  const { data, error } = await ctx.supabase
    .from("recurring_shifts")
    .select("exclusions, selected_days, start_time, end_time")
    .eq("id", fullRecurringId)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null)
    .single();
  if (error || !data) return { success: false, message: t(tr.recurringNotFound, { id: input.recurringId }) };
  const currentExclusions = (data.exclusions as string[]) || [];
  const exclusions = input.action === "add" ? Array.from(new Set([...currentExclusions, input.date])).sort() : currentExclusions.filter((date) => date !== input.date);
  const { error: updateError } = await ctx.supabase
    .from("recurring_shifts")
    .update({ exclusions })
    .eq("id", fullRecurringId)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (updateError) throw new Error(updateError.message);
  return { success: true, message: `${input.action === "add" ? "Excluded" : "Removed"} ${formatDateCompact(input.date)} ${input.action === "add" ? "from" : "in"} recurring shift (${formatRecurringDescription(data as any)})` };
}

async function executeGetStatistics(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = getStatisticsSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as GetStatisticsInput;
  const [currency, statsData] = await Promise.all([getUserCurrency(ctx), getStatistics(ctx, { year: input.year, month: input.month, jobId: input.jobId })]);
  let data: unknown;
  let message: string;
  switch (input.metric) {
    case "current_month":
      data = statsData.currentMonth;
      message = tr.statsCurrentMonth;
      break;
    case "last_month":
      data = statsData.lastMonth;
      message = tr.statsLastMonth;
      break;
    case "year_to_date":
      data = statsData.yearToDate;
      message = tr.statsYearToDate;
      break;
    case "full_year":
      data = statsData.fullYear;
      message = tr.statsFullYear;
      break;
    case "yearly_months":
      data = statsData.yearlyMonths;
      message = tr.statsYearlyMonths;
      break;
    case "this_week":
      data = statsData.thisWeek;
      message = tr.statsThisWeek;
      break;
    case "monthly_goal":
      data = statsData.monthlyGoal;
      message = tr.statsMonthlyGoal;
      break;
    case "supplement_breakdown":
      data = statsData.currentMonthBreakdown;
      message = tr.statsSupplementBreakdown;
      break;
    default:
      return { success: false, message: t(tr.unknownMetric, { metric: input.metric }) };
  }
  return { success: true, message, data, currency };
}

async function executeManageSettings(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageSettingsSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageSettingsInput;
  if (input.action === "update") {
    if (!input.category || !input.settings) return { success: false, message: tr.mustProvideCategoryAndSettings };
    switch (input.category) {
      case "display":
        await updateDisplaySettings(ctx, {
          ...(input.settings.theme !== undefined ? { theme: input.settings.theme } : {}),
          ...(input.settings.defaultShiftsView !== undefined ? { default_shifts_view: input.settings.defaultShiftsView } : {}),
          ...(input.settings.currency !== undefined ? { currency: input.settings.currency } : {}),
          ...(input.settings.showDashboardClockButtons !== undefined ? { show_dashboard_clock_buttons: input.settings.showDashboardClockButtons } : {}),
        });
        break;
      case "tax":
        await updatePaySettings(ctx, {
          ...(input.settings.halfTaxMonth !== undefined ? { half_tax_month: input.settings.halfTaxMonth } : {}),
        });
        break;
      case "goals":
        await updatePaySettings(ctx, {
          ...(input.settings.monthlyGoal !== undefined ? { monthly_goal: input.settings.monthlyGoal } : {}),
          ...(input.settings.payrollDay !== undefined ? { payroll_day: input.settings.payrollDay } : {}),
          ...(input.settings.monthlyGoalsByMonth !== undefined ? { monthly_goals_by_month: input.settings.monthlyGoalsByMonth } : {}),
        });
        break;
      case "preferences":
        await updatePreferencesSettings(ctx, {
          ...(input.settings.directTimeInput !== undefined ? { direct_time_input: input.settings.directTimeInput } : {}),
          ...(input.settings.fullMinuteRange !== undefined ? { full_minute_range: input.settings.fullMinuteRange } : {}),
          ...(input.settings.defaultStartupTab !== undefined ? { default_startup_tab: input.settings.defaultStartupTab } : {}),
        });
        break;
      default:
        return { success: false, message: t(tr.unknownCategory, { category: input.category }) };
    }
    return { success: true, message: t(tr.updatedSettings, { category: input.category }) };
  }
  const settings = await getUserSettings(ctx);
  const now = new Date();
  const monthKey = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
  const effectiveMonthlyGoal = settings.monthly_goals_by_month?.[monthKey] ?? settings.monthly_goal ?? null;
  return {
    success: true,
    message: tr.retrievedSettings,
    data: {
      display: {
        theme: settings.theme || "system",
        defaultShiftsView: settings.default_shifts_view || "calendar",
        currency: settings.currency || "kr",
        showDashboardClockButtons: settings.show_dashboard_clock_buttons ?? true,
      },
      tax: {
        halfTaxMonth: settings.half_tax_month,
      },
      goals: {
        monthlyGoal: effectiveMonthlyGoal,
        monthlyGoalBaseline: settings.monthly_goal ?? null,
        monthlyGoalForMonth: monthKey,
        monthlyGoalsByMonth: settings.monthly_goals_by_month ?? {},
        payrollDay: settings.payroll_day ?? null,
      },
      preferences: {
        directTimeInput: settings.direct_time_input ?? false,
        fullMinuteRange: settings.full_minute_range ?? false,
        defaultStartupTab: settings.default_startup_tab ?? "home",
      },
    },
  };
}

async function executeGetWageInfo(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = getWageInfoSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as GetWageInfoInput;

  const [settings, jobs, snapshots, tariffTypes] = await Promise.all([
    getUserSettings(ctx),
    getUserJobs(ctx, ctx.user.id, { includeArchived: true }),
    (async () => {
      const { data, error } = await ctx.supabase
        .from("wage_snapshots")
        .select("*")
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null)
        .order("from_date", { ascending: false, nullsFirst: false });
      if (error) throw new Error(error.message);
      return data ?? [];
    })(),
    getTariffTypes(ctx),
  ]);

  const selectedJob = input.jobId ? jobs.find((job) => job.id === input.jobId) ?? null : jobs.find((job) => job.is_default) ?? jobs[0] ?? null;
  if (input.jobId && !selectedJob) return { success: false, message: t(tr.workplaceNotFound, { id: input.jobId }) };
  let scopedSnapshots = selectedJob ? snapshots.filter((snapshot) => snapshot.job_id === selectedJob.id) : snapshots;
  if (selectedJob && scopedSnapshots.length === 0) scopedSnapshots = snapshots.filter((snapshot) => snapshot.job_id === null);

  if (scopedSnapshots.length === 0) {
    return {
      success: true,
      message: tr.noWageConfigured,
      data: {
        workplace: selectedJob ? { id: selectedJob.id, name: selectedJob.name, isDefault: selectedJob.is_default } : null,
        globalPaySettings: {
          halfTaxMonth: selectedJob?.half_tax_month ?? settings.half_tax_month ?? null,
          payrollDay: selectedJob?.payroll_day ?? settings.payroll_day ?? null,
          monthlyGoal: selectedJob?.monthly_goal ?? settings.monthly_goal ?? null,
        },
        tariffs: [],
        current: null,
      },
    };
  }

  const today = new Date().toISOString().slice(0, 10);
  const sorted = [...scopedSnapshots].sort((a, b) => (a.from_date === null ? -1 : b.from_date === null ? 1 : a.from_date.localeCompare(b.from_date)));
  const baseline = sorted.find((snapshot) => snapshot.from_date === null);
  const dated = sorted.filter((snapshot) => snapshot.from_date !== null);
  const pastAndCurrent = dated.filter((snapshot) => snapshot.from_date <= today);
  const currentSnapshot = pastAndCurrent[pastAndCurrent.length - 1] ?? baseline;
  const futureSnapshots = dated.filter((snapshot) => snapshot.from_date > today);
  const tariffMap = new Map(tariffTypes.map((tariff) => [tariff.id, tariff]));

  const compact = (snapshotsToFormat: any[], referenceSnapshot?: any) => {
    let prev = referenceSnapshot;
    return snapshotsToFormat.map((snapshot) => {
      const entry = {
        id: toShortId(snapshot.id),
        fromDate: snapshot.from_date,
        hourlyWage: snapshot.hourly_wage !== prev?.hourly_wage ? snapshot.hourly_wage : "unchanged",
        wageLevel: snapshot.wage_level !== prev?.wage_level ? snapshot.wage_level : "unchanged",
        usingTariff: (snapshot.wage_level !== null) !== (prev?.wage_level !== null) ? snapshot.wage_level !== null : "unchanged",
        tariffTypeId: snapshot.tariff_type_id !== (prev?.tariff_type_id ?? null) ? snapshot.tariff_type_id : "unchanged",
        tariff: snapshot.tariff_type_id !== (prev?.tariff_type_id ?? null) ? tariffMap.get(snapshot.tariff_type_id) ?? null : "unchanged",
        supplements: JSON.stringify(snapshot.supplements) !== JSON.stringify(prev?.supplements) ? snapshot.supplements?.rules ?? [] : "unchanged",
        taxEnabled: snapshot.tax_enabled !== prev?.tax_enabled ? snapshot.tax_enabled : "unchanged",
        taxPercentage: snapshot.tax_percentage !== prev?.tax_percentage ? snapshot.tax_percentage : "unchanged",
      };
      prev = snapshot;
      return entry;
    });
  };

  return {
    success: true,
    message: tr.retrievedWageInfo,
    data: {
      workplace: selectedJob ? { id: selectedJob.id, name: selectedJob.name, isDefault: selectedJob.is_default } : null,
      globalPaySettings: {
        halfTaxMonth: selectedJob?.half_tax_month ?? settings.half_tax_month ?? null,
        payrollDay: selectedJob?.payroll_day ?? settings.payroll_day ?? null,
        monthlyGoal: selectedJob?.monthly_goal ?? settings.monthly_goal ?? null,
      },
      tariffs: Array.from(new Map(scopedSnapshots.filter((snapshot) => snapshot.tariff_type_id).map((snapshot) => [snapshot.tariff_type_id, tariffMap.get(snapshot.tariff_type_id!) ?? null])).values()).filter(Boolean),
      current: currentSnapshot
        ? {
            id: toShortId(currentSnapshot.id),
            fromDate: currentSnapshot.from_date,
            usingTariff: currentSnapshot.wage_level !== null,
            wageLevel: currentSnapshot.wage_level,
            tariffTypeId: currentSnapshot.tariff_type_id,
            tariff: currentSnapshot.tariff_type_id ? tariffMap.get(currentSnapshot.tariff_type_id) ?? null : null,
            hourlyWage: currentSnapshot.hourly_wage,
            supplements: currentSnapshot.supplements?.rules ?? [],
            taxEnabled: currentSnapshot.tax_enabled,
            taxPercentage: currentSnapshot.tax_percentage,
          }
        : null,
      upcoming: futureSnapshots.length > 0 ? compact(futureSnapshots, currentSnapshot) : undefined,
      history: pastAndCurrent.length > 1 || baseline ? compact((baseline && currentSnapshot !== baseline ? [baseline, ...pastAndCurrent.slice(0, -1)] : pastAndCurrent.slice(0, -1)), undefined) : undefined,
    },
  };
}

async function executeManageWageSnapshots(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = manageWageSnapshotsSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as ManageWageSnapshotsInput;
  const DEFAULT_TARIFF_TYPE = "hk_retail";

  switch (input.action) {
    case "create": {
      if (input.from_date === undefined) return { success: false, message: tr.missingFromDate };
      let hourlyWage = input.hourly_wage ?? 200;
      let wageLevel = input.wage_level ?? null;
      let tariffTypeId: string | null = wageLevel !== null ? DEFAULT_TARIFF_TYPE : null;
      if (wageLevel !== null) {
        const tariffVersion = (input.from_date
          ? await getTariffVersionForDate(ctx, DEFAULT_TARIFF_TYPE, input.from_date)
          : await getLatestTariffVersion(ctx, DEFAULT_TARIFF_TYPE)) as TariffVersion | null;
        if (tariffVersion?.rates && tariffVersion.rates[String(wageLevel)] !== undefined) {
          hourlyWage = tariffVersion.rates[String(wageLevel)];
        }
      } else {
        tariffTypeId = null;
      }
      const { data, error } = await ctx.supabase
        .from("wage_snapshots")
        .insert({
          user_id: ctx.user.id,
          ...(input.jobId ? { job_id: input.jobId } : {}),
          from_date: input.from_date,
          hourly_wage: hourlyWage,
          wage_level: wageLevel,
          tariff_type_id: tariffTypeId,
          supplements: input.supplements ? { rules: input.supplements as any[] } : { rules: [] },
          tax_enabled: input.tax_enabled ?? false,
          tax_percentage: input.tax_percentage ?? 0,
          break_enabled: input.break_enabled ?? false,
          break_method: input.break_method ?? "none",
          break_threshold_hours: input.break_threshold_hours ?? 5.5,
          break_deduction_minutes: input.break_deduction_minutes ?? 30,
        })
        .select("id")
        .single();
      if (error || !data) {
        if (error?.code === "23505") return { success: false, message: tr.snapshotConflict };
        throw new Error(error?.message ?? "Failed to create wage snapshot");
      }
      return { success: true, message: t(tr.createdWageSnapshot, { date: input.from_date ? formatDateCompact(input.from_date) : "baseline" }), data: { id: toShortId(data.id) } };
    }
    case "update": {
      if (!input.snapshot_id) return { success: false, message: tr.missingSnapshotId };
      const fullSnapshotId = await resolveSnapshotId(ctx, input.snapshot_id);
      if (!fullSnapshotId) return { success: false, message: t(tr.snapshotNotFound, { id: input.snapshot_id }) };
      const { data: current, error } = await ctx.supabase
        .from("wage_snapshots")
        .select("*")
        .eq("id", fullSnapshotId)
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null)
        .single();
      if (error || !current) return { success: false, message: t(tr.snapshotNotFound, { id: input.snapshot_id }) };
      let hourlyWage = input.hourly_wage ?? current.hourly_wage;
      let wageLevel = input.wage_level !== undefined ? input.wage_level : current.wage_level;
      let tariffTypeId = wageLevel !== null ? DEFAULT_TARIFF_TYPE : null;
      if (wageLevel !== null) {
        const targetDate = input.from_date ?? current.from_date;
        const tariffVersion = (targetDate
          ? await getTariffVersionForDate(ctx, DEFAULT_TARIFF_TYPE, targetDate)
          : await getLatestTariffVersion(ctx, DEFAULT_TARIFF_TYPE)) as TariffVersion | null;
        if (tariffVersion?.rates && tariffVersion.rates[String(wageLevel)] !== undefined) {
          hourlyWage = tariffVersion.rates[String(wageLevel)];
        }
      }
      const { error: updateError } = await ctx.supabase
        .from("wage_snapshots")
        .update({
          from_date: input.from_date !== undefined ? input.from_date : current.from_date,
          hourly_wage: hourlyWage,
          wage_level: wageLevel,
          tariff_type_id: tariffTypeId,
          supplements: input.supplements ? { rules: input.supplements as any[] } : current.supplements,
          tax_enabled: input.tax_enabled ?? current.tax_enabled,
          tax_percentage: input.tax_percentage ?? current.tax_percentage,
          break_enabled: input.break_enabled ?? current.break_enabled,
          break_method: input.break_method ?? current.break_method,
          break_threshold_hours: input.break_threshold_hours ?? current.break_threshold_hours,
          break_deduction_minutes: input.break_deduction_minutes ?? current.break_deduction_minutes,
        })
        .eq("id", fullSnapshotId)
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null);
      if (updateError) {
        if (updateError.code === "23505") return { success: false, message: tr.snapshotConflict };
        throw new Error(updateError.message);
      }
      return { success: true, message: tr.updatedWageSnapshot };
    }
    case "delete": {
      if (!input.snapshot_id) return { success: false, message: tr.missingSnapshotId };
      const fullSnapshotId = await resolveSnapshotId(ctx, input.snapshot_id);
      if (!fullSnapshotId) return { success: false, message: t(tr.snapshotNotFound, { id: input.snapshot_id }) };
      const { data: snapshot, error } = await ctx.supabase
        .from("wage_snapshots")
        .select("id, from_date, job_id")
        .eq("id", fullSnapshotId)
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null)
        .single();
      if (error || !snapshot) return { success: false, message: t(tr.snapshotNotFound, { id: input.snapshot_id }) };
      const shifts = await getComputedShiftsForApi(ctx, ctx.user.id, { startDate: snapshot.from_date ?? "1900-01-01", endDate: "2100-12-31", limit: 5000, jobId: snapshot.job_id ?? undefined });
      const affectedShiftCount = shifts.shifts.filter((shift) => shift.shift_date >= (snapshot.from_date ?? "1900-01-01")).length;
      const { error: deleteError } = await ctx.supabase
        .from("wage_snapshots")
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", fullSnapshotId)
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null);
      if (deleteError) throw new Error(deleteError.message);
      return { success: true, message: t(tr.deletedWageSnapshot, { count: affectedShiftCount }) };
    }
    default:
      return { success: false, message: t(tr.unknownAction, { action: input.action }) };
  }
}

async function executeCalculateEarnings(ctx: WageyRequestContext, args: unknown): Promise<ToolResult> {
  const parsed = calculateEarningsSchema.safeParse(args);
  if (!parsed.success) return { success: false, message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }) };
  const input = parsed.data as CalculateEarningsInput;
  const settings = await getUserSettings(ctx);
  const currency = await getUserCurrency(ctx);

  const computeHypotheticalShift = async (date: string, startTime: string, endTime: string, label?: string) => {
    const { data: snapshots, error } = await ctx.supabase
      .from("wage_snapshots")
      .select("*")
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null)
      .order("from_date", { ascending: false, nullsFirst: false });
    if (error) throw new Error(error.message);
    const snapshotList = snapshots ?? [];
    const currentSnapshot =
      snapshotList.find((snapshot) => snapshot.from_date !== null && snapshot.from_date <= date) ??
      snapshotList.find((snapshot) => snapshot.from_date === null) ??
      null;
    const payrollDay = settings.payroll_day ?? 15;
    const payoutDate = (() => {
      const [year, month] = date.split("-").map(Number);
      let payoutYear = year;
      let payoutMonth = month + 1;
      if (payoutMonth > 12) {
        payoutMonth = 1;
        payoutYear += 1;
      }
      const daysInMonth = new Date(Date.UTC(payoutYear, payoutMonth, 0)).getUTCDate();
      return `${payoutYear}-${String(payoutMonth).padStart(2, "0")}-${String(Math.min(payrollDay, daysInMonth)).padStart(2, "0")}`;
    })();
    const taxSnapshot =
      snapshotList.find((snapshot) => snapshot.from_date !== null && snapshot.from_date <= payoutDate) ??
      snapshotList.find((snapshot) => snapshot.from_date === null) ??
      null;
    const computed = computeShift(
      {
        id: `hypothetical-${Date.now()}`,
        user_id: ctx.user.id,
        shift_date: date,
        start_time: startTime,
        end_time: endTime,
      },
      settings,
      PRESET_SUPPLEMENT_RULES,
      currentSnapshot,
      null,
    );
    return {
      label: label || `${getWeekdayAbbr(date)} ${formatDateCompact(date)}`,
      date,
      weekday: getWeekdayAbbr(date),
      start_time: startTime,
      end_time: endTime,
      duration_hours: Number(computed.durationHours.toFixed(2)),
      paid_hours: Number(computed.paidHours.toFixed(2)),
      gross: Number(computed.gross.toFixed(2)),
      net: Number(calculateNetPay(computed.gross, { tax_enabled: taxSnapshot?.tax_enabled, tax_percentage: taxSnapshot?.tax_percentage }, settings.half_tax_month, date).toFixed(2)),
      breakdown: {
        base_pay: Number(computed.basePay.toFixed(2)),
        supplement_pay: Number(computed.supplementPay.toFixed(2)),
        break_deducted_minutes: Number((computed.breakAudit.deductedHours * 60).toFixed(0)),
      },
    };
  };

  if (input.hypothetical) {
    const result = await computeHypotheticalShift(input.hypothetical.date, input.hypothetical.start_time, input.hypothetical.end_time, input.hypothetical.label);
    return { success: true, message: t(tr.calculatedHypothetical, { label: result.label }), data: { scenarios: [result] }, currency };
  }

  if (input.compare) {
    const scenarios = await Promise.all(input.compare.map((scenario) => computeHypotheticalShift(scenario.date, scenario.start_time, scenario.end_time, scenario.label)));
    const sorted = [...scenarios].sort((a, b) => b.gross - a.gross);
    return {
      success: true,
      message: t(tr.comparedScenarios, { count: scenarios.length }),
      data: {
        scenarios,
        comparison: {
          best_option: sorted[0].label,
          worst_option: sorted[sorted.length - 1].label,
          difference: Number((sorted[0].gross - sorted[sorted.length - 1].gross).toFixed(2)),
          summary: `"${sorted[0].label}" earns ${Number((sorted[0].gross - sorted[sorted.length - 1].gross).toFixed(2))} ${currency} more`,
        },
      },
      currency,
    };
  }

  if (input.hypothetical_change) {
    const shifts = await getComputedShiftsForApi(ctx, ctx.user.id, { startDate: "2000-01-01", endDate: "2100-12-31", limit: 5000 });
    const fullShiftId = resolveShortIdFromShifts(input.hypothetical_change.shift_id, shifts.shifts);
    const originalShift = shifts.shifts.find((shift) => shift.id === fullShiftId);
    if (!fullShiftId || !originalShift) return { success: false, message: t(tr.shiftNotFound, { id: input.hypothetical_change.shift_id }) };
    const original = await computeHypotheticalShift(originalShift.shift_date, originalShift.start_time, originalShift.end_time, "Original");
    const modified = await computeHypotheticalShift(input.hypothetical_change.changes.date || originalShift.shift_date, input.hypothetical_change.changes.start_time || originalShift.start_time, input.hypothetical_change.changes.end_time || originalShift.end_time, "Modified");
    const difference = Number((modified.gross - original.gross).toFixed(2));
    return { success: true, message: t(tr.calculatedChange, { difference }), data: { original, modified, difference, difference_net: Number((modified.net - original.net).toFixed(2)) }, currency };
  }

  return { success: false, message: tr.mustSpecifyMode };
}
