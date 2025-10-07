// calendar.utils.ts
export type ISODate = `${number}-${number}-${number}`;

export const toISODate = (d: Date): ISODate => {
  // Format using local time to avoid timezone shifting the date
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}` as ISODate;
};

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
