'use client';

import { useMemo, useState } from 'react';
import { Button } from '@/components/app/Button';
import { Input } from '@/components/app/Input';
import { Separator } from '@/components/app/Separator';
import { Download } from 'lucide-react';
import { cn } from '@/lib/cn';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { useTranslations } from '@/lib/i18n/client';
import type { Locale } from '@/lib/i18n/config';
import { getDateFormatter } from '@/lib/i18n/locale';

const JSPDF_CDN = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';

const PAGE_CONFIG = {
  format: 'a4',
  orientation: 'portrait',
  unit: 'mm',
  width: 210,
  height: 297,
  margins: {
    left: 20,
    right: 190,
    top: 20,
    bottom: 277,
  },
  footerY: 287,
} as const;

const DOCUMENT_PROPERTIES = {
  subject: 'Lønn og vaktdetaljer',
  author: 'Tidex',
  creator: 'Tidex',
} as const;

const DOCUMENT_TITLE = {
  no: 'Vakt- og lønnsrapport',
  en: 'Shift and earnings report',
} as const;

const TABLE_HEADER = {
  columns: ['Dato', 'Dag', 'Start', 'Slutt', 'Timer', 'Grunnlønn', 'Tillegg', 'Totalt'],
  widths: [25, 20, 15, 15, 15, 25, 25, 25],
} as const;

type PeriodPreset = 'current_month' | 'last_month' | 'current_year' | 'custom';

type DateRange = {
  from: string;
  to: string;
};

const PERIOD_CONFIG: Record<
  Exclude<PeriodPreset, 'custom'>,
  { resolve: () => DateRange }
> = {
  current_month: {
    resolve: () => {
      const now = new Date();
      const from = new Date(now.getFullYear(), now.getMonth(), 1);
      const to = new Date(now.getFullYear(), now.getMonth() + 1, 0);
      return {
        from: toIsoDate(from),
        to: toIsoDate(to),
      };
    },
  },
  last_month: {
    resolve: () => {
      const now = new Date();
      const from = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      const to = new Date(now.getFullYear(), now.getMonth(), 0);
      return {
        from: toIsoDate(from),
        to: toIsoDate(to),
      };
    },
  },
  current_year: {
    resolve: () => {
      const now = new Date();
      const from = new Date(now.getFullYear(), 0, 1);
      const to = new Date(now.getFullYear(), 11, 31);
      return {
        from: toIsoDate(from),
        to: toIsoDate(to),
      };
    },
  },
} as const;

const PRESET_ORDER: ReadonlyArray<Exclude<PeriodPreset, 'custom'>> = [
  'last_month',
  'current_month',
  'current_year',
];

function capitalize(value: string): string {
  if (!value) return value;
  return value[0].toUpperCase() + value.slice(1);
}

type JsPDFInstance = {
  setProperties: (properties: Record<string, string>) => void;
  setFont: (font: string, style?: string, size?: number) => void;
  setFontSize: (size: number) => void;
  text: (text: string, x: number, y: number, options?: any) => void;
  line: (x1: number, y1: number, x2: number, y2: number) => void;
  addPage: () => void;
  getNumberOfPages: () => number;
  setPage: (page: number) => void;
  save: (filename: string) => void;
  setLineWidth: (width: number) => void;
  addImage: (imageData: string, format: string, x: number, y: number, width: number, height: number) => void;
  getTextWidth: (text: string) => number;
};

type JsPDFConstructor = new (options?: {
  orientation?: string;
  unit?: string;
  format?: string;
}) => JsPDFInstance;

type ShiftCalculation = {
  hours: number;
  baseWage: number;
  supplement: number;
  total: number;
};

type RawShift = {
  id: string;
  date: string;
  startTime: string;
  endTime: string;
  type: number;
  recurringId: string | null;
  calc: ShiftCalculation;
};

type PreparedShift = RawShift & {
  dateObj: Date;
};

type ExportPayload = {
  generatedAt: string;
  shifts: RawShift[];
};

type PreparedExportData = {
  shifts: PreparedShift[];
  totals: {
    totalHours: number;
    totalBaseWage: number;
    totalSupplement: number;
    totalWages: number;
  };
  countsByType: {
    weekday: number;
    saturday: number;
    sunday: number;
  };
  firstDate: Date | null;
  lastDate: Date | null;
};

