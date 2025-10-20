'use client';

import { useMemo, useState } from 'react';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Separator } from '@appui/Separator';
import { Download } from 'lucide-react';
import { cn } from '@/lib/cn';

const JSPDF_CDN = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';

const WEEKDAY_NAMES = [
  'søndag',
  'mandag',
  'tirsdag',
  'onsdag',
  'torsdag',
  'fredag',
  'lørdag',
];

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
  title: 'Vaktrapport',
  subject: 'Lønn og vaktdetaljer',
  author: 'Vaktkalkulator',
  creator: 'Vaktkalkulator',
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

const MONTH_FORMATTER = new Intl.DateTimeFormat('no-NO', { month: 'long' });

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
  seriesId: string | null;
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

function getPresetLabel(preset: Exclude<PeriodPreset, 'custom'>): string {
  const now = new Date();
  if (preset === 'current_year') {
    return String(now.getFullYear());
  }

  const baseMonth =
    preset === 'current_month'
      ? new Date(now.getFullYear(), now.getMonth(), 1)
      : new Date(now.getFullYear(), now.getMonth() - 1, 1);

  return capitalize(MONTH_FORMATTER.format(baseMonth));
}

function formatCurrencyShort(value: number): string {
  return Math.round(value).toLocaleString('nb-NO');
}

function weekdayAbbrev(date: Date): string {
  return WEEKDAY_NAMES[date.getDay()].substring(0, 3);
}

