// calendar.utils.ts
export type ISODate = `${number}-${number}-${number}`;

export const toISODate = (d: Date): ISODate =>
  d.toISOString().slice(0, 10) as ISODate;

export const formatNOKInt = (n: number) =>
  new Intl.NumberFormat("nb-NO", { maximumFractionDigits: 0 }).format(n);

export const initials = (name: string) =>
  name
    .trim()
    .split(/\s+/)
    .map((s) => s[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
