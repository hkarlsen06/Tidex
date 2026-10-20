import { chars, reject, requireLiveJob, syncedTable } from "./lib/syncWrite";

const within = (value: string | undefined, max: number) => value === undefined || chars(value) <= max;
const trimmedWithin = (value: string | undefined, max: number) =>
  value === undefined || (chars(value.trim()) >= 1 && chars(value.trim()) <= max);

export const { insert, update, remove } = syncedTable("payroll_adjustments", {
  check: async (ctx, adjustment, _prev, changed) => {
    if (changed.has("job_id") && adjustment.job_id !== undefined) {
      await requireLiveJob(ctx, adjustment.user_id, adjustment.job_id);
    }
    const a = adjustment;
    const broken = [
      [trimmedWithin(a.currency, 12), "payroll_adjustments_currency_check"],
      [trimmedWithin(a.description, 240), "payroll_adjustments_description_check"],
      [within(a.note, 1000), "payroll_adjustments_note_check"],
      [within(a.curated_note, 1000), "payroll_adjustments_curated_note_check"],
      [within(a.curated_description, 2000), "payroll_adjustments_curated_description_check"],
      [trimmedWithin(a.curated_link, 2048), "payroll_adjustments_curated_link_check"],
      [trimmedWithin(a.curated_link_title, 120), "payroll_adjustments_curated_link_title_check"],
      [
        a.earned_from_date === undefined ||
          a.earned_to_date === undefined ||
          a.earned_from_date <= a.earned_to_date,
        "payroll_adjustments_earned_range_check",
      ],
    ] as const;
    const failed = broken.find(([ok]) => !ok);
    if (failed !== undefined) reject("invalid_row", failed[1]);
  },
});
