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
  badge: 'PAYROLL ENGINE SPECIFICATION V3.2',
  title: 'How Tidex calculates your pay',
  subtitle:
    'A transparent, auditable reference for every payroll rule we apply. This specification enables re-implementation in any language (Swift, Kotlin, Go, etc.) with identical results.',

  navigation: [
    { id: 'overview', label: 'Overview' },
    { id: 'data-model', label: 'Data Model' },
    { id: 'jobs', label: 'Jobs & Multi-employer' },
    { id: 'pipeline', label: 'Shift Pipeline' },
    { id: 'snapshots', label: 'Snapshots & Payout' },
    { id: 'calculation', label: 'Calculation Engine' },
    { id: 'breaks', label: 'Pauses & Breaks' },
    { id: 'adjustments', label: 'Adjustments' },
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
            'Shift data: shift_date (ISO), start_time (HH:MM), end_time (HH:MM), optional custom pause windows, optional custom supplements, job_id',
            'Wage snapshot: Hourly wage, supplement rules, tax settings, break deduction settings — scoped to a job',
            'Job: Name, color, payroll_day, half_tax_month, monthly_goal — primary source for payroll configuration',
            'Payroll adjustments: Manual payout-level additions or corrections with amount, payout date, job scope, and tax treatment',
            'User settings: Global preferences; payroll_day/half_tax_month/monthly_goal kept as legacy fallback during compatibility window',
          ],
        },
        {
          heading: 'Outputs',
          list: [
            'computeShift output: durationHours, paidHours, basePay, supplementPay, gross, wagePeriods, originalWagePeriods, breakAudit',
            'breakAudit output: method, thresholdHours, deductedHours, source, appliedPauseWindows, notes',
            'Downstream totals output: taxAmount and net (calculated outside computeShift), plus payroll adjustment gross/net totals for payout cards',
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
            'Job-scoped snapshots: Each shift uses wage snapshots belonging to the same job; legacy (job-less) snapshots serve as fallback',
            'Job-scoped payroll day: payroll_day is resolved from the shift\'s job first, then falls back to user settings',
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
              ['Wage snapshot', 'Point-in-time capture of wage, supplement, tax, and break settings — scoped to a job'],
              ['Baseline snapshot', 'Snapshot with from_date = NULL, serves as fallback within its job bucket'],
              ['Supplement window', 'Time-of-day range when a supplement rate applies'],
              ['Pause window', 'An exact unpaid interval clipped out of a shift before automatic break rules are considered'],
              ['Payout date', 'Date when wages are paid (typically month after work + payroll day)'],
              ['Payroll period', 'The calendar month whose earnings are grouped for a payout'],
              ['Month grouping', 'Shifts worked in month M are paid in month M+1'],
              ['Payroll adjustment', 'A manual payout-level bonus, retro pay, correction, or other adjustment included in payroll totals'],
              ['Job', 'An employer/workplace entity that groups shifts and wage snapshots; owns payroll_day, half_tax_month, monthly_goal'],
              ['Default job', 'Each user has exactly one active default job; shifts without an explicit job_id are assigned here'],
              ['Legacy snapshot', 'A wage_snapshot with job_id = NULL; used as fallback when no job-specific snapshot exists'],
            ],
          },
        },
        {
          heading: 'Entry points',
          paragraphs: [
            'The active payroll stack is split between the iOS app and the shared Supabase TypeScript module. The legacy Effect wrapper and ShiftsService wording no longer describe the live product.',
            'The Swift iOS layer orchestrates month-level loading and tax/snapshot selection, while the shared TypeScript calculator is still used by Wagey and server-side tooling. In the TypeScript compatibility signature, settings and job are retained for compatibility but are not required for the current core calculation path.',
          ],
          code: {
            language: 'text',
            content: `// iOS month orchestration (active app)
PayrollEngine.computeShiftsForMonth(request)
// ios/TidexApp/Services/Payroll/PayrollEngine.swift

// iOS per-shift calculator (active app)
PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
// ios/TidexApp/Services/Payroll/PayrollCalculator.swift

// Shared TypeScript calculator (Wagey / server-side tools)
computeShift(shift, settings, presetRules, snapshot, job?)
// supabase/functions/_shared/wagey/payroll/calc.ts`,
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
              ['job_id', 'uuid', 'Foreign key to jobs (NOT NULL; assigned by DB trigger when legacy clients omit it)'],
              ['shift_date', 'date', 'The date of the shift (ISO: YYYY-MM-DD)'],
              ['start_time', 'text', 'Start time in HH:MM format'],
              ['end_time', 'text', 'End time in HH:MM format (supports cross-midnight)'],
              ['note', 'text', 'Private owner-only shift note'],
              ['custom_pause_windows', 'jsonb', 'Exact per-shift pause windows: { windows: [{ start, end }] }'],
              ['custom_supplements', 'jsonb', 'Shift-specific supplement overrides'],
            ],
          },
          note: 'When end_time <= start_time, shift crosses midnight (e.g., 22:00 to 06:00). note is private to the owner and is intentionally omitted from shared payloads. custom_pause_windows is normalized before persistence; empty or fully invalid payloads become NULL. Custom supplements when present completely replace snapshot supplements for this shift. Legacy clients that do not send job_id are automatically assigned the user\'s default job by a DB trigger.',
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
              ['job_id', 'uuid', 'Foreign key to jobs (NOT NULL; all generated virtual shifts inherit this job)'],
              ['start_time', 'timetz', 'Shift start time with timezone'],
              ['end_time', 'timetz', 'Shift end time with timezone'],
              ['repeat_interval_weeks', 'smallint', '0 = every week, 1 = every 2 weeks, ..., 8 = every 9 weeks'],
              ['selected_days', 'jsonb', 'Anchor dates by weekday: { "1": "2025-01-27" }'],
              ['end_condition', 'jsonb', 'End rule: { type: "never" | "months" | "years" | "end_date" }'],
              ['exclusions', 'jsonb', 'Array of ISO dates to skip'],
              ['date_specific_pause_windows', 'jsonb', 'Per-date exact pause overrides: { "2025-01-15": { windows: [...] } }'],
              ['date_specific_supplements', 'jsonb', 'Per-date custom supplements'],
              ['date_specific_notes', 'jsonb', 'Per-date private notes keyed by ISO date'],
            ],
          },
          note: 'Virtual shifts are generated at runtime, never persisted. selected_days keys are weekday numbers (0=Sunday to 6=Saturday). A recurring pattern and all its virtual shifts belong to one job — there is no per-occurrence job override. Generated virtual shifts inherit any date-specific pause windows, date-specific supplements, and date-specific private notes for their occurrence date.',
        },
        {
          heading: 'wage_snapshots - Point-in-time wage settings',
          paragraphs: ['Wage snapshots preserve historical wage accuracy and are now scoped per job:'],
          table: {
            caption: 'wage_snapshots table schema',
            headers: ['Column', 'Type', 'Default', 'Purpose'],
            rows: [
              ['id', 'uuid', '-', 'Primary key'],
              ['user_id', 'uuid', '-', 'Foreign key to auth.users'],
              ['job_id', 'uuid', '-', 'Foreign key to jobs (NOT NULL; controls which job\'s wage history applies)'],
              ['from_date', 'date', '-', 'Effective date (NULL = baseline snapshot for this job)'],
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
          note: 'Snapshots are job-scoped: one baseline (from_date = NULL) allowed per (user, job) pair. Snapshot selection uses shift date for wage/supplements/breaks, but payout date for tax settings — both lookups are job-scoped with fallback to legacy (job_id = NULL) snapshots.',
        },
        {
          heading: 'user_settings - Global user preferences',
          paragraphs: ['User preferences. Payroll-related fields (payroll_day, half_tax_month, monthly_goal) have been moved to the jobs table but are kept here as mirrors for legacy client compatibility:'],
          table: {
            caption: 'user_settings relevant columns',
            headers: ['Column', 'Type', 'Default', 'Purpose'],
            rows: [
              ['user_id', 'uuid', '-', 'Primary key, FK to auth.users'],
              ['payroll_day', 'integer', '15 (legacy mirror)', 'Kept in sync with default job\'s payroll_day for backwards compatibility'],
              ['half_tax_month', 'integer', '-', 'Kept in sync with default job\'s half_tax_month for backwards compatibility'],
              ['monthly_goal', 'integer', '20000 (legacy mirror)', 'Kept in sync with default job\'s monthly_goal for backwards compatibility'],
            ],
          },
          note: 'DB triggers keep user_settings and the default job in sync bidirectionally. The jobs table is the authoritative source for payroll_day, half_tax_month, and monthly_goal in job-aware clients. Resolution order for payroll_day: job value → user_settings.payroll_day → 1.',
        },
        {
          heading: 'payroll_adjustments - Manual payout corrections',
          paragraphs: [
            'Payroll adjustments are payout-level rows used for bonuses, retro pay, corrections, and other additions that are not tied to a single shift.',
          ],
          table: {
            caption: 'payroll_adjustments table schema',
            headers: ['Column', 'Type', 'Purpose'],
            rows: [
              ['id', 'uuid', 'Primary key'],
              ['user_id', 'uuid', 'Foreign key to auth.users'],
              ['job_id', 'uuid', 'Optional job scope; NULL means use the default job for display and tax lookup'],
              ['amount', 'numeric', 'Adjustment amount in the row currency'],
              ['currency', 'text', 'Currency display code/symbol, default kr'],
              ['category', 'text', 'One of: retro_pay, bonus, correction, other'],
              ['tax_treatment', 'text', 'One of: gross_taxable, net_manual, excluded_from_tax_estimate'],
              ['description', 'text', 'Short user-visible explanation'],
              ['note', 'text', 'Private user note'],
              ['curated_note', 'text', 'Optional Wagey-authored explanation'],
              ['curated_link', 'text', 'Optional source link for the curated explanation'],
              ['earned_from_date / earned_to_date', 'date', 'Optional earned-period range for context'],
              ['payout_date', 'date', 'Payroll date whose totals include this adjustment'],
              ['revision / deleted_at', 'bigint / timestamptz', 'Sync conflict and soft-delete metadata'],
            ],
          },
          note: 'The database validates that explicit job_id values belong to the same active user-owned job. Adjustment rows are synced through the local-first iOS store and protected by the same owner-scoped RLS model as shifts.',
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
      id: 'jobs',
      title: 'Jobs & Multi-employer Support',
      subsections: [
        {
          heading: 'What is a job?',
          paragraphs: [
            'A job represents an employer or workplace. Each user starts with one default job ("Jobb") and can add more. Jobs group shifts and wage snapshots together, and own per-employer payroll configuration.',
            'The multi-job feature is invisible for single-job users — the default job is assigned automatically and all existing flows remain unchanged.',
          ],
        },
        {
          heading: 'jobs table',
          paragraphs: ['Each job stores employer-specific payroll configuration:'],
          table: {
            caption: 'jobs table schema',
            headers: ['Column', 'Type', 'Purpose'],
            rows: [
              ['id', 'uuid', 'Primary key'],
              ['user_id', 'uuid', 'FK to auth.users'],
              ['name', 'text', 'Display name (1-100 chars)'],
              ['color', 'text', 'Hex color (#RRGGBB) for visual differentiation in shift views'],
              ['is_default', 'boolean', 'Exactly one active default per user; auto-assigned to shifts from legacy clients'],
              ['sort_order', 'smallint', 'Display ordering'],
              ['payroll_day', 'integer', 'Day of month (1-31) payroll is received for this job'],
              ['half_tax_month', 'integer', 'Month (11 or 12) for half-tax; NULL = disabled'],
              ['monthly_goal', 'integer', 'Monthly earnings goal for this job'],
              ['archived_at', 'timestamptz', 'Set when archived; job is hidden from Add Shift pickers but remains in historical views'],
              ['deleted_at', 'timestamptz', 'Soft-delete; shifts remain queryable for history'],
            ],
          },
          note: 'Unique constraint: UNIQUE (user_id) WHERE is_default = true AND deleted_at IS NULL AND archived_at IS NULL — exactly one active default per user.',
        },
        {
          heading: 'Backward compatibility',
          paragraphs: [
            'Older clients that do not send job_id continue to work unchanged. Database triggers automatically:',
          ],
          list: [
            'Assign the user\'s default job to any shift, recurring shift, or wage snapshot written without job_id',
            'Mirror payroll_day, half_tax_month, and monthly_goal between user_settings and the default job in both directions',
            'Ensure every user has a default job, creating one on-the-fly if missing',
          ],
          note: 'Legacy user_settings fields (payroll_day, half_tax_month, monthly_goal) will not be removed until telemetry confirms all clients are job-aware.',
        },
        {
          heading: 'Payroll day resolution',
          paragraphs: ['The payroll day is resolved per shift using this priority chain:'],
          code: {
            language: 'typescript',
            content: `const payrollDayForJob = (targetJobId?: string | null): number =>
  jobsById.get(targetJobId ?? '')?.payroll_day   // 1. Job's own payroll_day
  ?? defaultJob?.payroll_day                      // 2. Default job's payroll_day
  ?? userSettings?.payroll_day                    // 3. Legacy user_settings fallback
  ?? 1;                                           // 4. Hard fallback`,
          },
        },
        {
          heading: 'Job-scoped snapshot buckets',
          paragraphs: ['All wage snapshots are loaded once and grouped into buckets by job_id. Snapshot resolution tries the shift\'s own job bucket first, then falls back to the legacy bucket (snapshots with no job_id):'],
          code: {
            language: 'typescript',
            content: `// Fallback chain for snapshot lookup
const preferredKeys = [shift.job_id ?? '__legacy__', '__legacy__'];

for (const key of preferredKeys) {
  const dated = buckets.get(key)?.dated.find(s => s.from_date <= targetDate);
  if (dated) return dated;
}
for (const key of preferredKeys) {
  const baseline = buckets.get(key)?.baseline;
  if (baseline) return baseline;
}`,
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
            content: `// ShiftRow now includes job_id and optional pause overrides
type ShiftRow = {
  id: string;
  user_id: string;
  job_id?: string | null;   // Set to default job if omitted by legacy clients
  shift_date: string;
  start_time: string;
  end_time: string;
  custom_pause_windows?: CustomPauseWindows | null;
  custom_supplements?: CustomSupplementsData | null;
};

type ShiftWithComputations = ShiftRow & {
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
              title: 'Step 1: Concurrent fetch (shifts, recurring, jobs, snapshots)',
              paragraphs: ['All four queries run in parallel for maximum performance:'],
              code: {
                language: 'typescript',
                content: `const [shifts, recurringShifts, jobs, allSnapshots] = await Promise.all([
  supabase.from("user_shifts")
    .select("*").eq("user_id", userId).is("deleted_at", null)
    .gte("shift_date", startDate).lte("shift_date", endDate).limit(limit),

  supabase.from("recurring_shifts")
    .select("*").eq("user_id", userId).is("deleted_at", null),

  supabase.from("jobs")
    .select("*").eq("user_id", userId).is("deleted_at", null)
    .order("sort_order", { ascending: true }),

  supabase.from("wage_snapshots")
    .select("*").eq("user_id", userId).is("deleted_at", null)
    .order("from_date", { ascending: false, nullsFirst: false }),
]);`,
              },
            },
            {
              title: 'Step 2: Build snapshot buckets (keyed by job_id)',
              code: {
                language: 'typescript',
                content: `const buckets = new Map<string, { dated: WageSnapshot[]; baseline: WageSnapshot | null }>();

for (const snapshot of allSnapshots) {
  const key = snapshot.job_id ?? '__legacy__';
  const bucket = buckets.get(key) ?? { dated: [], baseline: null };
  if (snapshot.from_date === null) bucket.baseline = snapshot;
  else bucket.dated.push(snapshot);
  buckets.set(key, bucket);
}

for (const bucket of buckets.values()) {
  bucket.dated.sort((a, b) => b.from_date.localeCompare(a.from_date));
}`,
              },
            },
            {
              title: 'Step 3: Generate virtual shifts from recurring templates',
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
                'If all pass, add to virtual shifts (inheriting the recurring shift\'s job_id plus any date-specific pause windows and supplements)',
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
              title: 'Step 5: Compute each shift (job-scoped snapshot lookup)',
              code: {
                language: 'typescript',
                content: `for (const shift of shifts) {
  const shiftJobId = shift.job_id ?? defaultJobId;
  const payrollDay =
    jobsById.get(shiftJobId)?.payroll_day
    ?? userSettings?.payroll_day
    ?? 1;

  const scopedSnapshots = snapshotsForJob(
    shiftJobId,
    snapshotsByJobId,
    legacyNilJobSnapshots,
    defaultJobId
  );

  // Wage/supplement/break snapshot: use shift date, job-scoped
  const wageSnapshot = snapshotForDate(shift.shift_date, scopedSnapshots);

  // Tax snapshot: use payout date for THIS shift's job
  const payoutDate = calculatePayoutDate(shift.shift_date, payrollDay);
  const taxSnapshot = snapshotForDate(payoutDate, scopedSnapshots);

  const computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot);

  result.push({
    ...shift, job_id: shiftJobId, computed,
    tax_enabled: taxSnapshot?.tax_enabled ?? false,
    tax_percentage: taxSnapshot?.tax_percentage ?? 0,
  });
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
          paragraphs: ['Virtual shifts have synthetic IDs for stable UI identity and conflict detection:'],
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
  const effectivePayrollDay = Math.min(Math.max(payrollDay, 1), daysInPayoutMonth);

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
          note: 'This adjustment is used for payroll date display/countdown UX. Snapshot selection for tax uses calculatePayoutDate() (unadjusted). Holiday detection includes fixed and Easter-based Norwegian public holidays. Raw payroll_day values are clamped to the valid range for the payout month before a payout date is emitted.',
        },
        {
          heading: 'Job-scoped snapshot selection algorithm',
          paragraphs: ['Snapshots are grouped into buckets by job_id. The selection algorithm tries the shift\'s own job bucket first, then falls back to the legacy bucket (job_id = NULL):'],
          code: {
            language: 'typescript',
            content: `const resolveSnapshotForDate = (
  buckets: Map<string, SnapshotBucket>,
  snapshots: WageSnapshot[],
  date: string,
  jobId?: string | null
): WageSnapshot | null => {
  // Try job-specific bucket first, then legacy fallback
  const preferredKeys = [jobId ?? '__legacy__', '__legacy__'];

  // 1. Try dated snapshots (bucket is sorted DESC — first match = latest valid)
  for (const key of preferredKeys) {
    const dated = buckets.get(key)?.dated.find(s => s.from_date <= date);
    if (dated) return dated;
  }

  // 2. Try baselines
  for (const key of preferredKeys) {
    const baseline = buckets.get(key)?.baseline;
    if (baseline) return baseline;
  }

  return snapshots.find(s => s.from_date === null) ?? null;
};`,
          },
        },
        {
          heading: 'Selection rules',
          list: [
            'Job-specific bucket: find latest dated snapshot where from_date <= targetDate',
            'If none, use job-specific baseline snapshot (from_date = NULL)',
            'If none, fall back to legacy bucket (same search on job_id = NULL snapshots)',
            'If still none, return null (calculation uses defaults)',
            'Inclusive from_date: A snapshot with from_date = 2025-02-01 applies to target dates >= 2025-02-01',
          ],
        },
        {
          heading: 'Example: Snapshot resolution (with job scope)',
          paragraphs: ['For a shift on 2025-01-15, job payroll day = 20, jobId = "job-uuid":'],
          list: [
            'Wage snapshot lookup: targetDate = 2025-01-15 (shift date), jobId = "job-uuid"',
            'Tax snapshot lookup: targetDate = 2025-02-20 (payout date), jobId = "job-uuid"',
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
            content: `function toMin(hhmm: string): number | null {
  const [h, m] = hhmm.split(":").map(Number);
  if (!Number.isInteger(h) || !Number.isInteger(m)) return null;
  if (m < 0 || m >= 60) return null;
  if (h < 0 || h > 24) return null;
  if (h === 24 && m !== 0) return null;
  return h * 60 + m;
}
// "09:00" -> 540
// "17:30" -> 1050
// "24:00" -> 1440
// "24:30" -> null`,
          },
          note: 'Invalid shift times or invalid supplement-window times are ignored defensively. A shift with invalid start/end time produces no wage periods and therefore no calculated pay.',
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
          heading: 'Defensive normalization',
          paragraphs: [
            'The live iOS engine clamps unsafe numeric inputs before they can affect pay. This keeps corrupted snapshots or stale local data from producing negative hours, negative taxes, or non-finite earnings.',
          ],
          list: [
            'payroll_day is clamped to 1 through the number of days in the payout month',
            'tax_percentage is clamped to 0 through 100 before gross-to-net conversion',
            'break_threshold_hours falls back to the default when missing, negative, or non-finite',
            'break_deduction_minutes is clamped to zero or higher and never deducts more than the shift duration',
            'hourly wage, fixed supplements, and percentage supplements must be finite and non-negative',
            'negative wage-period durations are ignored when totaling break input periods',
          ],
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
  if (Number.isFinite(snapshot?.hourly_wage) && snapshot.hourly_wage > 0) {
    return snapshot.hourly_wage;
  }

  // Priority 2: Legacy per-shift snapshot (backward compatibility)
  if (Number.isFinite(shift.hourly_wage_snapshot) && shift.hourly_wage_snapshot > 0) {
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
  if (rule.rate != null && Number.isFinite(rule.rate) && rule.rate >= 0) {
    return rule.rate;
  }

  // Percentage of base rate
  if (rule.percent != null && Number.isFinite(rule.percent) && rule.percent >= 0) {
    return (baseRate * rule.percent) / 100;
  }

  return 0;
}`,
          },
          note: 'Stacking behavior: Highest-wins. Only the highest non-negative finite supplement rate applies to each time period.',
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
          paragraphs: [
            'Tax is applied downstream from computeShift, not inside the pure shift calculator.',
            'In the iOS app this happens when ShiftWithComputations values and monthly totals are assembled; Wagey and other server-side tools expose the same tax-derived values in their response payloads.',
          ],
          code: {
            language: 'typescript',
            content: `const taxEnabled = snapshot.tax_enabled;
const taxPercentage = Math.min(Math.max(snapshot.tax_percentage, 0), 100);

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
            content: `FUNCTION computeShift(shift, snapshot, presetRules):
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
  originalPeriods = copy(periods)

  // 6. Calculate raw duration
  totalMinutes = SUM(period.toMin - period.fromMin FOR period IN periods)
  durationHours = ROUND(totalMinutes / 60, 2)

  // 7. Apply pause handling
  IF shift.custom_pause_windows EXISTS THEN
    periods, deductedHours, appliedPauseWindows =
      clipPeriodsByPauseWindows(periods, shift.custom_pause_windows, shift.start_time, shift.end_time)
    breakAudit = {
      method: "none",
      thresholdHours: 0,
      deductedHours,
      source: "custom_pause_windows",
      appliedPauseWindows,
      notes: appliedPauseWindows.length ? ["Deducted using custom pause windows"] : []
    }
  ELSE
    breakEnabled = snapshot.break_enabled OR true
    breakMethod = snapshot.break_method OR "proportional"
    threshold = snapshot.break_threshold_hours OR 5.5
    breakMinutes = breakEnabled ? (snapshot.break_deduction_minutes OR 30) : 0
    periods, breakAudit = applyBreakDeduction(periods, breakMethod, threshold, breakMinutes/60)
  ENDIF

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
    breakAudit
  }`,
          },
        },
      ],
    },
    {
      id: 'breaks',
      title: 'Pause Windows & Break Deductions',
      subsections: [
        {
          heading: 'Automatic break deductions',
          paragraphs: [
            'Tidex deducts unpaid breaks automatically based on your configuration when a shift does not carry exact pause windows. Four deduction strategies are available.',
          ],
        },
        {
          heading: 'Exact pause windows',
          paragraphs: [
            'A shift can now store exact unpaid intervals in custom_pause_windows. Recurring templates can also attach date-specific pause windows that are copied onto generated virtual shifts for the matching date.',
            'When custom pause windows are present, the engine clips those intervals out of the computed wage periods before pay is calculated. This overrides the automatic break rule for that shift and records the deduction source as custom_pause_windows.',
          ],
          code: {
            language: 'typescript',
            content: `if (normalizedPauseWindows) {
  const afterPause = applyCustomPauseWindowClipping(
    periods,
    normalizedPauseWindows,
    shift.start_time,
    shift.end_time
  );

  periods = afterPause.periods;
  breakAudit = {
    method: "none",
    thresholdHours: 0,
    deductedHours: afterPause.deductedHours,
    source: "custom_pause_windows",
    appliedPauseWindows: afterPause.appliedPauseWindows,
    notes: afterPause.appliedPauseWindows?.length
      ? ["Deducted using custom pause windows"]
      : [],
  };
} else {
  const afterBreak = applyBreakDeduction(periods, method, threshold, breakHours);
  periods = afterBreak.periods;
  breakAudit = afterBreak.audit;
}`,
          },
          note: 'Pause windows are normalized, deduplicated, and merged when they overlap. Cross-midnight pause windows are supported using the same extended timeline model as cross-midnight shifts.',
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
  source: "none" | "automatic_break" | "custom_pause_windows";
  appliedPauseWindows?: PauseWindow[];
  notes?: string[];
};`,
          },
        },
        {
          heading: 'Shared and previewed shifts',
          paragraphs: [
            'Shared month payloads, sharer previews, and Wagey what-if calculations now carry custom pause windows and the richer break-audit metadata as part of the current rollout.',
            'That means paid-hours recomputation stays accurate even when earnings are hidden, because pause overrides are still available to the consumer.',
          ],
        },
      ],
    },
    {
      id: 'adjustments',
      title: 'Payroll Adjustments',
      subsections: [
        {
          heading: 'What adjustments represent',
          paragraphs: [
            'Payroll adjustments are manual payout-level amounts that are added after shift earnings have been computed. They cover bonuses, retro pay, corrections, and other payroll items that should appear on a payout but do not come from a shift.',
            'Adjustments are filtered by payout_date. They are not allocated back into shift wage periods and do not change durationHours, paidHours, basePay, or supplementPay for any shift.',
          ],
        },
        {
          heading: 'Tax treatments',
          table: {
            caption: 'Adjustment tax behavior',
            headers: ['Tax treatment', 'Gross contribution', 'Net contribution', 'Uses tax estimate'],
            rows: [
              ['gross_taxable', 'amount', 'amount minus estimated tax using the adjustment payout tax settings', 'Yes, when tax is enabled'],
              ['net_manual', 'amount', 'amount exactly as entered', 'No'],
              ['excluded_from_tax_estimate', 'amount', 'amount exactly as entered', 'No'],
            ],
          },
          note: 'gross_taxable adjustments use the same half-tax rule as shift totals: if half_tax_month equals the payout month, the effective tax percentage is halved before calculating net.',
        },
        {
          heading: 'Adjustment totals algorithm',
          code: {
            language: 'typescript',
            content: `function payrollAdjustmentTotals(
  adjustments: PayrollAdjustment[],
  taxSettingsForAdjustment: (a: PayrollAdjustment) => PayoutTaxSettings,
  halfTaxMonth: number | null,
  payoutMonth: number
): PayrollAdjustmentTotals {
  return adjustments
    .filter(a => !a.deleted_at)
    .reduce((totals, adjustment) => {
      const tax = taxSettingsForAdjustment(adjustment);
      const gross = adjustment.amount;

      if (adjustment.tax_treatment !== "gross_taxable") {
        return {
          gross: totals.gross + gross,
          net: totals.net + gross,
          taxEnabled: totals.taxEnabled,
        };
      }

      const pct = Math.min(Math.max(tax.percentage, 0), 100);
      const effectivePct = halfTaxMonth === payoutMonth ? pct / 2 : pct;
      const net = tax.enabled ? gross * (1 - effectivePct / 100) : gross;

      return {
        gross: totals.gross + gross,
        net: totals.net + net,
        taxEnabled: totals.taxEnabled || tax.enabled,
      };
    }, { gross: 0, net: 0, taxEnabled: false });
}`,
          },
        },
        {
          heading: 'Job and tax lookup',
          paragraphs: [
            'An adjustment can be tied to a job. If job_id is omitted, the default job is used for display grouping and tax snapshot lookup.',
            'Tax settings for a gross_taxable adjustment are resolved from the adjustment payout_date, scoped to the adjustment job using the same job-specific snapshot fallback chain as shift tax lookup.',
          ],
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

const shiftTotals = included.reduce((acc, shift) => ({
  totalHours: acc.totalHours + shift.computed.paidHours,
  totalEarnings: acc.totalEarnings + shift.computed.gross,
}), { totalHours: 0, totalEarnings: 0 });`,
          },
          note: 'Monthly shift totals remain shift-only. Payout cards add payroll adjustments separately so hours and average-hourly metrics are not distorted by non-shift money.',
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
const netAmount = grossAmount - taxAmount;

const adjustmentTotals = payrollAdjustmentTotals(
  payoutAdjustments,
  () => payoutTax,
  halfTaxMonth,
  payoutMonth
);

const payoutGross = grossAmount + adjustmentTotals.gross;
const payoutNet = netAmount + adjustmentTotals.net;`,
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
        {
          heading: 'Test case 10: Payroll adjustment with tax',
          code: {
            language: 'typescript',
            content: `// Input
const adjustment = {
  amount: 1000,
  tax_treatment: "gross_taxable",
  payout_date: "2025-12-15",
};

const payoutTax = {
  enabled: true,
  percentage: 30,
};

const halfTaxMonth = 12;

// Expected adjustment contribution
// Payout month = December, so half-tax applies
const effectiveTaxPct = 30 / 2; // 15%

{
  gross: 1000.00,
  net: 850.00,
  taxEnabled: true,
}`,
          },
        },
      ],
    },
  ],
} as const;

export default function PayrollDocsPageRoute() {
  return <PayrollDocsPage docs={payrollDocs} />;
}