declare global {
  interface Window {
    jspdf?: { jsPDF: JsPDFConstructor };
  }
}

function toIsoDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function parseIsoDate(value: string): Date | null {
  if (!value) return null;
  const parsed = new Date(`${value}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed;
}

function getPresetLabel(preset: Exclude<PeriodPreset, 'custom'>, locale: Locale): string {
  const now = new Date();
  if (preset === 'current_year') {
    return String(now.getFullYear());
  }

  const baseMonth =
    preset === 'current_month'
      ? new Date(now.getFullYear(), now.getMonth(), 1)
      : new Date(now.getFullYear(), now.getMonth() - 1, 1);

  const monthFormatter = getDateFormatter(locale, { month: 'long' });
  return capitalize(monthFormatter.format(baseMonth));
}

function formatCurrencyShort(value: number, locale: Locale): string {
  // Format with thousands separator: . for Norwegian, , for English
  const separator = locale === 'no' ? '.' : ',';
  return Math.round(value).toString().replace(/\B(?=(\d{3})+(?!\d))/g, separator);
}

function formatHours(value: number, locale: Locale): string {
  // Format hours with 2 decimal places and locale-appropriate separators
  const decimalSeparator = locale === 'no' ? ',' : '.';
  const thousandsSeparator = locale === 'no' ? '.' : ',';
  const [whole, decimal] = value.toFixed(2).split('.');
  const formattedWhole = whole.replace(/\B(?=(\d{3})+(?!\d))/g, thousandsSeparator);
  return `${formattedWhole}${decimalSeparator}${decimal}`;
}

function weekdayAbbrev(date: Date, t: Dictionary): string {
  return t.dateTime.daysExport[date.getDay()].substring(0, 3);
}

function weekdayAbbrevCsv(date: Date, t: Dictionary): string {
  return weekdayAbbrev(date, t).replace(/ø/gi, (match) => (match === 'ø' ? 'o' : 'O'));
}

function calculateShift(shift: RawShift): ShiftCalculation {
  return shift.calc;
}

async function ensureJsPdf(): Promise<JsPDFConstructor | null> {
  if (typeof window === 'undefined') {
    return null;
  }

  if (window.jspdf?.jsPDF) {
    return window.jspdf.jsPDF;
  }

  const existingScript = document.querySelector<HTMLScriptElement>('script[data-jspdf-cdn]');

  if (!existingScript) {
    try {
      await new Promise<void>((resolve, reject) => {
        const script = document.createElement('script');
        script.src = JSPDF_CDN;
        script.async = true;
        script.dataset.jspdfCdn = 'true';
        script.onload = () => resolve();
        script.onerror = () => reject(new Error('Failed to load jsPDF'));
        document.head.appendChild(script);
      });
    } catch (error) {
      console.error('[pdf export] Failed to append jsPDF script:', error);
    }
  } else if (!window.jspdf?.jsPDF) {
    await new Promise<void>((resolve) => {
      const handleDone = () => resolve();
      existingScript.addEventListener('load', handleDone, { once: true });
      existingScript.addEventListener('error', handleDone, { once: true });
    });
  }

  if (window.jspdf?.jsPDF) {
    return window.jspdf.jsPDF;
  }

  alert('Kunne ikke laste jsPDF. Oppdater siden og prøv igjen.');
  return null;
}

async function loadLogoAsBase64(): Promise<string | null> {
  try {
    // Use PNG icon (better transparency support in jsPDF than WEBP)
    const response = await fetch('/icon-192x192.png');
    const blob = await response.blob();
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

async function fetchExportData(range: DateRange): Promise<ExportPayload | null> {
  try {
    const searchParams = new URLSearchParams({
      from: range.from,
      to: range.to,
    });
    const response = await fetch(`/api/settings/data/export?${searchParams.toString()}`, {
      method: 'GET',
      cache: 'no-store',
    });

    if (!response.ok) {
      const body = await response.json().catch(() => null);
      const message =
        (body as { error?: string } | null)?.error ??
        'Kunne ikke hente data for eksport.';
      alert(message);
      return null;
    }

    return (await response.json()) as ExportPayload;
  } catch (error) {
    console.error('[pdf export] Failed to fetch export data:', error);
    alert('Kunne ikke hente data for eksport. Sjekk tilkoblingen og prøv igjen.');
    return null;
  }
}

function prepareExportData(payload: ExportPayload): PreparedExportData {
  const preparedShifts: PreparedShift[] = (payload.shifts ?? [])
    .map((shift) => {
      const dateObj = new Date(`${shift.date}T00:00:00`);
      return {
        ...shift,
        dateObj,
        calc: calculateShift(shift),
      };
    })
    .sort((a, b) => a.dateObj.getTime() - b.dateObj.getTime());

  let totalHours = 0;
  let totalBaseWage = 0;
  let totalSupplement = 0;
  let totalWages = 0;

  const counts = {
    weekday: 0,
    saturday: 0,
    sunday: 0,
  };

  for (const shift of preparedShifts) {
    totalHours += shift.calc.hours;
    totalBaseWage += shift.calc.baseWage;
    totalSupplement += shift.calc.supplement;
    totalWages += shift.calc.total;

    if (shift.type === 1) {
      counts.saturday += 1;
    } else if (shift.type === 2) {
      counts.sunday += 1;
    } else {
      counts.weekday += 1;
    }
  }

  return {
    shifts: preparedShifts,
    totals: {
      totalHours,
      totalBaseWage,
      totalSupplement,
      totalWages,
    },
    countsByType: counts,
    firstDate: preparedShifts[0]?.dateObj ?? null,
    lastDate: preparedShifts.at(-1)?.dateObj ?? null,
  };
}

function formatLongDate(date: Date | null, locale: Locale): string {
  if (!date) return '';
  return getDateFormatter(locale, {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  }).format(date);
}

function buildFileName(range: DateRange | null, ext: 'pdf' | 'csv', locale: Locale, userName?: string) {
  const prefix = locale === 'no' ? 'tidex-rapport' : 'tidex-report';

  // Format name as "firstname-L" (first name + first letter of last name)
  let namePart = '';
  if (userName) {
    const parts = userName.trim().split(/\s+/);
    const firstName = parts[0].toLowerCase();
    const lastInitial = parts.length > 1 ? parts[parts.length - 1][0].toLowerCase() : '';
    namePart = lastInitial ? `_${firstName}-${lastInitial}` : `_${firstName}`;
  }

  if (range) {
    // Check if range covers exactly one full month
    const fromDate = new Date(range.from);
    const toDate = new Date(range.to);

    const isFirstOfMonth = fromDate.getDate() === 1;
    const isSameMonth = fromDate.getFullYear() === toDate.getFullYear() &&
                        fromDate.getMonth() === toDate.getMonth();

    // Check if toDate is the last day of the month
    const lastDayOfMonth = new Date(toDate.getFullYear(), toDate.getMonth() + 1, 0).getDate();
    const isLastOfMonth = toDate.getDate() === lastDayOfMonth;

    if (isFirstOfMonth && isSameMonth && isLastOfMonth) {
      // Full month - use month name and year
      const monthFormatter = getDateFormatter(locale, { month: 'long' });
      const monthName = monthFormatter.format(fromDate).toLowerCase();
      const year = fromDate.getFullYear();
      return `${prefix}${namePart}_${monthName}-${year}.${ext}`;
    }

    return `${prefix}${namePart}_${range.from}_${range.to}.${ext}`;
  }
  const stamp = new Date().toISOString().slice(0, 10);
  return `${prefix}${namePart}_${stamp}.${ext}`;
}

function renderSummary(doc: JsPDFInstance, yRef: { value: number }, data: PreparedExportData, locale: Locale) {
  const { margins } = PAGE_CONFIG;
  const ensureSpace = (required: number) => {
    if (yRef.value + required > margins.bottom) {
      doc.addPage();
      yRef.value = margins.top;
    }
  };

  ensureSpace(60);

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(14);
  doc.text(locale === 'no' ? 'Sammendrag' : 'Summary', margins.left, yRef.value);
  yRef.value += 10;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(10);

  const hoursLabel = locale === 'no' ? 'timer' : 'hours';
  const currencyLabel = locale === 'no' ? 'kr' : 'NOK';

  const summaryRows: Array<{ label: string; value: string }> = locale === 'no' ? [
    { label: 'Totalt antall vakter:', value: String(data.shifts.length) },
    { label: 'Totale timer:', value: `${formatHours(data.totals.totalHours, locale)} ${hoursLabel}` },
    {
      label: 'Total grunnlønn:',
      value: `${formatCurrencyShort(data.totals.totalBaseWage, locale)} ${currencyLabel}`,
    },
    {
      label: 'Totale tillegg:',
      value: `${formatCurrencyShort(data.totals.totalSupplement, locale)} ${currencyLabel}`,
    },
    {
      label: 'Total lønn:',
      value: `${formatCurrencyShort(data.totals.totalWages, locale)} ${currencyLabel}`,
    },
    { label: '', value: '' },
    { label: 'Vakter per type:', value: '' },
    { label: ' Ukedager:', value: String(data.countsByType.weekday) },
    { label: ' Lørdager:', value: String(data.countsByType.saturday) },
    { label: ' Søndager/helligdager:', value: String(data.countsByType.sunday) },
  ] : [
    { label: 'Total number of shifts:', value: String(data.shifts.length) },
    { label: 'Total hours:', value: `${formatHours(data.totals.totalHours, locale)} ${hoursLabel}` },
    {
      label: 'Total base wage:',
      value: `${formatCurrencyShort(data.totals.totalBaseWage, locale)} ${currencyLabel}`,
    },
    {
      label: 'Total supplements:',
      value: `${formatCurrencyShort(data.totals.totalSupplement, locale)} ${currencyLabel}`,
    },
    {
      label: 'Total earnings:',
      value: `${formatCurrencyShort(data.totals.totalWages, locale)} ${currencyLabel}`,
    },
    { label: '', value: '' },
    { label: 'Shifts by type:', value: '' },
    { label: ' Weekdays:', value: String(data.countsByType.weekday) },
    { label: ' Saturdays:', value: String(data.countsByType.saturday) },
    { label: ' Sundays/holidays:', value: String(data.countsByType.sunday) },
  ];

  for (const row of summaryRows) {
    if (!row.label && !row.value) {
      yRef.value += 5;
      continue;
    }

    doc.text(row.label, 20, yRef.value);
    doc.text(row.value, 80, yRef.value);
    yRef.value += 5;
  }

  yRef.value += 10;
}

/**
 * Get the ISO week number for a date
 */
function getISOWeekNumber(date: Date): number {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil((((d.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
}

/**
 * Draw a dashed line (for week separators)
 */
function drawDashedLine(
  doc: JsPDFInstance,
  x1: number,
  y: number,
  x2: number,
  dashLength = 2,
  gapLength = 2
) {
  doc.setLineWidth(0.3);
  let x = x1;
  while (x < x2) {
    const endX = Math.min(x + dashLength, x2);
    doc.line(x, y, endX, y);
    x = endX + gapLength;
  }
}

// Columns that should be right-aligned (numeric columns)
const RIGHT_ALIGNED_COLUMNS = new Set([4, 5, 6, 7]); // Timer, Grunnlønn, Tillegg, Totalt

function renderTable(
  doc: JsPDFInstance,
  yRef: { value: number },
  data: PreparedExportData,
  t: Dictionary,
  locale: Locale
) {
  const { margins } = PAGE_CONFIG;
  const columnPositions: number[] = [];
  let cursor = margins.left;
  for (const width of TABLE_HEADER.widths) {
    columnPositions.push(cursor);
    cursor += width;
  }

  // Calculate right edge positions for right-aligned columns
  const columnRightEdges: number[] = [];
  let rightCursor = margins.left;
  for (const width of TABLE_HEADER.widths) {
    rightCursor += width;
    columnRightEdges.push(rightCursor);
  }

  const renderHeader = () => {
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(8);
    for (let i = 0; i < TABLE_HEADER.columns.length; i += 1) {
      if (RIGHT_ALIGNED_COLUMNS.has(i)) {
        doc.text(TABLE_HEADER.columns[i], columnRightEdges[i], yRef.value, { align: 'right' });
      } else {
        doc.text(TABLE_HEADER.columns[i], columnPositions[i], yRef.value);
      }
    }
    yRef.value += 5;

    doc.setLineWidth(0.5);
    doc.line(margins.left, yRef.value, margins.right, yRef.value);
    yRef.value += 5;
  };

  const ensureSpace = (required: number, includeHeader = false) => {
    if (yRef.value + required > margins.bottom) {
      doc.addPage();
      yRef.value = margins.top;
      if (includeHeader) {
        renderHeader();
      }
    }
  };

  if (data.shifts.length === 0) {
    ensureSpace(30);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(14);
    doc.text('Detaljert vaktliste', margins.left, yRef.value);
    yRef.value += 10;

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.text('Ingen vakter tilgjengelig for eksport.', margins.left, yRef.value);
    yRef.value += 5;
    return;
  }

  ensureSpace(50);

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(14);
  doc.text('Detaljert vaktliste', margins.left, yRef.value);
  yRef.value += 10;

  renderHeader();

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);

  // Track previous shift's month and week for separator logic
  let prevMonth: number | null = null;
  let prevWeek: number | null = null;
  let prevYear: number | null = null;

  for (const shift of data.shifts) {
    const currentMonth = shift.dateObj.getMonth();
    const currentYear = shift.dateObj.getFullYear();
    const currentWeek = getISOWeekNumber(shift.dateObj);

    // Check if we need to draw a separator line before this shift
    const isNewMonth = prevMonth !== null && (currentMonth !== prevMonth || currentYear !== prevYear);
    const isNewWeek = prevWeek !== null && !isNewMonth && (currentWeek !== prevWeek || currentYear !== prevYear);

    if (isNewMonth) {
      // Solid line for month separator - symmetric spacing above and below
      ensureSpace(13, true);
      const lineY = yRef.value;
      doc.setLineWidth(0.5);
      doc.line(margins.left, lineY, margins.right, lineY);
      yRef.value += 5;
    } else if (isNewWeek) {
      // Dashed line for week separator with week number label
      ensureSpace(13, true);
      const lineY = yRef.value;
      // Draw week number label (localized)
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(7);
      const weekWord = t.dateTime.week ?? 'Uke';
      const weekLabel = `${weekWord} ${currentWeek}`;
      doc.text(weekLabel, margins.left, lineY + 0.5);
      // Draw dashed line after the label (indented to make room for "Uke ##")
      const lineStartX = margins.left + 10;
      drawDashedLine(doc, lineStartX, lineY, margins.right);
      // Reset font for row content
      doc.setFontSize(8);
      yRef.value += 5;
    } else {
      ensureSpace(8, true);
    }

    const dateLocale = locale === 'no' ? 'no-NO' : 'en-GB';
    const rowValues = [
      shift.dateObj.toLocaleDateString(dateLocale),
      weekdayAbbrev(shift.dateObj, t),
      shift.startTime,
      shift.endTime,
      formatHours(shift.calc.hours, locale),
      formatCurrencyShort(shift.calc.baseWage, locale),
      formatCurrencyShort(shift.calc.supplement, locale),
      formatCurrencyShort(shift.calc.total, locale),
    ];

    for (let i = 0; i < rowValues.length; i += 1) {
      if (RIGHT_ALIGNED_COLUMNS.has(i)) {
        doc.text(rowValues[i], columnRightEdges[i], yRef.value, { align: 'right' });
      } else {
        doc.text(rowValues[i], columnPositions[i], yRef.value);
      }
    }

    yRef.value += 5;

    // Update tracking variables
    prevMonth = currentMonth;
    prevWeek = currentWeek;
    prevYear = currentYear;
  }

  yRef.value += 5;
  doc.setLineWidth(0.5);
  doc.line(margins.left, yRef.value, margins.right, yRef.value);
  yRef.value += 5;

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8);
  doc.text('Sum:', columnPositions[0], yRef.value);
  doc.text(formatHours(data.totals.totalHours, locale), columnRightEdges[4], yRef.value, { align: 'right' });
  doc.text(
    formatCurrencyShort(data.totals.totalBaseWage, locale),
    columnRightEdges[5],
    yRef.value,
    { align: 'right' }
  );
  doc.text(
    formatCurrencyShort(data.totals.totalSupplement, locale),
    columnRightEdges[6],
    yRef.value,
    { align: 'right' }
  );
  doc.text(
    formatCurrencyShort(data.totals.totalWages, locale),
    columnRightEdges[7],
    yRef.value,
    { align: 'right' }
  );

  yRef.value += 5;
}

function applyFooters(doc: JsPDFInstance) {
  const totalPages = doc.getNumberOfPages();

  for (let page = 1; page <= totalPages; page += 1) {
    doc.setPage(page);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);

    doc.text('Generert av Tidex', PAGE_CONFIG.margins.left, PAGE_CONFIG.footerY);
    doc.text(
      `Side ${page} av ${totalPages}`,
      PAGE_CONFIG.margins.right - 20,
      PAGE_CONFIG.footerY,
      { align: 'right' }
    );
  }
}

function escapeCsvValue(value: string): string {
  const stringValue = String(value ?? '');
  if (/[;"\n]/.test(stringValue)) {
    return `"${stringValue.replace(/"/g, '""')}"`;
  }
  return stringValue;
}

