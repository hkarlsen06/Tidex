import { Metadata } from 'next';
import { PayrollDocsPage } from './PayrollDocsPage';

export const metadata: Metadata = {
  title: 'Payroll Documentation - How Tidex calculates your pay',
  description:
    'A transparent, auditable reference for every payroll rule we apply—from the shift you log to the amount you see on screen.',
  openGraph: {
    title: 'Payroll Documentation - How Tidex calculates your pay',
    description:
      'A transparent, auditable reference for every payroll rule we apply—from the shift you log to the amount you see on screen.',
  },
  twitter: {
    title: 'Payroll Documentation - How Tidex calculates your pay',
    description:
      'A transparent, auditable reference for every payroll rule we apply—from the shift you log to the amount you see on screen.',
  },
};

// English-only payroll documentation content
const payrollDocs = {
  badge: 'Payroll Documentation',
  title: 'How Tidex calculates your pay',
  subtitle:
    'A transparent, auditable reference for every payroll rule we apply—from the shift you log to the amount you see on screen.',

  navigation: [
    { id: 'overview', label: 'Overview' },
    { id: 'base-wage', label: 'Base Wage' },
    { id: 'time-periods', label: 'Time Periods' },
    { id: 'supplements', label: 'Supplements' },
    { id: 'breaks', label: 'Break Deductions' },
    { id: 'examples', label: 'Complete Flow' },
  ],

  bugReportCta: {
    heading: 'Notice an inconsistency?',
    description: 'Flag potential discrepancies directly to the payroll engineering team.',
    buttonText: 'Email the payroll team',
    emailSubject: 'Payroll calculation discrepancy',
    emailBody:
      'Hello Tidex payroll team,\\n\\nI believe there may be an issue with the payroll calculation engine:\\n\\n',
  },

  sections: [
    {
      id: 'overview',
      title: 'Overview',
      subsections: [
        {
          heading: 'Transparency by design',
          paragraphs: [
            'Pay accuracy is non-negotiable. Tidex documents every payroll rule so employees, customers, and auditors can review the exact calculations behind each payout.',
            'Use this guide as the canonical explanation of our payroll engine, from data capture to computed totals.',
          ],
        },
        {
          heading: 'What this guide covers',
          list: [
            'Base wage: Snapshot preservation for both hourly rates and supplement rules, with fallback to current settings',
            'Time periods: How a shift is segmented to honour supplement rules',
            'Supplements: Fixed NOK/hour and percentage-based adjustments for specific days or hours',
            'Break deductions: Three deduction strategies with audit trails',
            'Examples: End-to-end code flow from Supabase to the UI render',
          ],
        },
        {
          heading: 'Architecture highlights',
          paragraphs: [
            'All payroll calculations run in deterministic, side-effect free functions. Identical inputs always yield identical results.',
            'Computation happens server-side in the Data Access Layer to ensure:',
          ],
          list: [
            'Consistent outputs across devices and clients',
            'No client-side JavaScript required to validate pay',
            'A single source of truth for every payroll rule',
          ],
        },
      ],
    },
    {
      id: 'base-wage',
      title: 'Base Wage',
      subsections: [
        {
          heading: 'How we resolve the hourly rate',
          paragraphs: [
            'Each shift requires an explicit base rate. Tidex resolves the hourly rate using a priority system designed to preserve historical accuracy while respecting your current settings:',
          ],
        },
        {
          heading: '1. Snapshot rate (highest priority)',
          paragraphs: [
            'When a shift is created, Tidex snapshots both the hourly rate and supplement rules at that moment and stores them with the shift. This ensures historical shifts remain accurate even after you adjust your wage settings or when tariff rates change year-to-year.',
          ],
          code: {
            language: 'typescript',
            content: `// Hourly wage snapshot
if (shift.hourly_wage_snapshot && shift.hourly_wage_snapshot > 0) {
  return shift.hourly_wage_snapshot;
}

// Supplement rules snapshot
const rules = shift.supplement_rules_snapshot?.rules?.length
  ? shift.supplement_rules_snapshot.rules  // Use snapshot
  : settings.use_preset
    ? presetRules                          // Fall back to current preset
    : settings.custom_supplements.rules;   // Or current custom`,
          },
        },
        {
          heading: '2. Current wage settings',
          paragraphs: [
            'If no snapshot exists (e.g., for older shifts or when the feature is disabled), Tidex uses your current wage settings. You can choose between two wage models:',
          ],
          list: [
            'Preset tariff levels: Standard Norwegian tariff rates updated annually',
            'Custom hourly wage: Your own rate that you configure manually',
          ],
        },
        {
          heading: 'Preset tariff levels',
          paragraphs: [
            'When using preset mode, Tidex looks up your configured level from the tariff table:',
          ],
          code: {
            language: 'typescript',
            content: `if (settings.use_preset && settings.current_wage_level != null) {
  const key = String(settings.current_wage_level);
  if (PRESET_WAGE_RATES[key] != null) {
    return PRESET_WAGE_RATES[key];
  }
}`,
          },
          table: {
            caption: 'Preset wage levels (2024/2025 rates)',
            headers: ['Level', 'Hourly Rate (NOK)'],
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
        {
          heading: 'Custom hourly wage',
          paragraphs: [
            'When using custom mode, Tidex applies your manually configured rate:',
          ],
          code: {
            language: 'typescript',
            content: `if (settings.custom_wage && settings.custom_wage > 0) {
  return settings.custom_wage;
}`,
          },
        },
        {
          heading: '3. Safe default',
          paragraphs: [
            'As a last resort, Tidex defaults to wage level 1 (184.54 NOK) to prevent calculation errors:',
          ],
          code: {
            language: 'typescript',
            content: `return PRESET_WAGE_RATES["1"]; // Safe fallback`,
          },
        },
        {
          heading: 'Source code',
          paragraphs: [
            'The base wage resolution logic is implemented in lib/payroll/calc.ts (resolveBaseRate function).',
          ],
        },
      ],
    },
    {
      id: 'time-periods',
      title: 'Time Periods',
      subsections: [
        {
          heading: 'How shifts become wage periods',
          paragraphs: [
            'Single shifts (for example 15:00–23:00) are segmented into wage periods. Each period carries its own base rate and supplement rate so supplements can be applied with minute-level precision.',
          ],
        },
        {
          heading: 'The algorithm',
          steps: [
            {
              title: 'Step 1: Convert to minutes',
              paragraphs: ['Time strings are converted to minutes since midnight:'],
              code: {
                language: 'typescript',
                content: `"15:00" → 900 minutes (15 * 60)
"23:00" → 1380 minutes (23 * 60)`,
              },
            },
            {
              title: 'Step 2: Handle cross-midnight shifts',
              paragraphs: [
                'If the end time is earlier than or equal to the start time, we assume the shift crosses midnight.',
                'Example: 22:00 to 06:00 becomes 22:00 (1320 min) to 30:00 (1800 min)',
              ],
              code: {
                language: 'typescript',
                content: `if (endMin <= startMin) {
  endMin += 1440; // Add 24 hours
}`,
              },
            },
            {
              title: 'Step 3: Apply supplement rules',
              paragraphs: ['Each supplement rule (evening, night, weekend, etc.) defines:'],
              list: [
                'Days: Which days it applies (1-7 for Mon-Sun)',
                'Time range: From/to hours',
                'Rate: Either fixed NOK/hour or percentage',
              ],
              note: 'The algorithm overlays these rules onto the shift timeline, splitting it wherever a supplement starts or stops.',
            },
            {
              title: 'Important: Overlapping supplements',
              paragraphs: [
                'If several supplements overlap (for example night and weekend), Tidex applies the highest single supplement rather than stacking the amounts:',
              ],
              code: {
                language: 'typescript',
                content: `supplement = Math.max(supplement, supplementValue);`,
              },
            },
          ],
        },
        {
          heading: 'Example: Evening shift with night supplement',
          paragraphs: [
            'Shift: Monday 20:00-02:00 (6 hours)',
            'Base rate: 185 NOK/hour',
            'Rules:',
          ],
          list: ['Evening (18:00-21:00): +22 NOK/hour', 'Evening (21:00-23:59): +45 NOK/hour'],
          table: {
            caption: 'Result periods',
            headers: ['Period', 'Hours', 'Base Rate', 'Supplement', 'Total Rate'],
            rows: [
              ['20:00-21:00', '1h', '185 NOK', '+22 (evening)', '207 NOK/h'],
              ['21:00-02:00', '5h', '185 NOK', '+45 (evening)', '230 NOK/h'],
            ],
          },
        },
        {
          heading: 'Precision',
          paragraphs: [
            'All time calculations maintain 3 decimal place precision for hours to ensure accurate wage computation:',
          ],
          code: {
            language: 'typescript',
            content: `const HOUR_DECIMAL_PRECISION = 1000; // 0.001 hours ≈ 3.6 seconds
const hours = Math.round((toMin - fromMin) / 60 * 1000) / 1000;`,
          },
        },
        {
          heading: 'Source code',
          paragraphs: [
            'Period splitting logic lives in lib/payroll/periods.ts (buildWagePeriods function).',
          ],
        },
      ],
    },
    {
      id: 'supplements',
      title: 'Supplements',
      subsections: [
        {
          heading: 'How evening, night, and weekend pay is applied',
          paragraphs: [
            'Supplements are additional pay applied for specific days or hours. Tidex supports two models:',
          ],
        },
        {
          heading: '1. Percentage-based supplements',
          paragraphs: [
            'Applies a percentage on top of the base rate.',
            'Example: A 50% evening supplement on a 185 NOK base rate results in a 92.50 NOK/hour supplement.',
          ],
          code: {
            language: 'typescript',
            content: `if (rule.percent) {
  supplementRate = baseRate * (rule.percent / 100);
}`,
          },
        },
        {
          heading: '2. Fixed-rate supplements',
          paragraphs: [
            'Adds a fixed NOK/hour amount.',
            'Example: Night supplement of 110 NOK/hour.',
          ],
          code: {
            language: 'typescript',
            content: `if (rule.rate) {
  supplementRate = rule.rate;
}`,
          },
        },
        {
          heading: 'Supplement rules',
          paragraphs: ['Each rule defines:'],
          code: {
            language: 'typescript',
            content: `{
  days: number[];    // 1-7 for Mon-Sun
  from: "HH:mm";     // Start time (inclusive)
  to: "HH:mm";       // End time (inclusive)
  rate?: number;     // Fixed NOK/hour supplement
  percent?: number;  // Percentage supplement
}`,
          },
        },
        {
          heading: 'Preset supplement rules',
          paragraphs: [
            'Tidex ships with presets aligned with common Norwegian tariffs.',
            'All preset supplements use fixed NOK/hour rates.',
          ],
          table: {
            caption: 'Preset rates',
            headers: ['Supplement', 'Days', 'Time', 'Rate'],
            rows: [
              ['Evening 1', 'Mon-Fri (1-5)', '18:00-21:00', '+22 NOK/h'],
              ['Evening 2', 'Mon-Fri (1-5)', '21:00-23:59', '+45 NOK/h'],
              ['Saturday 1', 'Saturday (6)', '13:00-15:00', '+45 NOK/h'],
              ['Saturday 2', 'Saturday (6)', '15:00-18:00', '+55 NOK/h'],
              ['Saturday 3', 'Saturday (6)', '18:00-23:59', '+110 NOK/h'],
              ['Sunday', 'Sunday (7)', '00:00-23:59', '+115 NOK/h'],
            ],
          },
        },
        {
          heading: 'Custom supplements',
          paragraphs: ['Custom supplement rules can be defined in settings:'],
          code: {
            language: 'typescript',
            content: `settings.custom_supplements = {
  rules: [
    {
      days: [1, 2, 3, 4, 5],  // Weekdays
      from: "17:00",
      to: "22:00",
      percent: 40  // Custom 40% supplement
    }
  ]
}`,
          },
        },
        {
          heading: 'Overlapping supplements',
          paragraphs: [
            'If multiple supplements overlap (for example Saturday and evening) Tidex applies the highest single supplement, never the combined total.',
            'Example: Saturday evening 20:00',
          ],
          code: {
            language: 'typescript',
            content: `// From lib/payroll/periods.ts
supplement = Math.max(supplement, supplementValue);`,
          },
          list: [
            'Saturday 18:00-23:59: +110 NOK',
            'Evening 18:00-21:00: +22 NOK',
            'Result: +110 NOK (highest)',
          ],
        },
        {
          heading: 'Source code',
          paragraphs: ['Supplement logic lives in:'],
          list: [
            'lib/payroll/periods.ts (supplement application)',
            'lib/payroll/presets.ts (preset rules)',
            'lib/payroll/types.ts (type: SupplementRule)',
          ],
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
            'Tidex can deduct unpaid breaks automatically based on your configuration. Three deduction strategies are available:',
          ],
        },
        {
          heading: 'Default settings',
          paragraphs: ['Default break policy:'],
          list: [
            'Enabled: Yes',
            'Method: Proportional',
            'Threshold: 5.5 hours',
            'Break duration: 30 minutes',
          ],
          code: {
            language: 'typescript',
            content: `const defaultSettings = {
  pause_deduction_enabled: true,
  pause_deduction_method: "proportional",
  pause_threshold_hours: 5.5,
  pause_deduction_minutes: 30,
};`,
          },
        },
        {
          heading: 'Method 1: Proportional',
          paragraphs: [
            'Distributes the deduction proportionally across all wage periods, keeping ratios between base pay and supplements intact.',
            'Example: 6-hour shift with a 30-minute break.',
          ],
          code: {
            language: 'typescript',
            content: `for (let i = 0; i < periods.length; i++) {
  const span = periods[i].toMin - periods[i].fromMin;
  const proportion = span / totalMinutes;
  const cutMinutes = proportion * pauseHours * 60;
  periods[i].toMin -= cutMinutes;
}`,
          },
          list: [
            'Period 1: 2 hours → deduct 10 min (2/6 * 30)',
            'Period 2: 4 hours → deduct 20 min (4/6 * 30)',
          ],
        },
        {
          heading: 'Method 2: End of shift',
          paragraphs: [
            'Removes the break from the end of the shift by trimming the latest wage periods.',
            'Useful when breaks are always taken at the end.',
          ],
          code: {
            language: 'typescript',
            content: `for (let i = periods.length - 1; i >= 0 && remaining > 0; i--) {
  const span = periods[i].toMin - periods[i].fromMin;
  const cut = Math.min(span, remaining);
  periods[i].toMin -= cut;
  remaining -= cut;
}`,
          },
        },
        {
          heading: 'Method 3: Base first',
          paragraphs: [
            'Deducts from periods with the lowest supplement first (typically the base rate) to preserve premium hours.',
            'Example: A shift with base pay (185 NOK/h) and evening supplement (230 NOK/h).',
          ],
          code: {
            language: 'typescript',
            content: `// Sort periods by supplement (lowest first)
const order = periods
  .map((p, idx) => ({ idx, supplement: p.supplementRate }))
  .sort((a, b) => a.supplement - b.supplement)
  .map(o => o.idx);

// Deduct from lowest supplement periods
for (const i of order) {
  if (remaining <= 0) break;
  const span = periods[i].toMin - periods[i].fromMin;
  const cut = Math.min(span, remaining);
  periods[i].toMin -= cut;
  remaining -= cut;
}`,
          },
          list: [
            '30 min break deducted first from base pay period',
            'Evening supplement period preserved entirely',
          ],
        },
        {
          heading: 'Threshold',
          paragraphs: [
            'Breaks are only deducted when the shift exceeds the configured threshold.',
            'Default threshold: 5.5 hours (shifts under 5.5 hours incur no deduction).',
          ],
          code: {
            language: 'typescript',
            content: `const totalHours = totalMinutes / 60;
let toDeduct = totalHours > thresholdHours ? pauseHours : 0;`,
          },
        },
        {
          heading: 'Break audit',
          paragraphs: ['Each computation includes a break audit to show exactly what was deducted:'],
          code: {
            language: 'typescript',
            content: `{
  method: "proportional",
  thresholdHours: 5.5,
  deductedHours: 0.5,
  notes: ["Deducted proportionally across periods"]
}`,
          },
        },
        {
          heading: 'Source code',
          paragraphs: [
            'Break deduction logic is in lib/payroll/breaks.ts (applyBreakDeduction function).',
          ],
        },
      ],
    },
    {
      id: 'examples',
      title: 'Complete Flow',
      subsections: [
        {
          heading: 'From database to UI',
          paragraphs: [
            "Here's the complete flow of how a shift goes from raw data in Supabase to the final number you see on screen:",
          ],
        },
        {
          heading: 'Step 1: Database query',
          paragraphs: ['Data Access Layer (DAL) fetches shifts and user settings from Supabase:'],
          code: {
            language: 'typescript',
            content: `// data-access/shifts.ts
const supabase = await createSupabaseServerClient();

const { data: settingsRow } = await supabase
  .from("user_settings")
  .select("*")
  .eq("user_id", userId)
  .single();

const { data: shifts } = await supabase
  .from("user_shifts")
  .select("*")
  .eq("user_id", userId)
  .gte("shift_date", startDate)
  .lte("shift_date", endDate)
  .order("shift_date", { ascending: false });`,
          },
        },
        {
          heading: 'Step 2: Payroll computation',
          paragraphs: ['For each shift, call computeShift() to calculate wages:'],
          code: {
            language: 'typescript',
            content: `// data-access/shifts.ts
const computedShifts = shifts.map((shift) => ({
  ...shift,
  computed: computeShift(shift, settings, PRESET_RULES),
}));`,
          },
          note: 'Inside computeShift() (from lib/payroll/calc.ts):',
          additionalCode: {
            language: 'typescript',
            content: `export function computeShift(
  shift: ShiftRow,
  settings: UserSettings,
  presetRules: SupplementRule[]
): ShiftComputed {
  // 1. Determine base wage
  const baseRate = resolveBaseRate(shift, settings);

  // 2. Build wage periods with supplements
  let periods = buildWagePeriods(
    shift.start_time,
    shift.end_time,
    weekday,
    baseRate,
    rules
  );

  // 3. Calculate total duration
  const totalMinutes = periods.reduce((sum, p) =>
    sum + (p.toMin - p.fromMin), 0
  );
  const durationHours = totalMinutes / 60;

  // 4. Deduct break
  const afterBreak = applyBreakDeduction(
    periods,
    settings.pause_deduction_method,
    settings.pause_threshold_hours,
    pauseHours
  );
  periods = afterBreak.periods;

  // 5. Calculate pay
  let basePay = 0, supplementPay = 0;
  for (const p of periods) {
    const h = (p.toMin - p.fromMin) / 60;
    basePay += h * p.baseRate;
    supplementPay += h * p.supplementRate;
  }

  const gross = basePay + supplementPay;

  return {
    id: shift.id,
    durationHours,
    paidHours: periods.reduce(...) / 60,
    basePay,
    supplementPay,
    gross,
    wagePeriods: periods,
    breakAudit: afterBreak.audit
  };
}`,
          },
        },
        {
          heading: 'Step 3: Return to page',
          paragraphs: ['DAL returns shifts with pre-computed values:'],
          code: {
            language: 'typescript',
            content: `// data-access/shifts.ts
return {
  shifts: computedShifts,
  settings,
  aggregates: {
    totalHours: sum(shifts.map(s => s.computed.paidHours)),
    totalEarnings: sum(shifts.map(s => s.computed.gross))
  }
};`,
          },
        },
        {
          heading: 'Step 4: UI rendering',
          paragraphs: ['Page receives pre-computed data and displays it:'],
          code: {
            language: 'typescript',
            content: `// app/[locale]/(app)/page.tsx
import { verifySession } from "@/data-access/auth";
import { getComputedShifts } from "@/data-access/shifts";

export default async function Page() {
  const { user } = await verifySession();
  const { shifts, aggregates } = await getComputedShifts(user.id);

  return <ShiftsList shifts={shifts} totals={aggregates} />;
}`,
          },
          note: 'ShiftCard component displays the computed values:',
          additionalCode: {
            language: 'typescript',
            content: `// components/app/ShiftCard.tsx
export function ShiftCard({ shift }: { shift: ShiftWithComputations }) {
  const { basePay, supplementPay, gross, paidHours } = shift.computed;

  return (
    <Card>
      <p>{formatCurrency(gross)}</p>
      <p>{formatHours(paidHours)}</p>
      <p>Base pay: {formatCurrency(basePay)}</p>
      <p>Supplements: {formatCurrency(supplementPay)}</p>
    </Card>
  );
}`,
          },
        },
        {
          heading: 'Complete example: Saturday evening',
          paragraphs: ['The following example walks through a shift end to end:'],
          list: [
            'Shift: Saturday 15:00-23:00',
            'User settings: Preset wage level 3 (187.46 NOK/h), proportional break',
          ],
          code: {
            language: 'typescript',
            content: `// 1. Base wage
baseRate = 187.46 // From PRESET_WAGE_RATES["3"]

// 2. Time periods with supplements
// Saturday 15:00-18:00: +55 NOK
// Saturday 18:00-23:00: +110 NOK
periods = [
  { fromMin: 900, toMin: 1080, baseRate: 187.46, supplementRate: 55 },  // 15:00-18:00 (3h)
  { fromMin: 1080, toMin: 1380, baseRate: 187.46, supplementRate: 110 } // 18:00-23:00 (5h)
]

// 3. Duration
durationHours = 8.00 hours

// 4. Break deduction (8h > 5.5h, deduct 0.5h proportionally)
// Period 1: 180min → deduct 11.25min (180/480 * 30)
// Period 2: 300min → deduct 18.75min (300/480 * 30)
// After deduction:
periods = [
  { fromMin: 900, toMin: 1068.75, baseRate: 187.46, supplementRate: 55 },  // 2.813h
  { fromMin: 1080, toMin: 1361.25, baseRate: 187.46, supplementRate: 110 } // 4.688h
]
paidHours = 7.50 hours

// 5. Pay calculation (with per-period rounding to 2 decimals)
// Period 1: 2.813h * 187.46 = 527.32 kr (base), 2.813h * 55 = 154.72 kr (supp)
// Period 2: 4.688h * 187.46 = 878.81 kr (base), 4.688h * 110 = 515.68 kr (supp)
basePay = 527.32 + 878.81 = 1406.13 kr
supplementPay = 154.72 + 515.68 = 670.40 kr
gross = 2076.53 kr`,
          },
        },
      ],
    },
  ],
} as const;

export default function PayrollDocsPageRoute() {
  return <PayrollDocsPage docs={payrollDocs} />;
}
