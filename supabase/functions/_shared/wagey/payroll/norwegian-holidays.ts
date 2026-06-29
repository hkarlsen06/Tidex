export type NorwegianHoliday = {
  date: string;
  nameNO: string;
  nameEN: string;
};

const easterDates: Record<number, { month: number; day: number }> = {
  2025: { month: 4, day: 20 },
  2026: { month: 4, day: 5 },
  2027: { month: 3, day: 28 },
  2028: { month: 4, day: 16 },
  2029: { month: 4, day: 1 },
  2030: { month: 4, day: 21 },
};

const cache = new Map<number, NorwegianHoliday[]>();

export function isNorwegianPublicHoliday(date: Date): boolean {
  const iso = formatDateISO(date);
  return getNorwegianHolidays(date.getUTCFullYear()).some((holiday) =>
    holiday.date === iso
  );
}

export function getNorwegianHolidays(year: number): NorwegianHoliday[] {
  const cached = cache.get(year);
  if (cached) return cached;

  const easter = calculateEaster(year);
  const holidays: NorwegianHoliday[] = [
    {
      date: `${year}-01-01`,
      nameNO: "Forste nyttarsdag",
      nameEN: "New Year's Day",
    },
    { date: `${year}-05-01`, nameNO: "Forste mai", nameEN: "Labour Day" },
    {
      date: `${year}-05-17`,
      nameNO: "Grunnlovsdag",
      nameEN: "Constitution Day",
    },
    {
      date: `${year}-12-25`,
      nameNO: "Forste juledag",
      nameEN: "Christmas Day",
    },
    { date: `${year}-12-26`, nameNO: "Andre juledag", nameEN: "Boxing Day" },
    {
      date: formatDateISO(addDays(easter, -3)),
      nameNO: "Skjaertorsdag",
      nameEN: "Maundy Thursday",
    },
    {
      date: formatDateISO(addDays(easter, -2)),
      nameNO: "Langfredag",
      nameEN: "Good Friday",
    },
    {
      date: formatDateISO(easter),
      nameNO: "Forste paskedag",
      nameEN: "Easter Sunday",
    },
    {
      date: formatDateISO(addDays(easter, 1)),
      nameNO: "Andre paskedag",
      nameEN: "Easter Monday",
    },
    {
      date: formatDateISO(addDays(easter, 39)),
      nameNO: "Kristi himmelfartsdag",
      nameEN: "Ascension Day",
    },
    {
      date: formatDateISO(addDays(easter, 49)),
      nameNO: "Forste pinsedag",
      nameEN: "Whit Sunday",
    },
    {
      date: formatDateISO(addDays(easter, 50)),
      nameNO: "Andre pinsedag",
      nameEN: "Whit Monday",
    },
  ].sort((a, b) => a.date.localeCompare(b.date));

  cache.set(year, holidays);
  return holidays;
}

function calculateEaster(year: number): Date {
  const known = easterDates[year];
  if (known) {
    return new Date(Date.UTC(year, known.month - 1, known.day, 12));
  }

  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(Date.UTC(year, month - 1, day, 12));
}

function addDays(date: Date, days: number): Date {
  const copy = new Date(date.getTime());
  copy.setUTCDate(copy.getUTCDate() + days);
  return copy;
}

function formatDateISO(date: Date): string {
  return date.toISOString().slice(0, 10);
}
