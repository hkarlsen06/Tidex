import { Metadata } from 'next';
import { PayrollDocsPage } from './PayrollDocsPage';

export const metadata: Metadata = {
  title: 'Payroll Engine Specification - How Tidex calculates your pay',
  description:
    'Complete technical specification for the Tidex payroll engine. Enables re-implementation in any language with identical results.',
  openGraph: {
    title: 'Payroll Engine Specification - How Tidex calculates your pay',
    description:
      'Complete technical specification for the Tidex payroll engine. Enables re-implementation in any language with identical results.',
  },
  twitter: {
    title: 'Payroll Engine Specification - How Tidex calculates your pay',
    description:
      'Complete technical specification for the Tidex payroll engine. Enables re-implementation in any language with identical results.',
  },
};

// Comprehensive payroll documentation based on PAYROLL_ENGINE_SPEC.md
const payrollDocs = {
  badge: 'PAYROLL ENGINE SPECIFICATION V2.0',
  title: 'How Tidex calculates your pay',
  subtitle:
    'A transparent, auditable reference for every payroll rule we apply. This specification enables re-implementation in any language (Swift, Kotlin, Go, etc.) with identical results.',

  navigation: [
    { id: 'overview', label: 'Overview' },
    { id: 'data-model', label: 'Data Model' },
    { id: 'pipeline', label: 'Shift Pipeline' },
    { id: 'snapshots', label: 'Snapshots & Payout' },
    { id: 'calculation', label: 'Calculation Engine' },
    { id: 'breaks', label: 'Break Deductions' },
    { id: 'aggregations', label: 'Aggregations' },
    { id: 'test-vectors', label: 'Test Vectors' },
  ],

  bugReportCta: {
    heading: 'Notice an inconsistency?',
    description: 'Flag potential discrepancies directly to the payroll engineering team.',
    buttonText: 'Email the payroll team',
    emailSubject: 'Payroll calculation discrepancy',
    emailBody:
      'Hello Tidex payroll team. I believe there may be an issue with the payroll calculation engine:'
  },

  sections: [
    {
      id: 'overview',
      title: 'Overview',
      subsections: [
        {
          heading: 'What the payroll engine does',
          paragraphs: [
            'The Tidex payroll engine computes wage earnings for work shifts. It takes shift data (date, start/end time) and wage settings (hourly rate, supplements, tax, break deductions) to produce deterministic earnings values.',
          ],
        },
        {
          heading: 'Inputs',
          list: [
            'Shift data: shift_date (ISO), start_time (HH:MM), end_time (HH:MM), optional custom supplements',
            'Wage snapshot: Hourly wage, supplement rules, tax settings, break deduction settings',
            'User settings: Payroll day, half-tax month, monthly goal',
          ],
        },
        {
          heading: 'Outputs',
          list: [
            'computeShift output: durationHours, paidHours, basePay, supplementPay, gross, wagePeriods, originalWagePeriods, breakAudit',
            'Downstream totals output: taxAmount and net (calculated outside computeShift)',
          ],
        },
        {
          heading: 'Key invariants',
          list: [
            'Deterministic: Same inputs always produce same outputs',
            'Pure computation: Zero I/O, all inputs explicit',
            'Cross-midnight support: Shifts spanning midnight are calculated as continuous time',
            'Dual-date snapshot logic: Wage/supplements/breaks use shift date; tax uses payout date',
            'Precision: 3 decimal places for hours, 2 decimal places for currency',
          ],
        },
        {
          heading: 'Definitions',
          table: {
            caption: 'Key terminology',
            headers: ['Term', 'Definition'],
            rows: [
              ['Shift', 'A stored work period with date, start time, end time'],
              ['Virtual shift', 'A computed occurrence from a recurring shift template (not persisted)'],
              ['Wage snapshot', 'Point-in-time capture of wage, supplement, tax, and break settings'],
              ['Baseline snapshot', 'Snapshot with from_date = NULL, serves as fallback'],
              ['Supplement window', 'Time-of-day range when a supplement rate applies'],
              ['Payout date', 'Date when wages are paid (typically month after work + payroll day)'],
              ['Payroll period', 'The calendar month whose earnings are grouped for a payout'],
              ['Month grouping', 'Shifts worked in month M are paid in month M+1'],
            ],
          },
        },
        {
          heading: 'Entry points',
          paragraphs: ['The payroll engine can be called in two ways:'],
          code: {
            language: 'typescript',
            content: `// Pure function (core calculation)
computeShift(shift, settings, presetRules, snapshot) // from @/lib/payroll/calc.ts

// Effect-wrapped (with validation)
computeShift(shift, settings, presetRules, snapshot) // from @/lib/payroll/effect.ts (returns Effect<ShiftComputed, ValidationError>)`,
          },
        },
      ],
    },
    {
      id: 'data-model',
      title: 'Data Model & Schema',
      subsections: [
        {
          heading: 'user_shifts - Core shift data',
          paragraphs: ['Each shift is stored with the following structure:'],
          table: {
            caption: 'user_shifts table schema',
            headers: ['Column', 'Type', 'Purpose'],
            rows: [
              ['id', 'uuid', 'Primary key, unique shift identifier'],
              ['user_id', 'uuid', 'Foreign key to auth.users'],
              ['shift_date', 'date', 'The date of the shift (ISO: YYYY-MM-DD)'],
              ['start_time', 'text', 'Start time in HH:MM format'],
              ['end_time', 'text', 'End time in HH:MM format (supports cross-midnight)'],
              ['custom_supplements', 'jsonb', 'Shift-specific supplement overrides'],
            ],
          },
          note: 'When end_time <= start_time, shift crosses midnight (e.g., 22:00 to 06:00). Custom supplements when present completely replace snapshot supplements for this shift.',
        },
        {
          heading: 'recurring_shifts - Recurring shift templates',
          paragraphs: ['Recurring shifts generate virtual shifts at runtime:'],
          table: {
            caption: 'recurring_shifts table schema',
            headers: ['Column', 'Type', 'Purpose'],
            rows: [
              ['id', 'uuid', 'Primary key'],
              ['user_id', 'uuid', 'Foreign key to auth.users'],
              ['start_time', 'timetz', 'Shift start time with timezone'],
              ['end_time', 'timetz', 'Shift end time with timezone'],
              ['repeat_interval_weeks', 'smallint', '0 = every week, 1 = every 2 weeks, ..., 8 = every 9 weeks'],
              ['selected_days', 'jsonb', 'Anchor dates by weekday: { "1": "2025-01-27" }'],
              ['end_condition', 'jsonb', 'End rule: { type: "never" | "months" | "years" | "end_date" }'],
              ['exclusions', 'jsonb', 'Array of ISO dates to skip'],
              ['date_specific_supplements', 'jsonb', 'Per-date custom supplements'],
            ],
          },
          note: 'Virtual shifts are generated at runtime, never persisted. selected_days keys are weekday numbers (0=Sunday to 6=Saturday).',
        },
        {
          heading: 'wage_snapshots - Point-in-time wage settings',
          paragraphs: ['Wage snapshots preserve historical wage accuracy:'],
          table: {
            caption: 'wage_snapshots table schema',
            headers: ['Column', 'Type', 'Default', 'Purpose'],
            rows: [
              ['id', 'uuid', '-', 'Primary key'],
              ['user_id', 'uuid', '-', 'Foreign key to auth.users'],
              ['from_date', 'date', '-', 'Effective date (NULL = baseline snapshot)'],
              ['hourly_wage', 'numeric', '-', 'Base hourly wage in NOK'],
              ['wage_level', 'integer', '-', 'Tariff level (1-9) or NULL for custom'],
              ['supplements', 'jsonb', '[]', 'Array of SupplementRule objects'],
              ['tax_enabled', 'boolean', 'false', 'Whether tax deduction is enabled'],
              ['tax_percentage', 'numeric', '0', 'Tax percentage (0-100)'],
              ['break_enabled', 'boolean', 'true', 'Whether break deduction is enabled'],
              ['break_method', 'text', 'proportional', 'One of: proportional, base_only, end_of_shift, none'],
              ['break_threshold_hours', 'numeric', '5.5', 'Hours before break applies'],
              ['break_deduction_minutes', 'integer', '30', 'Break duration in minutes'],
            ],
          },
          note: 'Only one baseline snapshot (from_date = NULL) allowed per user. Snapshot selection uses shift date for wage/supplements/breaks, but payout date for tax settings.',
        },
        {
          heading: 'user_settings - User preferences',
          paragraphs: ['User preferences affecting payroll calculations:'],
          table: {
            caption: 'user_settings table schema',
            headers: ['Column', 'Type', 'Default', 'Purpose'],
            rows: [
              ['user_id', 'uuid', '-', 'Primary key, FK to auth.users'],
              ['payroll_day', 'integer', 'app fallback: 1', 'Day of month (1-31) when payroll is received'],
              ['half_tax_month', 'integer', '-', 'Month (11 or 12) for half-tax; NULL = disabled'],
              ['monthly_goal', 'integer', '20000', 'Monthly earnings goal in NOK'],
            ],
          },
          note: 'payroll_day is used to calculate payout dates for snapshot selection. half_tax_month applies to payout month, not worked month.',
        },
        {
          heading: 'SupplementRule structure',
          paragraphs: ['Used in wage_snapshots.supplements and user_shifts.custom_supplements:'],
          code: {
            language: 'typescript',
            content: `type SupplementRule = {
  days: number[];    // 1-7 (1=Monday, 7=Sunday)
  from: string;      // "HH:MM" (inclusive)
  to: string;        // "HH:MM" (inclusive)
  rate?: number;     // Fixed NOK per hour (mutually exclusive with percent)
  percent?: number;  // Percentage of base rate (mutually exclusive with rate)
};

// Example rules:
[
  { "days": [1,2,3,4,5], "from": "18:00", "to": "21:00", "rate": 22 },
  { "days": [6], "from": "13:00", "to": "24:00", "rate": 110 },
  { "days": [7], "from": "00:00", "to": "24:00", "rate": 115 }
]`,
          },
        },
        {
          heading: 'Preset supplement rules (tariff default)',
          paragraphs: ['The standard Norwegian tariff supplements:'],
          table: {
            caption: 'Preset supplement rates',
            headers: ['Period', 'Days', 'Time', 'Rate'],
            rows: [
              ['Weekday evening', 'Mon-Fri (1-5)', '18:00-21:00', '+22 NOK/h'],
              ['Weekday late night', 'Mon-Fri (1-5)', '21:00-24:00', '+45 NOK/h'],
              ['Saturday afternoon', 'Saturday (6)', '13:00-15:00', '+45 NOK/h'],
              ['Saturday late afternoon', 'Saturday (6)', '15:00-18:00', '+55 NOK/h'],
              ['Saturday evening', 'Saturday (6)', '18:00-24:00', '+110 NOK/h'],
              ['Sunday all day', 'Sunday (7)', '00:00-24:00', '+115 NOK/h'],
            ],
          },
        },
        {
          heading: 'Preset wage rates (tariff levels)',
          table: {
            caption: 'Preset wage levels',
            headers: ['Level', 'Rate (NOK/hour)'],
            rows: [
              ['-1', '129.91'],
              ['-2', '132.90'],
              ['1', '184.54'],
              ['2', '185.38'],
              ['3', '187.46'],
              ['4', '193.05'],
              ['5', '210.81'],
              ['6', '256.14'],
            ],
          },
        },
      ],
    },
    {
      id: 'pipeline',
      title: 'Shift Acquisition Pipeline',
      subsections: [
        {
          heading: 'ShiftWithComputations - The canonical shift object',
          paragraphs: ['Every shift flows through the pipeline and emerges with computed values:'],
          code: {
            language: 'typescript',
            content: `type ShiftWithComputations = ShiftRow & {
  computed: ShiftComputed;
  tax_enabled?: boolean;
  tax_percentage?: number;
};

type ShiftComputed = {
  id: string;
  durationHours: number;      // Raw duration before break
  paidHours: number;          // Duration after break deduction
  basePay: number;            // NOK from base rate
  supplementPay: number;      // NOK from supplements
  gross: number;              // basePay + supplementPay
  wagePeriods: WagePeriod[];  // After break deduction
  originalWagePeriods: WagePeriod[];  // Before break deduction
  breakAudit: BreakAudit;     // Deduction details
};

type WagePeriod = {
  fromMin: number;      // Minutes from midnight (shift-relative)
  toMin: number;        // Minutes from midnight (exclusive)
  baseRate: number;     // NOK per hour
  supplementRate: number;  // NOK per hour supplement
  totalRate: number;    // baseRate + supplementRate
};`,
          },
        },
        {
          heading: 'Pipeline steps',
          steps: [
            {
              title: 'Step 1: Fetch stored shifts',
              code: {
                language: 'typescript',
                content: `const { data } = await supabase
  .from("user_shifts")
  .select("*")
  .eq("user_id", userId)
  .is("deleted_at", null)
  .gte("shift_date", startDate)
  .lte("shift_date", endDate)
  .order("shift_date", { ascending: false })
  .limit(limit);`,
              },
            },
            {
              title: 'Step 2: Fetch recurring shift templates',
              code: {
                language: 'typescript',
                content: `const { data: recurringShifts } = await supabase
  .from("recurring_shifts")
  .select("*")
  .eq("user_id", userId)
  .is("deleted_at", null);`,
              },
            },
            {
              title: 'Step 3: Generate virtual shifts',
              paragraphs: ['For each recurring shift template and each month in range:'],
              code: {
                language: 'typescript',
                content: `function generateVirtualShiftsForMonth(
  yearMonth: { year: number; month: number },
  draft: RecurringDraft
): RecurringVirtualShift[]`,
              },
              list: [
                'For each selected weekday anchor in selected_days',
                'Find first occurrence of that weekday in target month',
                'Check if date is on/after anchor date',
                'Check if date is in phase with anchor (isInPhase)',
                'Check if within end window (if end condition exists)',
                'Check if not in exclusions list',
                'If all pass, add to virtual shifts',
              ],
            },
            {
              title: 'Step 4: Phase check formula',
              code: {
                language: 'typescript',
                content: `function isInPhase(dateISO, anchorISO, interval) {
  if (interval === 0) return true; // Every week

  const daysDiff = (date - anchor) / (24 * 60 * 60 * 1000);
  const weeksDiff = Math.floor(daysDiff / 7);

  // interval 1 = every 2 weeks, interval 2 = every 3 weeks
  return weeksDiff % (interval + 1) === 0;
}`,
              },
            },
            {
              title: 'Step 5: Batch snapshot lookup',
              code: {
                language: 'typescript',
                content: `// Fetch all user's wage snapshots once
const snapshots = await getUserWageSnapshots(userId);

// Wage/supplement/break snapshots (lookup by shift date)
for (const shiftDate of allDates) {
  const wageSnapshot = findSnapshotForDate(shiftDate, snapshots);
  wageSnapshotMap.set(shiftDate, wageSnapshot);
}

// Tax snapshots (lookup by payout date)
const payoutDates = new Set(allDates.map(d => getPayoutDateForShift(d)));
for (const shiftDate of allDates) {
  const payoutDate = getPayoutDateForShift(shiftDate);
  const taxSnapshot = findSnapshotForDate(payoutDate, snapshots);
  payoutSnapshotMap.set(payoutDate, taxSnapshot);
}`,
              },
            },
            {
              title: 'Step 6: Compute each shift',
              code: {
                language: 'typescript',
                content: `for (const shift of shifts) {
  const snapshot = snapshotMap.get(shift.shift_date);
  const computed = computeShift(shift, settings, PRESET_RULES, snapshot);
  result.push({ ...shift, computed, tax_enabled, tax_percentage });
}`,
              },
            },
          ],
        },
        {
          heading: 'Date-range inclusion rules',
          list: [
            'Boundaries are inclusive on both ends',
            'Query: shift_date >= startDate AND shift_date <= endDate',
            'For overnight shifts: The shift belongs to the start date',
          ],
          note: 'A shift from 22:00 to 06:00 on 2025-01-15 is queried by shift_date = 2025-01-15',
        },
        {
          heading: 'Cross-midnight handling',
          code: {
            language: 'typescript',
            content: `// Detection
const isCrossMidnight = endTime <= startTime;

// Treatment in calculation
let start = toMin(startHHMM); // e.g., 22:00 = 1320
let end = toMin(endHHMM);     // e.g., 06:00 = 360
if (end <= start) {
  end += 24 * 60;             // 360 + 1440 = 1800
}
// Duration: 1800 - 1320 = 480 minutes = 8 hours`,
          },
          note: 'Supplement rules are matched by the shift\'s weekday. For cross-midnight shifts, matching windows are projected into an extended timeline (0-2880 minutes), but rules from the next calendar day are not applied unless they are also configured for the shift weekday.',
        },
        {
          heading: 'Virtual shift identity',
          paragraphs: ['Virtual shifts have synthetic IDs for stable React keys and conflict detection:'],
          code: {
            language: 'typescript',
            content: `const id = \`virtual-\${recurringId}-\${shiftDate}\`;
// Example: "virtual-abc123-2025-01-15"`,
          },
        },
      ],
    },
    {
      id: 'snapshots',
      title: 'Wage Snapshot Selection & Payout Date Logic',
      subsections: [
        {
          heading: 'Important: Two different lookups per shift',
          paragraphs: [
            'Snapshot selection uses TWO different dates for each shift:',
          ],
          list: [
            'Wage, supplements, break settings: Selected based on shift date (the date the shift is worked)',
            'Tax settings only: Selected based on payout date (shift month + 1, on payroll day)',
          ],
          note: 'This is critical for accurate tax calculations when tax rates change between working and getting paid.',
        },
        {
          heading: 'Payout date calculation',
          code: {
            language: 'typescript',
            content: `function calculatePayoutDate(
  earningsYear: number,
  earningsMonth: number, // 1-12
  payrollDay: number
): string {
  // Payout month is earnings month + 1
  let payoutYear = earningsYear;
  let payoutMonth = earningsMonth + 1;

  if (payoutMonth > 12) {
    payoutMonth = 1;
    payoutYear += 1;
  }

  // Handle edge case: payroll_day exceeds days in payout month
  const daysInPayoutMonth = new Date(payoutYear, payoutMonth, 0).getDate();
  const effectivePayrollDay = Math.min(payrollDay, daysInPayoutMonth);

  return \`\${payoutYear}-\${padZero(payoutMonth)}-\${padZero(effectivePayrollDay)}\`;
}

// Example:
// Shift on 2025-01-15, payroll day = 20
// Earnings month = January (1)
// Payout month = February (2)
// Payout date = 2025-02-20`,
          },
        },
        {
          heading: 'Payout date adjustment for holidays',
          paragraphs: ['Valid payroll days are Tuesday through Friday, excluding public holidays:'],
          code: {
            language: 'typescript',
            content: `function adjustPayrollDate(
  payrollDay: number,
  month: number,      // 0-11 (JavaScript Date format)
  year: number,
  locale: Locale = 'no'
): Date {
  let date = new Date(year, month, payrollDay);

  // Move backward until valid payroll day found (max 10 iterations)
  while (isInvalidPayrollDay(date, locale)) {
    date.setDate(date.getDate() - 1);
  }

  return date;
}

function isInvalidPayrollDay(date: Date, locale: Locale): boolean {
  return isWeekend(date) || isMonday(date) || isPublicHoliday(date, locale);
}`,
          },
          note: 'This adjustment is used for payroll date display/countdown UX. Snapshot selection for tax uses calculatePayoutDate() (unadjusted). Holiday detection includes fixed and Easter-based Norwegian public holidays.',
        },
        {
          heading: 'Batch snapshot selection algorithm (binary search)',
          code: {
            language: 'typescript',
            content: `function findSnapshotForDate(
  targetDate: string,
  snapshots: WageSnapshot[]
): WageSnapshot | null {
  // snapshots sorted by from_date DESC (newest first)

  // Find baseline (from_date = NULL) for fallback
  const baseline = snapshots.find(s => s.from_date === null);

  // Filter to only dated snapshots and sort ascending for binary search
  const datedSnapshots = snapshots
    .filter(s => s.from_date !== null)
    .reverse(); // Now ascending

  // Binary search: find the latest snapshot where from_date <= targetDate
  let left = 0, right = datedSnapshots.length - 1;
  let result = null;

  while (left <= right) {
    const mid = Math.floor((left + right) / 2);
    if (datedSnapshots[mid].from_date <= targetDate) {
      result = datedSnapshots[mid];
      left = mid + 1; // Look for later valid snapshot
    } else {
      right = mid - 1;
    }
  }

  return result || baseline || null;
}`,
          },
        },
        {
          heading: 'Selection rules',
          list: [
            'Find latest dated snapshot where from_date <= targetDate',
            'If none found, use baseline snapshot (from_date = NULL)',
            'If no baseline, return null (calculation will use defaults)',
            'Inclusive from_date: A snapshot with from_date = 2025-02-01 applies to target dates >= 2025-02-01',
            'Batch lookups use binary search; single-date lookups may use first-match on DESC-sorted snapshots',
          ],
        },
        {
          heading: 'Example: Snapshot resolution',
          paragraphs: ['For a shift on 2025-01-15 with payroll day = 20:'],
          list: [
            'Wage snapshot lookup: targetDate = 2025-01-15 (shift date)',
            'Tax snapshot lookup: targetDate = 2025-02-20 (payout date)',
          ],
          code: {
            language: 'typescript',
            content: `// Snapshots:
const baseline = { from_date: null, hourly_wage: 180.00, tax_percentage: 25 };
const january = { from_date: "2025-01-01", hourly_wage: 185.00, tax_percentage: 30 };
const february = { from_date: "2025-02-01", hourly_wage: 190.00, tax_percentage: 35 };

// Resolution:
// Wage snapshot (by shift date 2025-01-15): january (from_date <= 2025-01-15)
// Tax snapshot (by payout date 2025-02-20): february (from_date <= 2025-02-20)
// Hourly wage used: 185.00 (from january snapshot)
// Tax percentage used: 35% (from february snapshot)`,
          },
        },
      ],
    },
    {
      id: 'calculation',
      title: 'Pay Calculation Engine (Math Spec)',
      subsections: [
        {
          heading: 'Precision constants',
          code: {
            language: 'typescript',
            content: `const HOUR_DECIMAL_PRECISION = 1000;  // 3 decimal places (0.001 hours)
const CURRENCY_PRECISION = 100;       // 2 decimal places (cents)`,
          },
        },
        {
          heading: 'Time conversion',
          code: {
            language: 'typescript',
            content: `function toMin(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}
// "09:00" -> 540
// "17:30" -> 1050
// "24:00" -> 1440`,
          },
        },
        {
          heading: 'Duration calculation',
          code: {
            language: 'typescript',
            content: `let start = toMin(startTime);  // e.g., 540
let end = toMin(endTime);      // e.g., 1050

// Handle cross-midnight
if (end <= start) {
  end += 24 * 60; // Add 1440 minutes (24 hours)
}

const totalMinutes = end - start;
const durationHours = +(totalMinutes / 60).toFixed(2);`,
          },
        },
        {
          heading: 'Weekday calculation',
          code: {
            language: 'typescript',
            content: `const WEEKDAYS = [7, 1, 2, 3, 4, 5, 6]; // JS getDay(): 0=Sun -> 7, then 1..6 Mon..Sat

const date = new Date(shiftDate + "T00:00:00Z");
const weekday = WEEKDAYS[date.getUTCDay()]; // 1-7 (Mon-Sun)`,
          },
          note: 'Supplement rules use 1-7 (Monday-Sunday), not JavaScript\'s 0-6.',
        },
        {
          heading: 'Base rate resolution',
          code: {
            language: 'typescript',
            content: `function resolveBaseRate(shift: ShiftRow, snapshot: WageSnapshot | null): number {
  // Priority 1: New snapshot system
  if (snapshot?.hourly_wage && snapshot.hourly_wage > 0) {
    return snapshot.hourly_wage;
  }

  // Priority 2: Legacy per-shift snapshot (backward compatibility)
  if (shift.hourly_wage_snapshot && shift.hourly_wage_snapshot > 0) {
    return shift.hourly_wage_snapshot;
  }

  // Priority 3: Fallback to tariff level 1
  return PRESET_WAGE_RATES["1"]; // 184.54
}`,
          },
        },
        {
          heading: 'Supplement rules resolution',
          code: {
            language: 'typescript',
            content: `function resolveSupplementRules(
  weekday: number,
  predefinedRules: SupplementRule[],
  customSupplements: CustomSupplementsData | null
): SupplementRule[] {
  // Custom supplements completely replace predefined rules
  if (customSupplements?.rules?.length > 0) {
    return customSupplements.rules.map(rule => ({
      ...rule,
      days: [weekday], // Apply to this shift's weekday only
    }));
  }

  return predefinedRules;
}`,
          },
        },
        {
          heading: 'Wage periods construction',
          paragraphs: ['The algorithm builds time periods with their applicable rates:'],
          code: {
            language: 'typescript',
            content: `function buildWagePeriods(
  startHHMM: string,
  endHHMM: string,
  weekday: number,
  baseRate: number,
  rules: SupplementRule[]
): WagePeriod[] {
  let start = toMin(startHHMM);
  let end = toMin(endHHMM);
  if (end <= start) end += 24 * 60;

  // Collect boundaries
  const points = new Set([start, end]);
  for (const rule of rules) {
    if (!rule.days.includes(weekday)) continue;
    // Add rule boundaries that fall within shift
    // ... (handles cross-midnight rules)
  }

  const sorted = Array.from(points).sort((a, b) => a - b);
  const periods: WagePeriod[] = [];

  for (let i = 0; i < sorted.length - 1; i++) {
    const a = sorted[i], b = sorted[i + 1];

    // Find highest supplement for this period
    let supplement = 0;
    for (const rule of rules) {
      // ... check if period falls within rule
      supplement = Math.max(supplement, resolveSupplementRate(rule, baseRate));
    }

    periods.push({
      fromMin: a,
      toMin: b,
      baseRate,
      supplementRate: supplement,
      totalRate: baseRate + supplement,
    });
  }

  return periods;
}`,
          },
        },
        {
          heading: 'Supplement rate resolution',
          code: {
            language: 'typescript',
            content: `function resolveSupplementRate(rule: SupplementRule, baseRate: number): number {
  // Fixed rate (NOK per hour)
  if (rule.rate != null && !isNaN(rule.rate)) {
    return rule.rate;
  }

  // Percentage of base rate
  if (rule.percent != null && !isNaN(rule.percent)) {
    return (baseRate * rule.percent) / 100;
  }

  return 0;
}`,
          },
          note: 'Stacking behavior: Highest-wins. Only the highest supplement rate applies to each time period.',
        },
        {
          heading: 'Pay calculation',
          code: {
            language: 'typescript',
            content: `let basePay = 0, supplementPay = 0;

for (const period of periods) {
  // Round hours to 3 decimals
  const hours = Math.round((period.toMin - period.fromMin) / 60 * 1000) / 1000;

  // Round each period's contribution to cents
  basePay += Math.round(hours * period.baseRate * 100) / 100;
  supplementPay += Math.round(hours * period.supplementRate * 100) / 100;
}

basePay = +basePay.toFixed(2);
supplementPay = +supplementPay.toFixed(2);
const gross = +(basePay + supplementPay).toFixed(2);`,
          },
        },
        {
          heading: 'Tax calculation',
          paragraphs: ['Tax is applied client-side or in aggregations, not in computeShift:'],
          code: {
            language: 'typescript',
            content: `const taxEnabled = snapshot.tax_enabled;
const taxPercentage = snapshot.tax_percentage;

// Half-tax adjustment (based on payout month)
const payoutMonth = shiftMonth === 12 ? 1 : shiftMonth + 1;
const effectiveTaxPct = (halfTaxMonth === payoutMonth)
  ? taxPercentage / 2
  : taxPercentage;

const taxAmount = taxEnabled ? gross * (effectiveTaxPct / 100) : 0;
const net = gross - taxAmount;`,
          },
        },
        {
          heading: 'Complete computation flow (pseudocode)',
          code: {
            language: 'text',
            content: `FUNCTION computeShift(shift, settings, presetRules, snapshot):
  // 1. Parse times
  start_minutes = toMinutes(shift.start_time)
  end_minutes = toMinutes(shift.end_time)
  IF end_minutes <= start_minutes THEN
    end_minutes += 1440  // Cross-midnight

  // 2. Get weekday (1-7)
  date = parseDate(shift.shift_date)
  weekday = WEEKDAYS[date.dayOfWeek]

  // 3. Resolve base rate
  baseRate = snapshot?.hourly_wage OR shift.hourly_wage_snapshot OR 184.54

  // 4. Resolve supplement rules
  rules = shift.custom_supplements OR snapshot.supplements OR presetRules

  // 5. Build wage periods
  periods = buildWagePeriods(start, end, weekday, baseRate, rules)

  // 6. Calculate raw duration
  totalMinutes = SUM(period.toMin - period.fromMin FOR period IN periods)
  durationHours = ROUND(totalMinutes / 60, 2)

  // 7. Apply break deduction
  breakEnabled = snapshot.break_enabled OR true
  breakMethod = snapshot.break_method OR "proportional"
  threshold = snapshot.break_threshold_hours OR 5.5
  breakMinutes = breakEnabled ? (snapshot.break_deduction_minutes OR 30) : 0

  IF durationHours > threshold AND breakEnabled THEN
    periods = applyBreakDeduction(periods, breakMethod, threshold, breakMinutes/60)

  // 8. Calculate paid hours
  paidMinutes = SUM(period.toMin - period.fromMin FOR period IN periods)
  paidHours = ROUND(paidMinutes / 60, 2)

  // 9. Calculate pay
  basePay = 0
  supplementPay = 0
  FOR period IN periods:
    hours = ROUND((period.toMin - period.fromMin) / 60, 3)
    basePay += ROUND(hours * period.baseRate, 2)
    supplementPay += ROUND(hours * period.supplementRate, 2)

  gross = ROUND(basePay + supplementPay, 2)

  RETURN {
    id: shift.id,
    durationHours,
    paidHours,
    basePay,
    supplementPay,
    gross,
    wagePeriods: periods,
    originalWagePeriods: originalPeriods,
    breakAudit: { method, threshold, deducted }
  }`,
          },
        },
      ],
    },
    {
      id: 'breaks',
      title: 'Break Deductions',
      subsections: [
        {
          heading: 'Automatic break deductions',
          paragraphs: [
            'Tidex deducts unpaid breaks automatically based on your configuration. Four deduction strategies are available.',
          ],
        },
        {
          heading: 'Default settings',
          list: [
            'Enabled: Yes (break_enabled = true)',
            'Method: Proportional',
            'Threshold: 5.5 hours (break_threshold_hours)',
            'Break duration: 30 minutes (break_deduction_minutes)',
          ],
        },
        {
          heading: 'Threshold behavior',
          paragraphs: ['Breaks are only deducted when the shift exceeds the configured threshold:'],
          code: {
            language: 'typescript',
            content: `// Threshold comparison: strict greater than (>)
let toDeduct = totalHours > thresholdHours ? deductionHours : 0;

// Edge case: Shift exactly at threshold (e.g., 5.5h with 5.5h threshold)
// NO break applied (uses >, not >=)`,
          },
          note: 'A 5.5-hour shift with a 5.5-hour threshold will NOT have a break deducted.',
        },
        {
          heading: 'Method 1: Proportional (default)',
          paragraphs: ['Distributes the deduction proportionally across all wage periods:'],
          code: {
            language: 'typescript',
            content: `if (method === "proportional") {
  // Deduct exact proportional fractions (not rounded to minutes)
  for (let i = 0; i < adjusted.length; i++) {
    const span = adjusted[i].toMin - adjusted[i].fromMin;
    const proportion = span / totalMinutes;
    const cutMinutes = proportion * toDeduct * 60;
    adjusted[i].toMin -= cutMinutes;
  }
}`,
          },
          note: 'Keeps ratios between base pay and supplements intact.',
        },
        {
          heading: 'Method 2: End of shift',
          paragraphs: ['Removes the break from the end of the shift:'],
          code: {
            language: 'typescript',
            content: `if (method === "end_of_shift") {
  // Subtract from the tail
  for (let i = adjusted.length - 1; i >= 0 && remaining > 0; i--) {
    const span = adjusted[i].toMin - adjusted[i].fromMin;
    const cut = Math.min(span, remaining);
    adjusted[i].toMin -= cut;
    remaining -= cut;
  }
}`,
          },
        },
        {
          heading: 'Method 3: Base only',
          paragraphs: ['Deducts from periods with the lowest supplement first:'],
          code: {
            language: 'typescript',
            content: `if (method === "base_only") {
  // Deduct from periods with lowest supplement first
  const order = adjusted
    .map((p, idx) => ({ idx, supplement: p.supplementRate }))
    .sort((a, b) => a.supplement - b.supplement)
    .map(o => o.idx);

  for (const i of order) {
    if (remaining <= 0) break;
    const span = adjusted[i].toMin - adjusted[i].fromMin;
    const cut = Math.min(span, remaining);
    adjusted[i].toMin -= cut;
    remaining -= cut;
  }
}`,
          },
          note: 'Useful for preserving premium hours (evening/weekend supplements).',
        },
        {
          heading: 'Method 4: None',
          paragraphs: ['No automatic break deduction is applied. All hours are paid.'],
        },
        {
          heading: 'Break method summary',
          table: {
            caption: 'Break deduction methods',
            headers: ['Method', 'Behavior'],
            rows: [
              ['proportional', 'Deducts break time proportionally across all periods based on their duration'],
              ['base_only', 'Deducts from periods with lowest supplement rate first'],
              ['end_of_shift', 'Deducts from the last period(s) of the shift'],
              ['none', 'No break deduction'],
            ],
          },
        },
        {
          heading: 'Break audit',
          paragraphs: ['Each computation includes a break audit for transparency:'],
          code: {
            language: 'typescript',
            content: `type BreakAudit = {
  method: BreakMethod;
  thresholdHours: number;
  deductedHours: number;
  notes?: string[];
};`,
          },
        },
      ],
    },
    {
      id: 'aggregations',
      title: 'Aggregations & Higher-Level Metrics',
      subsections: [
        {
          heading: 'Monthly totals (TotalCard)',
          code: {
            language: 'typescript',
            content: `// Exclude higher-earning overlapping shifts first
const excludedIds = buildExcludedShiftIds(shifts);
const included = shifts.filter(s => !excludedIds.has(s.id));

const aggregates = included.reduce((acc, shift) => ({
  totalHours: acc.totalHours + shift.computed.paidHours,
  totalEarnings: acc.totalEarnings + shift.computed.gross,
}), { totalHours: 0, totalEarnings: 0 });`,
          },
        },
        {
          heading: 'Next payroll (NextPayrollCard)',
          paragraphs: ['Which shifts are included: Earnings month is the month before the payroll month currently in view.'],
          code: {
            language: 'typescript',
            content: `const payoutDate = calculatePayoutDate(earningsYear, earningsMonth, payrollDay);
const payoutTax = getTaxSettingsForPayoutDate(wageSnapshots, payoutDate);

const grossAmount = summarizeShiftTotals({ shifts: earningsMonthShifts }).gross;
const taxAmount = payoutTax?.enabled
  ? grossAmount * (payoutTax.percentage / 100)
  : 0;
const netAmount = grossAmount - taxAmount;`,
          },
        },
        {
          heading: 'Projected total',
          paragraphs: ['Total earnings including future planned shifts:'],
          code: {
            language: 'typescript',
            content: `const totals = summarizeShiftTotals({
  shifts: monthShifts,
  now: new Date(),
  month: payoutMonth,
  halfTaxMonth,
  payoutTaxOverride,
});

const earnedToDate = taxEnabled ? totals.completedNet : totals.completedGross;
const projectedTotal = taxEnabled ? totals.net : totals.gross;
const hasFutureShifts = projectedTotal !== earnedToDate;`,
          },
        },
        {
          heading: 'Conflict exclusion (overlapping shifts)',
          paragraphs: [
            'When multiple shifts overlap on the same date, only one contributes to earnings totals. The shift with the lowest gross earnings is kept; all higher-earning overlapping shifts are excluded.',
          ],
          code: {
            language: 'typescript',
            content: `function buildExcludedShiftIds(shifts: ShiftWithComputations[]): Set<string> {
  const result = new Set<string>();
  const shiftsByDate = groupByDate(shifts);

  for (const [date, shiftsOnDate] of shiftsByDate) {
    if (shiftsOnDate.length < 2) continue;

    // Find overlapping clusters using union-find
    const clusters = findOverlappingClusters(shiftsOnDate);

    for (const cluster of clusters) {
      if (cluster.length < 2) continue;

      // Sort by gross ascending, keep only the lowest
      cluster.sort((a, b) => a.computed.gross - b.computed.gross);
      for (let i = 1; i < cluster.length; i++) {
        result.add(cluster[i].id);
      }
    }
  }

  return result;
}`,
          },
          note: 'Excluded shifts are displayed with strikethrough styling but remain visible.',
        },
        {
          heading: 'Overlap detection',
          code: {
            language: 'typescript',
            content: `function shiftsOverlap(a, b): boolean {
  let startA = toMinutes(a.start_time);
  let endA = toMinutes(a.end_time);
  let startB = toMinutes(b.start_time);
  let endB = toMinutes(b.end_time);

  // Handle cross-midnight
  if (endA <= startA) endA += 24 * 60;
  if (endB <= startB) endB += 24 * 60;

  return startA < endB && startB < endA;
}`,
          },
        },
        {
          heading: 'Stats aggregates',
          table: {
            caption: 'Stats calculations',
            headers: ['Aggregate', 'Formula', 'Period'],
            rows: [
              ['Total hours', 'SUM(paidHours)', 'Selected range'],
              ['Total earnings', 'SUM(gross)', 'Selected range'],
              ['Average per shift', 'totalEarnings / shiftCount', 'Selected range'],
              ['Average hourly', 'totalEarnings / totalHours', 'Selected range'],
              ['Month-over-month %', '(current - previous) / previous * 100', 'Comparison'],
            ],
          },
        },
      ],
    },
    {
      id: 'test-vectors',
      title: 'Test Vectors & Examples',
      subsections: [
        {
          heading: 'Test case 1: Basic weekday shift (no supplements)',
          paragraphs: ['A simple morning shift with no supplement windows:'],
          code: {
            language: 'typescript',
            content: `// Input
const shift = {
  shift_date: "2025-01-15", // Wednesday
  start_time: "09:00",
  end_time: "14:00",
};

const snapshot = {
  hourly_wage: 185.00,
  supplements: { rules: [] }, // No supplements
  break_enabled: false,
};

// Expected output
{
  durationHours: 5.00,
  paidHours: 5.00,
  basePay: 925.00,      // 5h x 185
  supplementPay: 0,
  gross: 925.00,
}`,
          },
        },
        {
          heading: 'Test case 2: Weekday evening shift (with supplement)',
          paragraphs: ['An evening shift that spans multiple supplement windows:'],
          code: {
            language: 'typescript',
            content: `// Input
const shift = {
  shift_date: "2025-01-15", // Wednesday
  start_time: "17:00",
  end_time: "22:00",
};

const snapshot = {
  hourly_wage: 185.00,
  supplements: { rules: [
    { days: [1,2,3,4,5], from: "18:00", to: "21:00", rate: 22 },
    { days: [1,2,3,4,5], from: "21:00", to: "24:00", rate: 45 },
  ]},
  break_enabled: false,
};

// Expected output
{
  durationHours: 5.00,
  paidHours: 5.00,
  basePay: 925.00,       // 5h x 185
  supplementPay: 111.00, // 1h x 0 + 3h x 22 + 1h x 45 = 0 + 66 + 45
  gross: 1036.00,
}`,
          },
        },
        {
          heading: 'Test case 3: Cross-midnight shift',
          paragraphs: ['A night shift that crosses midnight:'],
          code: {
            language: 'typescript',
            content: `// Input
const shift = {
  shift_date: "2025-01-15", // Wednesday
  start_time: "22:00",
  end_time: "06:00",
};

const snapshot = {
  hourly_wage: 185.00,
  supplements: { rules: [
    { days: [1,2,3,4,5], from: "21:00", to: "24:00", rate: 45 },
  ]},
  break_enabled: true,
  break_threshold_hours: 5.5,
  break_deduction_minutes: 30,
};

// Expected output
{
  durationHours: 8.00,        // 22:00 to 06:00 = 8 hours
  paidHours: 7.50,            // 8h - 0.5h break
  basePay: 1387.51,           // 346.88 (1.875h x 185) + 1040.63 (5.625h x 185)
  supplementPay: 84.38,       // 1.875h x 45 (proportional: 2h loses 2/8 x 0.5h)
  gross: 1471.89,
}`,
          },
        },
        {
          heading: 'Test case 4: Sunday full day (high supplement)',
          code: {
            language: 'typescript',
            content: `// Input
const shift = {
  shift_date: "2025-01-19", // Sunday
  start_time: "08:00",
  end_time: "16:00",
};

const snapshot = {
  hourly_wage: 185.00,
  supplements: { rules: [
    { days: [7], from: "00:00", to: "24:00", rate: 115 },
  ]},
  break_enabled: true,
  break_threshold_hours: 5.5,
  break_deduction_minutes: 30,
};

// Expected output
{
  durationHours: 8.00,
  paidHours: 7.50,
  basePay: 1387.50,      // 7.5h x 185
  supplementPay: 862.50, // 7.5h x 115
  gross: 2250.00,
}`,
          },
        },
        {
          heading: 'Test case 5: Break threshold edge case',
          paragraphs: ['A shift exactly at the threshold - NO break applied:'],
          code: {
            language: 'typescript',
            content: `// Input
const shift = {
  shift_date: "2025-01-15",
  start_time: "09:00",
  end_time: "14:30", // Exactly 5.5 hours
};

const snapshot = {
  hourly_wage: 185.00,
  break_enabled: true,
  break_threshold_hours: 5.5,
  break_deduction_minutes: 30,
};

// Expected output
{
  durationHours: 5.50,
  paidHours: 5.50,       // NO break (threshold uses >)
  basePay: 1017.50,
  supplementPay: 0,
  gross: 1017.50,
}`,
          },
          note: 'The threshold comparison uses strict greater than (>), not >=.',
        },
        {
          heading: 'Test case 6: Percentage-based supplement',
          code: {
            language: 'typescript',
            content: `// Input
const shift = {
  shift_date: "2025-01-15",
  start_time: "18:00",
  end_time: "22:00",
};

const snapshot = {
  hourly_wage: 200.00,
  supplements: { rules: [
    { days: [3], from: "18:00", to: "24:00", percent: 50 }, // 50% of base
  ]},
  break_enabled: false,
};

// Expected output
{
  durationHours: 4.00,
  paidHours: 4.00,
  basePay: 800.00,       // 4h x 200
  supplementPay: 400.00, // 4h x (200 x 0.50)
  gross: 1200.00,
}`,
          },
        },
        {
          heading: 'Test case 7: Saturday to Sunday cross-midnight',
          paragraphs: ['A shift that spans from Saturday evening to Sunday morning:'],
          code: {
            language: 'typescript',
            content: `// Input
const shift = {
  shift_date: "2025-01-18", // Saturday
  start_time: "20:00",
  end_time: "02:00",
};

const snapshot = {
  hourly_wage: 185.00,
  supplements: { rules: [
    { days: [6], from: "18:00", to: "24:00", rate: 110 }, // Saturday evening
    { days: [7], from: "00:00", to: "24:00", rate: 115 }, // Sunday all day
  ]},
  break_enabled: false,
};

// Expected output
{
  durationHours: 6.00,
  paidHours: 6.00,
  // Current engine matches supplements by shift weekday only (Saturday = day 6)
  // 20:00-00:00 (4h) at Saturday rate 110
  // 00:00-02:00 (2h) has no Sunday supplement in this model
  basePay: 1110.00,       // 6h x 185
  supplementPay: 440.00,  // 4h x 110
  gross: 1550.00,
}`,
          },
        },
        {
          heading: 'Test case 8: Tax with half-tax month',
          code: {
            language: 'typescript',
            content: `// Input
const shift = {
  shift_date: "2025-11-15", // November
};

const snapshot = {
  tax_enabled: true,
  tax_percentage: 30,
};

const settings = {
  half_tax_month: 12, // December (payout month for November shifts)
};

// Tax calculation
// Payout month = December
// Half-tax applies because halfTaxMonth === payoutMonth
const effectiveTaxPct = 30 / 2; // = 15%
const taxAmount = gross * 0.15;`,
          },
        },
        {
          heading: 'Test case 9: Overlapping shifts (conflict exclusion)',
          code: {
            language: 'typescript',
            content: `// Input
const shifts = [
  {
    id: "shift-a",
    shift_date: "2025-01-15",
    start_time: "09:00",
    end_time: "17:00", // Gross: 1480 NOK
  },
  {
    id: "shift-b",
    shift_date: "2025-01-15",
    start_time: "14:00",
    end_time: "22:00", // Gross: 1850 NOK (higher due to evening supplement)
  },
];

// Expected behavior
// shift-a and shift-b overlap (14:00-17:00)
// shift-a has lower gross (1480) -> included in totals
// shift-b has higher gross (1850) -> excluded from totals, shown with strikethrough

const excludedIds = buildExcludedShiftIds(shifts);
// excludedIds.has("shift-b") === true
// excludedIds.has("shift-a") === false

// Monthly total = 1480 (only shift-a counted)`,
          },
        },
      ],
    },
  ],
} as const;

export default function PayrollDocsPageRoute() {
  return <PayrollDocsPage docs={payrollDocs} />;
}
