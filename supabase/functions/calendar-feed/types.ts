import type {
  EndCondition,
  SelectedDays,
} from "../_shared/wagey/recurring/types.ts";

export type CalendarSubscriptionContentMode =
  | "events_only"
  | "shifts_only"
  | "shifts_and_events";

export type CalendarFeedLocale =
  | "ar"
  | "bg"
  | "bn"
  | "ca"
  | "cs"
  | "da"
  | "de"
  | "el"
  | "en"
  | "es"
  | "et"
  | "fa"
  | "fi"
  | "fil"
  | "fr"
  | "he"
  | "hi"
  | "hr"
  | "hu"
  | "id"
  | "is"
  | "it"
  | "ja"
  | "ko"
  | "lt"
  | "lv"
  | "nb"
  | "nl"
  | "nn"
  | "pl"
  | "pt"
  | "pt-br"
  | "ro"
  | "ru"
  | "sk"
  | "sl"
  | "sr"
  | "sv"
  | "sw"
  | "ta"
  | "th"
  | "tr"
  | "uk"
  | "ur"
  | "vi"
  | "zh"
  | "zh-hans"
  | "zh-hant";

export type FeedWindow = {
  startDate: string;
  endDate: string;
};

export type CalendarJobRow = {
  id: string;
  name: string;
};

export type CalendarShiftRow = {
  id: string;
  shift_date: string;
  start_time: string;
  end_time: string;
  note: string | null;
  job_id: string | null;
  updated_at: string | null;
};

export type CalendarRecurringShiftRow = {
  id: string;
  start_time: string;
  end_time: string;
  repeat_interval_weeks: number;
  selected_days: SelectedDays;
  end_condition: EndCondition;
  exclusions: string[] | null;
  date_specific_notes: Record<string, string> | null;
  job_id: string | null;
  updated_at: string | null;
};

export type CalendarEventRow = {
  id: string;
  start_date: string;
  end_date: string;
  is_all_day: boolean;
  start_time: string | null;
  end_time: string | null;
  note: string;
  updated_at: string | null;
};

export type CalendarData = {
  jobs: CalendarJobRow[];
  shifts: CalendarShiftRow[];
  recurringShifts: CalendarRecurringShiftRow[];
  events: CalendarEventRow[];
};

export type ProjectedRecurringShift = {
  id: string;
  occurrenceDate: string;
  start_time: string;
  end_time: string;
  note: string | null;
  job_id: string | null;
  updated_at: string | null;
};

export type CalendarSupabaseClient = {
  from: (table: string) => unknown;
  rpc: (functionName: string, args: Record<string, unknown>) => unknown;
};
