// calendar.utils.ts
export const toISODate = (d: Date): `${number}-${number}-${number}` =>
  d.toISOString().slice(0, 10) as `${number}-${number}-${number}`;

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