function buildCsvContent(data: PreparedExportData, t: Dictionary): string {
  const header = ['Dato', 'Dag', 'Start', 'Slutt', 'Timer', 'Grunnlonn', 'Tillegg', 'Totalt'];
  const rows = data.shifts.map((shift) => [
    shift.dateObj.toLocaleDateString('no-NO'),
    weekdayAbbrevCsv(shift.dateObj, t),
    shift.startTime,
    shift.endTime,
    shift.calc.hours.toFixed(2),
    shift.calc.baseWage.toFixed(2),
    shift.calc.supplement.toFixed(2),
    shift.calc.total.toFixed(2),
  ]);

  const totalsRow = [
    'Sum',
    '',
    '',
    '',
    data.totals.totalHours.toFixed(2),
    data.totals.totalBaseWage.toFixed(2),
    data.totals.totalSupplement.toFixed(2),
    data.totals.totalWages.toFixed(2),
  ];

  return [header, ...rows, totalsRow]
    .map((row) => row.map((cell) => escapeCsvValue(cell)).join(';'))
    .join('\n');
}

function downloadCsv(data: PreparedExportData, range: DateRange, t: Dictionary, locale: Locale, userName?: string) {
  const csvContent = buildCsvContent(data, t);
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = buildFileName(range, 'csv', locale, userName);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

interface DataFormProps {
  t: Dictionary;
  userName: string;
}

export function DataForm({ t, userName }: DataFormProps) {
  const { locale } = useTranslations();
  const [selectedPreset, setSelectedPreset] = useState<PeriodPreset | null>(null);
  const [customRange, setCustomRange] = useState<DateRange>({ from: '', to: '' });
  const [isExportingPdf, setIsExportingPdf] = useState(false);
  const [isExportingCsv, setIsExportingCsv] = useState(false);

  const resolvedRange = useMemo(() => {
    if (!selectedPreset) {
      return null;
    }

    if (selectedPreset === 'custom') {
      if (!customRange.from || !customRange.to) {
        return null;
      }

      if (customRange.from > customRange.to) {
        return null;
      }

      return customRange;
    }

    return PERIOD_CONFIG[selectedPreset].resolve();
  }, [customRange, selectedPreset]);

  const customRangeInvalid =
    selectedPreset === 'custom' &&
    Boolean(customRange.from && customRange.to && customRange.from > customRange.to);

  const selectedRangeLabel = useMemo(() => {
    if (!resolvedRange) {
      return '';
    }

    const fromDate = parseIsoDate(resolvedRange.from);
    const toDate = parseIsoDate(resolvedRange.to);

    if (!fromDate || !toDate) {
      return '';
    }

    return `${formatLongDate(fromDate, locale)} - ${formatLongDate(toDate, locale)}`;
  }, [resolvedRange, locale]);

  const canExport = Boolean(resolvedRange);

  const handleExport = async (format: 'pdf' | 'csv') => {
    const range = resolvedRange;
    if (!range) {
      return;
    }

    if (format === 'pdf') {
      setIsExportingPdf(true);
      try {
        const jsPdfCtor = await ensureJsPdf();
        if (!jsPdfCtor) {
          return;
        }

        const payload = await fetchExportData(range);
        if (!payload) {
          return;
        }

        const exportData = prepareExportData(payload);
        const doc = new jsPdfCtor({
          orientation: PAGE_CONFIG.orientation,
          unit: PAGE_CONFIG.unit,
          format: PAGE_CONFIG.format,
        });

        // Get localized title
        const documentTitle = DOCUMENT_TITLE[locale as keyof typeof DOCUMENT_TITLE] ?? DOCUMENT_TITLE.no;
        doc.setProperties({ ...DOCUMENT_PROPERTIES, title: `Tidex · ${documentTitle}` });

        const yRef: { value: number } = { value: PAGE_CONFIG.margins.top };
        const headerStartY = yRef.value;

        // Add title: "Tidex" (bold) + " · Vakt- og lønnsrapport" (normal)
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(16);
        doc.text('Tidex', PAGE_CONFIG.margins.left, yRef.value);
        // Get width of "Tidex" to position the rest
        const tidexWidth = doc.getTextWidth('Tidex');
        doc.setFont('helvetica', 'normal');
        doc.text(` · ${documentTitle}`, PAGE_CONFIG.margins.left + tidexWidth, yRef.value);
        yRef.value += 6;

        doc.setFont('helvetica', 'normal');
        doc.setFontSize(10);

        const exportDate = payload.generatedAt ? new Date(payload.generatedAt) : new Date();
        const exportedLabel = locale === 'no' ? 'Eksportert' : 'Exported';
        doc.text(
          `${exportedLabel}: ${formatLongDate(exportDate, locale)}`,
          PAGE_CONFIG.margins.left,
          yRef.value
        );
        yRef.value += 5;

        const fromDate = parseIsoDate(range.from);
        const toDate = parseIsoDate(range.to);
        const periodLabel = locale === 'no' ? 'Periode' : 'Period';
        if (fromDate && toDate) {
          doc.text(
            `${periodLabel}: ${formatLongDate(fromDate, locale)} - ${formatLongDate(toDate, locale)}`,
            PAGE_CONFIG.margins.left,
            yRef.value
          );
        } else if (exportData.shifts.length > 0) {
          doc.text(
            `${periodLabel}: ${formatLongDate(exportData.firstDate, locale)} - ${formatLongDate(
              exportData.lastDate,
              locale
            )}`,
            PAGE_CONFIG.margins.left,
            yRef.value
          );
        }
        yRef.value += 5;

        // Add user name
        if (userName) {
          const nameLabel = locale === 'no' ? 'Navn' : 'Name';
          doc.text(`${nameLabel}: ${userName}`, PAGE_CONFIG.margins.left, yRef.value);
        }

        // Add logo in top right corner, spanning from title to user name
        const logoBase64 = await loadLogoAsBase64();
        const headerEndY = yRef.value;
        const logoSize = headerEndY - headerStartY + 5;
        if (logoBase64) {
          doc.addImage(logoBase64, 'PNG', PAGE_CONFIG.margins.right - logoSize, headerStartY - 5, logoSize, logoSize);
        }

        yRef.value += 10;

        renderSummary(doc, yRef, exportData, locale);
        renderTable(doc, yRef, exportData, t, locale);
        applyFooters(doc);

        doc.save(buildFileName(range, 'pdf', locale, userName));
      } catch (error) {
        console.error('[pdf export] Failed to generate pdf:', error);
        alert('Noe gikk galt under eksporten. Prøv igjen senere.');
      } finally {
        setIsExportingPdf(false);
      }

      return;
    }

    setIsExportingCsv(true);
    try {
      const payload = await fetchExportData(range);
      if (!payload) {
        return;
      }

      const exportData = prepareExportData(payload);
      downloadCsv(exportData, range, t, locale, userName);
    } catch (error) {
      console.error('[csv export] Failed to generate csv:', error);
      alert('Noe gikk galt under eksporten. Prøv igjen senere.');
    } finally {
      setIsExportingCsv(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="space-y-6">
        <div className="text-center">
          <h3 className="text-lg font-semibold text-text-muted">{t.pages.settings.data.export.title}</h3>
          <p className="mt-1 text-sm text-text-secondary">
            {t.pages.settings.data.export.description}
          </p>
        </div>

        <Separator />

        <div className="space-y-4">
          <div>
            <p className="font-medium text-text-muted">{t.pages.settings.data.export.periodLabel}</p>
            <p className="text-sm text-text-secondary">
              {t.pages.settings.data.export.periodDescription}
            </p>
          </div>

          <div className="flex gap-2">
            {PRESET_ORDER.map((key) => {
              const isSelected = selectedPreset === key;
              return (
                <Button
                  key={key}
                  type="button"
                  variant={isSelected ? 'default' : 'secondary'}
                  className={cn(
                    'flex-1 min-w-0 text-sm',
                    !isSelected && 'bg-muted text-text-secondary hover:bg-muted'
                  )}
                  onClick={() => setSelectedPreset(key)}
                >
                  {getPresetLabel(key, locale)}
                </Button>
              );
            })}
          </div>

          <div className="flex items-center gap-4">
            <div
              className="h-px flex-1"
              style={{
                backgroundImage:
                  'repeating-linear-gradient(to right, hsl(var(--border)) 0, hsl(var(--border)) 8px, transparent 8px, transparent 16px)',
              }}
            />
            <span className="text-xs uppercase tracking-wide text-text-secondary">
              {t.common.or}
            </span>
            <div
              className="h-px flex-1"
              style={{
                backgroundImage:
                  'repeating-linear-gradient(to right, hsl(var(--border)) 0, hsl(var(--border)) 8px, transparent 8px, transparent 16px)',
              }}
            />
          </div>

          <button
            type="button"
            className={cn(
              'w-full text-left rounded-md border p-3 transition-colors sm:p-4',
              selectedPreset === 'custom'
                ? 'border-primary bg-primary/5'
                : 'border-border bg-muted text-text-secondary hover:bg-muted'
            )}
            onClick={() => setSelectedPreset('custom')}
          >
            <div className="flex flex-col gap-2">
              <div className="flex flex-wrap items-center gap-2 sm:gap-3">
                <p className="font-medium text-text-muted">{t.pages.settings.data.export.customPeriod}</p>
                <div className="flex flex-wrap items-center gap-2 sm:flex-nowrap">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold uppercase tracking-wide text-text-secondary">
                      {t.pages.settings.data.export.fromLabel}
                    </span>
                    <Input
                      type="date"
                      value={customRange.from}
                      max={customRange.to || undefined}
                      onChange={(event) => {
                        const value = event.target.value;
                        setSelectedPreset('custom');
                        setCustomRange((previous) => ({
                          ...previous,
                          from: value,
                        }));
                      }}
                      onFocus={() => setSelectedPreset('custom')}
                      className="w-32 sm:w-36"
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold uppercase tracking-wide text-text-secondary">
                      {t.pages.settings.data.export.toLabel}
                    </span>
                    <Input
                      type="date"
                      value={customRange.to}
                      min={customRange.from || undefined}
                      onChange={(event) => {
                        const value = event.target.value;
                        setSelectedPreset('custom');
                        setCustomRange((previous) => ({
                          ...previous,
                          to: value,
                        }));
                      }}
                      onFocus={() => setSelectedPreset('custom')}
                      className="w-32 sm:w-36"
                    />
                  </div>
                </div>
              </div>
              {customRangeInvalid && (
                <p className="text-xs text-destructive">
                  {t.pages.settings.data.export.dateRangeError}
                </p>
              )}
            </div>
          </button>

          {selectedRangeLabel && (
            <p className="text-sm text-text-secondary">
              {t.pages.settings.data.export.selectedPeriod} {selectedRangeLabel}
            </p>
          )}
        </div>

        <Separator />

        <div className="space-y-6">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="font-medium text-text-muted">{t.pages.settings.data.export.pdf.title}</p>
              <p className="text-sm text-text-secondary">
                {t.pages.settings.data.export.pdf.description}
              </p>
            </div>
            <Button
              className={cn(
                'bg-[#FF0000] text-white hover:bg-[#e50000]',
                (!canExport || isExportingPdf) && 'hover:bg-[#FF0000]'
              )}
              onClick={() => handleExport('pdf')}
              disabled={!canExport || isExportingPdf}
            >
              <Download className="mr-2 h-4 w-4" />
              {isExportingPdf ? t.pages.settings.data.export.pdf.exporting : t.pages.settings.data.export.pdf.button}
            </Button>
          </div>

          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="font-medium text-text-muted">{t.pages.settings.data.export.csv.title}</p>
              <p className="text-sm text-text-secondary">
                {t.pages.settings.data.export.csv.description}
              </p>
            </div>
            <Button
              onClick={() => handleExport('csv')}
              disabled={!canExport || isExportingCsv}
            >
              <Download className="mr-2 h-4 w-4" />
              {isExportingCsv ? t.pages.settings.data.export.csv.exporting : t.pages.settings.data.export.csv.button}
            </Button>
          </div>
        </div>
      </div>

      <Separator className="mt-6" />

      <div className="space-y-2">
        <h3 className="font-semibold text-text-muted">{t.pages.settings.data.export.about.title}</h3>
        <p className="text-sm text-text-secondary">
          {t.pages.settings.data.export.about.description}
        </p>
      </div>
    </div>
  );
}