function weekdayAbbrevCsv(date: Date): string {
  return weekdayAbbrev(date).replace(/ø/gi, (match) => (match === 'ø' ? 'o' : 'O'));
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

function formatLongDate(date: Date | null): string {
  if (!date) return '';
  return new Intl.DateTimeFormat('no-NO', {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  }).format(date);
}

function buildFileName(range: DateRange | null, ext: 'pdf' | 'csv', at: Date = new Date()) {
  if (range) {
    return `vaktrapport_${range.from}_${range.to}.${ext}`;
  }
  const stamp = at.toISOString().slice(0, 10);
  return `vaktrapport_${stamp}.${ext}`;
}

function renderSummary(doc: JsPDFInstance, yRef: { value: number }, data: PreparedExportData) {
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
  doc.text('Sammendrag', margins.left, yRef.value);
  yRef.value += 10;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(10);

  const summaryRows: Array<{ label: string; value: string }> = [
    { label: 'Totalt antall vakter:', value: String(data.shifts.length) },
    { label: 'Totale timer:', value: `${data.totals.totalHours.toFixed(2)} timer` },
    {
      label: 'Total grunnlønn:',
      value: `${formatCurrencyShort(data.totals.totalBaseWage)} kr`,
    },
    {
      label: 'Totale tillegg:',
      value: `${formatCurrencyShort(data.totals.totalSupplement)} kr`,
    },
    {
      label: 'Total lønn:',
      value: `${formatCurrencyShort(data.totals.totalWages)} kr`,
    },
    { label: '', value: '' },
    { label: 'Vakter per type:', value: '' },
    { label: ' Ukedager:', value: String(data.countsByType.weekday) },
    { label: ' Lørdager:', value: String(data.countsByType.saturday) },
    { label: ' Søndager/helligdager:', value: String(data.countsByType.sunday) },
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

function renderTable(
  doc: JsPDFInstance,
  yRef: { value: number },
  data: PreparedExportData
) {
  const { margins } = PAGE_CONFIG;
  const columnPositions: number[] = [];
  let cursor = margins.left;
  for (const width of TABLE_HEADER.widths) {
    columnPositions.push(cursor);
    cursor += width;
  }

  const renderHeader = () => {
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(8);
    for (let i = 0; i < TABLE_HEADER.columns.length; i += 1) {
      doc.text(TABLE_HEADER.columns[i], columnPositions[i], yRef.value);
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

  for (const shift of data.shifts) {
    ensureSpace(8, true);

    const rowValues = [
      shift.dateObj.toLocaleDateString('no-NO'),
      weekdayAbbrev(shift.dateObj),
      shift.startTime,
      shift.endTime,
      shift.calc.hours.toFixed(2),
      formatCurrencyShort(shift.calc.baseWage),
      formatCurrencyShort(shift.calc.supplement),
      formatCurrencyShort(shift.calc.total),
    ];

    for (let i = 0; i < rowValues.length; i += 1) {
      doc.text(rowValues[i], columnPositions[i], yRef.value);
    }

    yRef.value += 5;
  }

  yRef.value += 5;
  doc.setLineWidth(0.5);
  doc.line(margins.left, yRef.value, margins.right, yRef.value);
  yRef.value += 5;

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8);
  doc.text('Sum:', columnPositions[0], yRef.value);
  doc.text(data.totals.totalHours.toFixed(2), columnPositions[4], yRef.value);
  doc.text(
    formatCurrencyShort(data.totals.totalBaseWage),
    columnPositions[5],
    yRef.value
  );
  doc.text(
    formatCurrencyShort(data.totals.totalSupplement),
    columnPositions[6],
    yRef.value
  );
  doc.text(
    formatCurrencyShort(data.totals.totalWages),
    columnPositions[7],
    yRef.value
  );

  yRef.value += 5;
}

function applyFooters(doc: JsPDFInstance) {
  const totalPages = doc.getNumberOfPages();

  for (let page = 1; page <= totalPages; page += 1) {
    doc.setPage(page);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);

    doc.text('Generert av Vaktkalkulator', PAGE_CONFIG.margins.left, PAGE_CONFIG.footerY);
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

function buildCsvContent(data: PreparedExportData): string {
  const header = ['Dato', 'Dag', 'Start', 'Slutt', 'Timer', 'Grunnlonn', 'Tillegg', 'Totalt'];
  const rows = data.shifts.map((shift) => [
    shift.dateObj.toLocaleDateString('no-NO'),
    weekdayAbbrevCsv(shift.dateObj),
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

function downloadCsv(data: PreparedExportData, range: DateRange) {
  const csvContent = buildCsvContent(data);
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = buildFileName(range, 'csv');
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

export function DataForm() {
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

    return `${formatLongDate(fromDate)} - ${formatLongDate(toDate)}`;
  }, [resolvedRange]);

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

        doc.setProperties(DOCUMENT_PROPERTIES);

        const yRef: { value: number } = { value: PAGE_CONFIG.margins.top };

        doc.setFont('helvetica', 'bold');
        doc.setFontSize(20);
        doc.text(DOCUMENT_PROPERTIES.title, PAGE_CONFIG.margins.left, yRef.value);
        yRef.value = 35;

        doc.setFont('helvetica', 'normal');
        doc.setFontSize(10);

        const exportDate = payload.generatedAt ? new Date(payload.generatedAt) : new Date();
        doc.text(
          `Eksportert: ${formatLongDate(exportDate)}`,
          PAGE_CONFIG.margins.left,
          yRef.value
        );
        yRef.value = 45;

        const fromDate = parseIsoDate(range.from);
        const toDate = parseIsoDate(range.to);
        if (fromDate && toDate) {
          doc.text(
            `Periode: ${formatLongDate(fromDate)} - ${formatLongDate(toDate)}`,
            PAGE_CONFIG.margins.left,
            yRef.value
          );
        } else if (exportData.shifts.length > 0) {
          doc.text(
            `Periode: ${formatLongDate(exportData.firstDate)} - ${formatLongDate(
              exportData.lastDate
            )}`,
            PAGE_CONFIG.margins.left,
            yRef.value
          );
        }

        yRef.value = 60;

        renderSummary(doc, yRef, exportData);
        renderTable(doc, yRef, exportData);
        applyFooters(doc);

        doc.save(buildFileName(range, 'pdf', exportDate));
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
      downloadCsv(exportData, range);
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
          <h3 className="text-lg font-semibold text-text-muted">Eksporter data</h3>
          <p className="mt-1 text-sm text-text-secondary">
            Velg tidsperiode og last ned vakter som PDF eller CSV.
          </p>
        </div>

        <Separator />

        <div className="space-y-4">
          <div>
            <p className="font-medium text-text-muted">Velg tidsperiode</p>
            <p className="text-sm text-text-secondary">
              Velg en tidsperiode for eksporten.
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
                  {getPresetLabel(key)}
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
              eller
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
                <p className="font-medium text-text-muted">Egendefinert periode</p>
                <div className="flex flex-wrap items-center gap-2 sm:flex-nowrap">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold uppercase tracking-wide text-text-secondary">
                      Fra
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
                      Til
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
                  Fradato kan ikke være etter tildato.
                </p>
              )}
            </div>
          </button>

          {selectedRangeLabel && (
            <p className="text-sm text-text-secondary">
              Valgt periode: {selectedRangeLabel}
            </p>
          )}
        </div>

        <Separator />

        <div className="space-y-6">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="font-medium text-text-muted">Eksporter til PDF</p>
              <p className="text-sm text-text-secondary">
                Inkluderer vaktoversikt, summer per type og totale lønnstall.
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
              {isExportingPdf ? 'Eksporterer…' : 'Last ned PDF'}
            </Button>
          </div>

          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="font-medium text-text-muted">Eksporter til CSV</p>
              <p className="text-sm text-text-secondary">
                Vaktinfo per vakt i kronologisk rekkefølge. Inkluderer sum på slutten.
              </p>
            </div>
            <Button
              onClick={() => handleExport('csv')}
              disabled={!canExport || isExportingCsv}
            >
              <Download className="mr-2 h-4 w-4" />
              {isExportingCsv ? 'Eksporterer…' : 'Last ned CSV'}
            </Button>
          </div>
        </div>
      </div>

      <Separator className="mt-6" />

      <div className="space-y-2">
        <h3 className="font-semibold text-text-muted">Om rapporten</h3>
        <p className="text-sm text-text-secondary">
          PDF-rapporten er optimalisert for A4-portrettformat og inkluderer automatisk sidetall og
          genereringstidspunkt. Lagre den for intern dokumentasjon eller del den ved
          behov.
        </p>
      </div>
    </div>
  );
}
