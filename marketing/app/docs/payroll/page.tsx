import { Metadata } from 'next';
import socialPreviewEn from '@/public/og/landing-en.png';
import { marketingEn } from '@/lib/i18n/dictionaries/marketing.en';
import { PayrollDocsPage, type PayrollDocs } from './PayrollDocsPage';

const title = 'How Tidex calculates your pay';
const description =
  'Every rule Tidex uses to calculate pay: supplements, breaks, overtime, paydays, tax and totals, with worked examples.';

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: '/docs/payroll/' },
  openGraph: {
    title,
    description,
    url: '/docs/payroll/',
    type: 'website',
    images: [
      {
        url: socialPreviewEn.src,
        width: socialPreviewEn.width,
        height: socialPreviewEn.height,
        alt: marketingEn.meta.ogImageAlt,
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title,
    description,
    images: [socialPreviewEn.src],
  },
};

// Mirrors ios/TidexApp/Services/Payroll and docs/PAYROLL_ENGINE_SPEC.md. Update both when a rule changes.
const payrollDocs: PayrollDocs = {
  badge: 'Payroll reference',
  title: 'How Tidex calculates your pay',
  titleEmphasis: 'your pay',
  subtitle:
    'Every rule Tidex uses to turn your shifts into pay, tax and a payday, with worked examples you can check your numbers against.',
  updated: 'Updated 30 September 2026',
  quickLinksHeading: 'Common questions',
  quickLinks: [
    { question: 'Which hourly wage applies?', id: 'wage-settings' },
    { question: 'Why was a break deducted?', id: 'breaks' },
    { question: 'When does overtime start?', id: 'overtime' },
    { question: 'When do I get paid?', id: 'payday' },
    { question: 'Why is a shift crossed out?', id: 'totals' },
    { question: 'How do I check my numbers?', id: 'examples' },
  ],

  navigation: [
    { id: 'overview', label: 'Overview' },
    { id: 'shifts', label: 'Shifts' },
    { id: 'wage-settings', label: 'Wage settings' },
    { id: 'supplements', label: 'Supplements' },
    { id: 'breaks', label: 'Breaks' },
    { id: 'overtime', label: 'Overtime' },
    { id: 'payday', label: 'Payday and tax' },
    { id: 'totals', label: 'Totals' },
    { id: 'reference', label: 'Reference' },
    { id: 'examples', label: 'Examples' },
  ],

  bugReportCta: {
    heading: 'Numbers don\'t match?',
    description:
      'Send us the shift times, your wage settings and the amount you expected. We will check the calculation.',
    buttonText: 'Report a calculation issue',
    emailSubject: 'Payroll calculation issue',
    emailBody:
      'Shift date and times:\nJob and wage settings:\nAmount shown in Tidex:\nAmount I expected:\n',
  },

  sections: [
    {
      id: 'overview',
      title: 'Overview',
      summary:
        'Tidex prices each shift on its own, adds weekly overtime, then groups shifts by payday and applies tax.',
      subsections: [
        {
          heading: 'The calculation in order',
          ordered: true,
          list: [
            'Find the wage settings that were active on the shift date.',
            'Split the shift into periods wherever a supplement starts or stops.',
            'Remove unpaid time, using your exact pauses or the automatic break.',
            'Price each period at hours × (hourly wage + supplement).',
            'Leave out overlapping shifts, keeping only the lowest-paid one.',
            'Apply weekly overtime once a job passes its weekly hour limit.',
            'Assign the shift to a payday and apply the tax rate active on that payday.',
            'Add up the shifts and any manual adjustments for each payday.',
          ],
        },
        {
          heading: 'Rules worth knowing',
          table: {
            headers: ['Rule', 'What it means'],
            rows: [
              [
                'Wage follows the shift date, tax follows the payday',
                'A raise from 1 February applies to shifts on or after 1 February. A new tax rate from 1 February also applies to January shifts paid in February.',
              ],
              [
                'Night shifts belong to their start date',
                'A shift from 22:00 on 15 January to 06:00 the next morning is a 15 January shift.',
              ],
              [
                'The break threshold is strict',
                'With a 5.5-hour threshold, a shift of exactly 5.5 hours has no break deducted.',
              ],
              [
                'Supplements don\'t stack',
                'When two supplements cover the same minute, only the higher one is paid.',
              ],
              [
                'Overtime replaces supplements',
                'An overtime minute earns the overtime premium instead of the ordinary supplement.',
              ],
              [
                'Overlapping shifts count once',
                'Totals keep the lowest-paid shift and cross out the others.',
              ],
              [
                'Pay is rounded once per shift',
                'Hours are never rounded. Base pay and supplement pay are each rounded to 2 decimals after the whole shift is added up.',
              ],
            ],
          },
        },
        {
          heading: 'Terms',
          table: {
            headers: ['Term', 'Meaning'],
            rows: [
              ['Job', 'An employer. Each job has its own wage settings, payday, pay period and currency.'],
              ['Wage settings', 'Hourly wage, supplements, overtime, break and tax rules, valid from a start date. Stored as a wage snapshot.'],
              ['Supplement', 'An extra hourly amount for set hours, such as evenings or Sundays.'],
              ['Pause', 'An exact unpaid interval you add to a shift.'],
              ['Pay period', 'The days whose work is paid together.'],
              ['Payday', 'The date a pay period is paid out.'],
              ['Adjustment', 'A one-off amount on a payday, such as a bonus or back pay.'],
              ['Gross / net', 'Pay before tax / pay after the estimated tax.'],
            ],
          },
        },
      ],
    },
    {
      id: 'shifts',
      title: 'Shifts',
      summary:
        'A shift is a date, a start time and an end time. If the end is at or before the start, the shift runs past midnight.',
      subsections: [
        {
          heading: 'Times',
          list: [
            'Times use 24-hour `HH:MM`. `24:00` is allowed and means the end of the day.',
            'If the end time is at or before the start time, Tidex adds 24 hours to the end. 22:00 to 06:00 is 8 hours.',
            'A shift belongs to the date it starts, even when it ends the next day.',
            'Hours are exact to the minute.',
            'A shift with an invalid time has no pay.',
          ],
        },
        {
          heading: 'Recurring shifts',
          list: [
            'A recurring shift repeats on chosen weekdays every 1 to 9 weeks.',
            'Tidex creates each occurrence when it needs it. Occurrences are not stored as separate shifts.',
            'For every second week or more, Tidex counts whole weeks from the start date you picked for that weekday. Every second week matches when that count is even, every third week when it divides by 3, and so on.',
            'You can skip single dates, and set pauses, supplements and notes for a single date.',
            'Every occurrence belongs to the recurring shift\'s job.',
          ],
        },
        {
          heading: 'Jobs',
          list: [
            'Each shift belongs to one job. Pay, payday and tax rules come from that job.',
            'Every account has one default job. A shift saved without a job goes there.',
            'A job\'s currency is set when the job is created and can\'t change.',
            'Dashboard totals use one currency at a time and flag months that mix currencies.',
          ],
        },
      ],
    },
    {
      id: 'wage-settings',
      title: 'Wage settings',
      summary:
        'Wage settings have a start date. Each shift uses the newest settings that started on or before its date.',
      subsections: [
        {
          heading: 'What they contain',
          list: [
            'Hourly wage, and the tariff and level if you use one',
            'Supplement rules',
            'Overtime rules',
            'Break rules',
            'Tax on or off, and the tax percentage',
          ],
        },
        {
          heading: 'Which settings apply',
          ordered: true,
          list: [
            'Look only at the settings for the shift\'s job.',
            'Pick the newest settings whose start date is on or before the target date. The start date itself counts.',
            'If none have started yet, use the job\'s undated baseline settings.',
          ],
          note: 'The target date is the shift date for wage, supplements, overtime and breaks. For tax it is the payday. If a job has no settings of its own, Tidex uses the default job\'s settings.',
        },
        {
          heading: 'Example',
          table: {
            headers: ['Settings', 'Starts', 'Hourly wage', 'Tax'],
            rows: [
              ['Baseline', 'No date', '180.00', '25 %'],
              ['January', '2025-01-01', '185.00', '30 %'],
              ['February', '2025-02-01', '190.00', '35 %'],
            ],
          },
          note: 'A shift on 15 January 2025 that is paid on 20 February 2025 earns 185.00 an hour from the January settings and is taxed at 35 % from the February settings.',
        },
        {
          heading: 'Missing or invalid values',
          table: {
            headers: ['Value', 'Used instead'],
            rows: [
              ['Hourly wage', '184.54, tariff level 1'],
              ['Break', 'On, proportional, 30 minutes after 5.5 hours'],
              ['Tax', 'Off'],
              ['Overtime', 'Off'],
              ['Supplements', 'The built-in rules under Supplements, but only if the job has no wage settings at all'],
            ],
          },
          note: 'Tidex also limits tax to 0 to 100 %, ignores negative wages and supplements, and never deducts a break longer than the shift.',
        },
      ],
    },
    {
      id: 'supplements',
      title: 'Supplements',
      summary:
        'A supplement adds an hourly amount during set hours on set weekdays. When several match the same minute, only the highest is paid.',
      subsections: [
        {
          heading: 'How a rule works',
          table: {
            headers: ['Field', 'Meaning'],
            rows: [
              ['`days`', 'Weekdays from 1 to 7. Monday is 1, Sunday is 7.'],
              ['`from`', 'Start time. This minute is included.'],
              ['`to`', 'End time. This minute is not included. `24:00` means the end of the day.'],
              ['`rate`', 'Fixed amount per hour.'],
              ['`percent`', 'Percent of the hourly wage. Used only when `rate` is empty or invalid.'],
            ],
          },
          code: `{ "days": [1, 2, 3, 4, 5], "from": "18:00", "to": "21:00", "rate": 22 }
// Monday to Friday, 18:00 to 21:00, plus 22 an hour`,
        },
        {
          heading: 'Around midnight',
          list: [
            'The weekday is the day the window starts. A Friday window from 22:00 to 02:00 covers Friday night and early Saturday.',
            'At midnight, the next day\'s rules take over. A Saturday evening supplement ends at 24:00 and the Sunday supplement starts.',
          ],
        },
        {
          heading: 'Custom supplements on one shift',
          paragraphs: [
            'Supplements set on a single shift replace the job\'s rules for that shift. They apply on every weekday, including after midnight. An empty list means the shift has no supplements.',
          ],
        },
        {
          heading: 'Built-in rules',
          paragraphs: [
            'Tidex uses these only when a job has no wage settings at all. Your own or your tariff\'s rules replace them.',
          ],
          table: {
            headers: ['Period', 'Days', 'Time', 'Supplement'],
            rows: [
              ['Weekday evening', 'Monday to Friday', '18:00-21:00', '+22 an hour'],
              ['Weekday night', 'Monday to Friday', '21:00-24:00', '+45 an hour'],
              ['Saturday afternoon', 'Saturday', '13:00-15:00', '+45 an hour'],
              ['Saturday late afternoon', 'Saturday', '15:00-18:00', '+55 an hour'],
              ['Saturday evening', 'Saturday', '18:00-24:00', '+110 an hour'],
              ['Sunday', 'Sunday', 'All day', '+115 an hour'],
            ],
          },
        },
      ],
    },
    {
      id: 'breaks',
      title: 'Breaks',
      summary:
        'Pauses you enter always win. Without them, Tidex deducts an automatic break when the shift is longer than the threshold.',
      subsections: [
        {
          heading: 'Exact pauses',
          list: [
            'Tidex cuts each pause out of the shift at its exact times.',
            'Overlapping pauses are merged. A pause can cross midnight.',
            'A shift with pauses gets no automatic break.',
            'A recurring shift can have pauses for a single date.',
          ],
        },
        {
          heading: 'Automatic break',
          list: [
            'By default the break is on and lasts 30 minutes when a shift is longer than 5.5 hours.',
            'Longer means strictly longer. A shift of exactly 5.5 hours has no break.',
            'The break is never longer than the shift.',
          ],
        },
        {
          heading: 'Where the break comes from',
          table: {
            headers: ['Method', 'Deducts from', 'Effect'],
            rows: [
              ['`proportional` (default)', 'Every period, in proportion to its length', 'Base pay and supplements shrink by the same share'],
              ['`base_only`', 'Periods with the lowest supplement first', 'Evening and weekend hours stay paid'],
              ['`end_of_shift`', 'The last minutes of the shift', 'Same as leaving early'],
              ['`none`', 'Nothing', 'All hours are paid'],
            ],
          },
          note: 'Proportional deduction uses exact fractions of a minute. The other methods deduct whole minutes.',
        },
        {
          heading: 'Example',
          paragraphs: [
            'A Wednesday shift from 22:00 to 06:00 has a 45 an hour supplement until 24:00. The shift is 8 hours, so a 30-minute proportional break applies. The 2 supplement hours lose 2/8 of it (7.5 minutes). The 6 plain hours lose 6/8 (22.5 minutes).',
          ],
        },
      ],
    },
    {
      id: 'overtime',
      title: 'Overtime',
      summary:
        'Once a job passes its weekly hour limit, each further paid minute that week earns an overtime premium instead of the ordinary supplement.',
      subsections: [
        {
          heading: 'How it works',
          list: [
            'Overtime is off unless the wage settings turn it on. Settings based on a tariff start with the tariff\'s overtime rules.',
            'The default limit is 40 paid hours a week.',
            'A week runs from Monday 00:00 to Sunday 24:00 in your time zone.',
            'Hours count per job. Hours at two jobs are never added together.',
            'Tidex counts paid hours in time order. Breaks and crossed-out overlapping shifts don\'t count.',
            'A shift can be partly overtime. Overtime starts at the minute the limit is reached.',
            'Overtime premium = hourly wage × overtime percent. It replaces the ordinary supplement for those minutes.',
            'Each shift uses the overtime rules from the wage settings active on its date.',
          ],
        },
        {
          heading: 'Default overtime rules',
          table: {
            headers: ['Days', 'Time', 'Premium'],
            rows: [
              ['Monday to Saturday', '00:00-21:00', '50 % of hourly wage'],
              ['Monday to Saturday', '21:00-24:00', '100 % of hourly wage'],
              ['Sunday', 'All day', '100 % of hourly wage'],
              ['Norwegian public holidays', 'All day', '100 % of hourly wage'],
            ],
          },
          note: 'The rules must cover every minute of every day, public holidays included. If they don\'t, Tidex treats overtime as off. When several rules match, the highest percent wins.',
        },
        {
          heading: 'Example',
          paragraphs: [
            'Hourly wage 200, no supplements, no breaks. Monday to Thursday from 08:00 to 18:00 adds up to 40 hours. A Friday shift from 08:00 to 12:00 is all overtime at 50 %, so it pays 4 × 200 base plus 4 × 100 premium, which is 1200.00.',
          ],
        },
      ],
    },
    {
      id: 'payday',
      title: 'Payday and tax',
      summary:
        'Each job has a pay period and a payday. A shift is paid on the payday of the period it falls in, and taxed at the rate active on that payday.',
      subsections: [
        {
          heading: 'Pay periods',
          table: {
            headers: ['Pay period', 'Covers', 'Payday'],
            rows: [
              ['Calendar month (default)', 'The 1st to the last day of the month', 'The payroll day in the next month'],
              ['Monthly from a start day', 'The start day (1 to 28) to the day before the next start day', 'The payroll day in the month the period ends, or in the month after'],
              ['Every two weeks', '14-day blocks counted from an end date you choose', '0 to 27 days after the block ends'],
            ],
          },
          note: 'A payday in the month the period ends has to come after the period ends. If it doesn\'t, Tidex moves it to the next month. A payroll day past the end of a month becomes the last day, so day 31 in February is 28 or 29 February.',
        },
        {
          heading: 'Payday shown in the app',
          paragraphs: [
            'If the payday falls on a weekend, a Monday or a Norwegian public holiday, the app shows the nearest earlier Tuesday to Friday that is not a holiday. This moves only the displayed date and countdown. Tax still uses the original payday.',
          ],
        },
        {
          heading: 'Tax',
          list: [
            'Tax is a flat percentage from the wage settings active on the payday.',
            'Net = gross × (1 − tax percent ÷ 100).',
            'If the payday falls in the job\'s half-tax month (November or December), the tax percent is halved.',
            'This is an estimate based on the percentage you enter. Your payslip uses your tax deduction card.',
          ],
        },
        {
          heading: 'Example',
          paragraphs: [
            'A shift on 15 November, calendar-month pay period, payroll day 20. The payday is 20 December. With 30 % tax and December as the half-tax month, the shift is taxed at 15 %.',
          ],
        },
      ],
    },
    {
      id: 'totals',
      title: 'Totals',
      summary:
        'Totals add up the included shifts. Overlapping shifts count once, and adjustments only appear on payday totals.',
      subsections: [
        {
          heading: 'Overlapping shifts',
          list: [
            'Two shifts on the same date overlap when their times intersect. One ending exactly when the other starts is not an overlap.',
            'In each group of overlapping shifts, Tidex keeps the one with the lowest gross pay before overtime. If two tie, the one that starts first stays.',
            'The other shifts stay visible but are crossed out. They don\'t count toward totals or overtime.',
          ],
        },
        {
          heading: 'Adjustments',
          paragraphs: [
            'An adjustment is a one-off amount on a payday, such as a bonus, back pay or a correction. It is added to that payday\'s total and never changes a shift\'s hours or pay. An adjustment without a job uses the default job.',
          ],
          table: {
            headers: ['Tax treatment', 'Net amount'],
            rows: [
              ['`gross_taxable`', 'The amount minus tax at the payday\'s rate, halved in the half-tax month'],
              ['`net_manual`', 'The amount as entered'],
              ['`excluded_from_tax_estimate`', 'The amount as entered'],
            ],
          },
        },
        {
          heading: 'What each total means',
          table: {
            headers: ['Total', 'Calculation'],
            rows: [
              ['Month total', 'Included shifts worked in the month. Net when tax is on, otherwise gross. No adjustments.'],
              ['Earned so far', 'The same, counting only shifts that have ended.'],
              ['Payday card', 'Included shifts in the pay period plus that payday\'s adjustments, for the next job to be paid. Jobs with the same payday share one card.'],
              ['Average per shift', 'Earnings ÷ number of shifts'],
              ['Average hourly', 'Earnings ÷ paid hours'],
              ['Month over month', '(this month − last month) ÷ last month × 100'],
            ],
          },
        },
      ],
    },
    {
      id: 'reference',
      title: 'Reference',
      summary: 'Formulas, rounding and the database fields behind the rules above.',
      subsections: [
        {
          heading: 'Formulas',
          code: `duration_hours = (end - start) / 60        // add 1440 to end when end <= start
paid_hours     = duration_hours - unpaid_hours

base_pay       = round2(sum(period_hours * hourly_wage))
supplement_pay = round2(sum(period_hours * supplement_rate))
gross          = round2(base_pay + supplement_pay)

tax_percent    = half_tax_month ? tax_percentage / 2 : tax_percentage
net            = gross * (1 - tax_percent / 100)`,
          note: '`round2` rounds to 2 decimals, halves away from zero. A period\'s `supplement_rate` is the highest matching supplement, or the overtime premium for overtime minutes.',
        },
        {
          heading: '`user_shifts`',
          table: {
            headers: ['Column', 'Meaning'],
            rows: [
              ['`job_id`', 'The job. Set to the default job when missing.'],
              ['`shift_date`', 'Start date, `YYYY-MM-DD`'],
              ['`start_time`, `end_time`', '`HH:MM`. An end at or before the start crosses midnight.'],
              ['`custom_pause_windows`', '`{ windows: [{ start, end }] }`'],
              ['`custom_supplements`', 'Replaces the job\'s supplement rules for this shift'],
            ],
          },
        },
        {
          heading: '`recurring_shifts`',
          table: {
            headers: ['Column', 'Meaning'],
            rows: [
              ['`repeat_interval_weeks`', '0 is every week, 1 every second week, up to 8 for every ninth week'],
              ['`selected_days`', 'Start date per weekday, `{ "1": "2025-01-27" }`. Here 0 is Sunday and 6 is Saturday.'],
              ['`end_condition`', '`never`, after a number of months or years, or an end date'],
              ['`exclusions`', 'Dates to skip'],
              ['`date_specific_pause_windows`, `date_specific_supplements`', 'Overrides for one date'],
            ],
          },
        },
        {
          heading: '`wage_snapshots`',
          table: {
            headers: ['Column', 'Default', 'Meaning'],
            rows: [
              ['`job_id`', '', 'The job these settings belong to'],
              ['`from_date`', '', 'Start date. Empty for the baseline, one per job.'],
              ['`hourly_wage`', '', 'Hourly wage in the job currency'],
              ['`supplements`', '', '`{ rules: [...] }`'],
              ['`overtime`', 'off, 40 h', '`{ enabled, weeklyThresholdHours, rules: [{ days, appliesOnHolidays, from, to, percent }] }`'],
              ['`break_enabled`, `break_method`', 'on, `proportional`', 'Automatic break'],
              ['`break_threshold_hours`, `break_deduction_minutes`', '5.5, 30', 'Break threshold and length'],
              ['`tax_enabled`, `tax_percentage`', 'off, 0', 'Tax estimate'],
            ],
          },
        },
        {
          heading: '`jobs`',
          table: {
            headers: ['Column', 'Meaning'],
            rows: [
              ['`is_default`', 'One active default job per user'],
              ['`currency`', 'Fixed when the job is created'],
              ['`payroll_day`', 'Day of the month for monthly paydays, 1 to 31'],
              ['`pay_period`', 'Empty for calendar month, `{ type: "monthly", startDay, payoutMonthOffset }` or `{ type: "biweekly", anchorEnd, payoutDelayDays }`'],
              ['`half_tax_month`', '11, 12 or empty'],
            ],
          },
        },
        {
          heading: '`payroll_adjustments`',
          table: {
            headers: ['Column', 'Meaning'],
            rows: [
              ['`amount`', 'Amount in the job currency'],
              ['`payout_date`', 'The payday this amount is added to'],
              ['`job_id`', 'The job. Empty means the default job.'],
              ['`category`', '`retro_pay`, `bonus`, `correction` or `other`'],
              ['`tax_treatment`', 'See Adjustments under Totals'],
            ],
          },
        },
        {
          heading: 'Source code',
          list: [
            '`ios/TidexApp/Services/Payroll/PayrollEngine.swift` handles months, tax lookup and overtime.',
            '`ios/TidexApp/Services/Payroll/PayrollCalculator.swift` prices one shift.',
            '`ios/TidexApp/Services/Payroll/BreakDeduction.swift` and `ConflictExclusion.swift` handle breaks and overlaps.',
            '`ios/Shared/PayPeriod.swift` works out pay periods and paydays.',
            '`supabase/functions/_shared/payroll/calc.ts` is the TypeScript version used by server-side tools.',
          ],
        },
      ],
    },
    {
      id: 'examples',
      title: 'Examples',
      summary:
        'Worked cases with the expected result. Use them to check your own numbers or another implementation.',
      subsections: [
        {
          heading: 'Single shifts',
          table: {
            headers: ['Shift', 'Settings', 'Paid hours', 'Base', 'Supplement', 'Gross'],
            rows: [
              ['Wed 09:00-14:00', '185/h, no supplements, no break', '5.00', '925.00', '0.00', '925.00'],
              ['Wed 17:00-22:00', '185/h, +22 from 18-21, +45 from 21-24, no break', '5.00', '925.00', '111.00', '1036.00'],
              ['Wed 22:00-06:00', '185/h, +45 from 21-24, 30 min proportional break after 5.5 h', '7.50', '1387.50', '84.38', '1471.88'],
              ['Sun 08:00-16:00', '185/h, +115 all Sunday, 30 min break after 5.5 h', '7.50', '1387.50', '862.50', '2250.00'],
              ['Wed 09:00-14:30', '185/h, no supplements, 30 min break after 5.5 h', '5.50', '1017.50', '0.00', '1017.50'],
              ['Wed 18:00-22:00', '200/h, +50 % on Wednesday 18-24, no break', '4.00', '800.00', '400.00', '1200.00'],
              ['Sat 20:00-02:00', '185/h, +110 Saturday 18-24, +115 all Sunday, no break', '6.00', '1110.00', '670.00', '1780.00'],
            ],
          },
          note: 'Dates used are Wednesday 15, Saturday 18 and Sunday 19 January 2025.',
        },
        {
          heading: 'Paydays',
          table: {
            headers: ['Pay period', 'Shift', 'Payday', 'Shown in app'],
            rows: [
              ['Calendar month, payroll day 20', '2025-01-15', '2025-02-20', 'Thu 20 Feb'],
              ['Calendar month, payroll day 17', '2025-01-15', '2025-02-17', 'Fri 14 Feb, because the 17th is a Monday'],
              ['Monthly from the 20th, paid the same month, payroll day 25', '2025-01-15', '2025-01-25', 'Fri 24 Jan, because the 25th is a Saturday'],
              ['Every two weeks, block ending 2025-01-12, paid 5 days later', '2025-01-15', '2025-01-31', 'Fri 31 Jan'],
            ],
          },
        },
        {
          heading: 'Tax, overlaps, overtime and adjustments',
          table: {
            headers: ['Case', 'Input', 'Result'],
            rows: [
              ['Half tax', 'Gross 1036.00 on 2025-11-15, calendar month, 30 % tax, half-tax month December', 'Payday is in December, so tax is 15 %. Net 880.60.'],
              ['Overlap', 'Wed 09:00-17:00 earns 1480.00. Wed 14:00-22:00 earns 1591.00 with the weekday supplements. No breaks.', 'They overlap 14:00-17:00. Totals keep the 1480.00 shift and cross out the other.'],
              ['Overtime', '200/h, 40 h limit, default overtime rules, no breaks. 08:00-18:00 on Monday 2 to Thursday 5 February 2026, then 08:00-12:00 on Friday 6 February.', 'Friday is all overtime at 50 %: base 800.00, premium 400.00, gross 1200.00.'],
              ['Adjustment', '`gross_taxable` bonus of 1000.00 paid 2025-12-15, 30 % tax, half-tax month December', 'Gross 1000.00, net 850.00'],
            ],
          },
        },
      ],
    },
  ],
};

export default function PayrollDocsPageRoute() {
  return <PayrollDocsPage docs={payrollDocs} />;
}
