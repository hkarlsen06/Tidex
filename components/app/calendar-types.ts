// calendar.types.ts
export type ISODate = `${number}-${number}-${number}`; // YYYY-MM-DD

export type Shift = {
  id: string;
  date: ISODate;
  start: string; // "HH:MM"
  end: string; // "HH:MM"
  employee?: { id: string; name: string; color?: string };
};

export type EarningsByDate = Record<ISODate, number>;
export type HoursByDate = Record<
  ISODate,
  { start?: string; end?: string; crossesMidnight?: boolean }
>;
