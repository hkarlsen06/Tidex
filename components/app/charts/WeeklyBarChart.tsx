"use client";

import React from "react";
import { Bar, BarChart, CartesianGrid, XAxis, YAxis, Cell } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { DailyData } from "@/data-access/stats";
import { formatNumber } from "@/lib/formatters";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";

type WeeklyBarChartProps = {
  data: DailyData[];
  /** When true, highlights the day with highest earnings instead of today */
  highlightBestDay?: boolean;
  /** When true, shows dates (e.g., "15. nov") instead of day names (e.g., "Mon") on X-axis */
  showDatesInsteadOfDays?: boolean;
};

const chartConfig = {
  earnings: {
    label: "inntjening",
    color: "hsl(var(--brand-gradientMid))",
  },
};

const FALLBACK_DOMAIN: [number, number] = [0, 100];
const FALLBACK_TICKS = [0, 25, 50, 75, 100];

const niceNumber = (value: number) => {
  if (!Number.isFinite(value) || value <= 0) {
    return 1;
  }

  const exponent = Math.floor(Math.log10(value));
  const fraction = value / Math.pow(10, exponent);

  let niceFraction: number;
  if (fraction <= 1) niceFraction = 1;
  else if (fraction <= 2) niceFraction = 2;
  else if (fraction <= 2.5) niceFraction = 2.5;
  else if (fraction <= 5) niceFraction = 5;
  else niceFraction = 10;

  return niceFraction * Math.pow(10, exponent);
};

const buildNiceScale = (min: number, max: number, desiredTicks = 5) => {
  const span = max - min;

  if (!Number.isFinite(span) || span <= 0) {
    return { domain: FALLBACK_DOMAIN, ticks: FALLBACK_TICKS };
  }

  const tickInterval = niceNumber(span / Math.max(desiredTicks - 1, 1));
  const niceMin = Math.floor(min / tickInterval) * tickInterval;
  const niceMax = Math.ceil(max / tickInterval) * tickInterval;

  const ticks: number[] = [];
  for (let tick = niceMin; tick <= niceMax + tickInterval / 2; tick += tickInterval) {
    ticks.push(Number(tick.toFixed(6)));
  }

  return {
    domain: [niceMin, niceMax] as [number, number],
    ticks,
  };
};

const calculateYAxisScale = (earnings: number[]) => {
  if (earnings.length === 0) {
    return { domain: FALLBACK_DOMAIN, ticks: FALLBACK_TICKS };
  }

  const positiveEarnings = earnings.filter((value) => value > 0);
  const hasPositiveValues = positiveEarnings.length > 0;
  const maxEarnings = Math.max(...earnings);
  const minPositiveEarnings = hasPositiveValues ? Math.min(...positiveEarnings) : 0;

  if (!hasPositiveValues && maxEarnings === 0) {
    return { domain: FALLBACK_DOMAIN, ticks: FALLBACK_TICKS };
  }

  let lowerBound = hasPositiveValues ? minPositiveEarnings : 0;
  let upperBound = Math.max(maxEarnings, lowerBound);
  let span = upperBound - lowerBound;

  if (span <= 0) {
    const cushion = upperBound === 0 ? 100 : Math.abs(upperBound) * 0.25;
    lowerBound = Math.max(0, lowerBound - cushion);
    upperBound = upperBound + cushion;
    span = upperBound - lowerBound;
  } else {
    lowerBound = Math.max(0, lowerBound - span * 0.3);
    upperBound = upperBound + span * 0.15;
  }

  if (upperBound <= lowerBound) {
    upperBound = lowerBound + Math.max(span, 1);
  }

  return buildNiceScale(lowerBound, upperBound, 6);
};

const determineFractionDigits = (step: number, base: number, maxDigits = 3) => {
  if (!Number.isFinite(step) || step <= 0) {
    return 0;
  }

  const ratio = base / step;
  if (!Number.isFinite(ratio) || ratio <= 1) {
    return 0;
  }

  return Math.max(0, Math.min(maxDigits, Math.ceil(Math.log10(ratio))));
};

const createTickFormatter = (ticks: number[]) => {
  if (!ticks || ticks.length === 0) {
    return (value: number) => {
      if (value === 0) return "0";
      if (Math.abs(value) >= 1000) {
        return `${Math.round(value / 1000)}k`;
      }
      return Math.round(value).toString();
    };
  }

  const step = ticks.length > 1 ? Math.abs(ticks[1] - ticks[0]) : ticks[0] || 0;
  const thousandsDigits = determineFractionDigits(step, 1000);
  const standardDigits = determineFractionDigits(step, 1);

  return (value: number) => {
    if (value === 0) {
      return "0";
    }

    if (Math.abs(value) >= 1000) {
      return `${formatNumber(value / 1000, {
        minimumFractionDigits: thousandsDigits,
        maximumFractionDigits: thousandsDigits,
      })}k`;
    }

    return formatNumber(value, {
      minimumFractionDigits: standardDigits,
      maximumFractionDigits: standardDigits,
    });
  };
};

// Custom tick component to color highlighted day's label
function CustomXAxisTick({
  x,
  y,
  payload,
  data,
  highlightDate
}: {
  x: number;
  y: number;
  payload: any;
  data: DailyData[];
  highlightDate: string;
}) {
  const dayData = data.find(d => d.date === payload.value);
  // Only highlight if there's a specific date to highlight
  const isHighlighted = highlightDate && dayData?.fullDate === highlightDate;

  return (
    <g transform={`translate(${x},${y})`}>
      <text
        x={0}
        y={0}
        dy={8}
        textAnchor="middle"
        fontSize={16}
        fill={isHighlighted ? "hsl(var(--brand-gradientMid))" : "hsl(var(--foreground))"}
        fontWeight={isHighlighted ? 600 : 400}
      >
        {payload.value}
      </text>
    </g>
  );
}

// Format date as the day number with a dot (e.g., "15.")
const formatShortDate = (dateString: string): string => {
  const date = new Date(dateString + 'T00:00:00Z');
  return `${date.getUTCDate()}.`;
};

export function WeeklyBarChart({ data, highlightBestDay = false, showDatesInsteadOfDays = false }: WeeklyBarChartProps) {
  const formatCurrency = useFormatCurrency();

  // Transform data to show dates instead of day names if requested
  const chartData = showDatesInsteadOfDays
    ? data.map(d => ({
        ...d,
        date: formatShortDate(d.fullDate), // Replace day name with short date
      }))
    : data;

  // Calculate domain for y-axis to focus on the range where data varies
  const earnings = chartData.map((d) => d.earnings);
  const { domain, ticks } = calculateYAxisScale(earnings);
  const formatTick = createTickFormatter(ticks);

  // Determine which date to highlight
  // - Default: today's date (for "This week" view)
  // - highlightBestDay: no highlighting (for "Best week" view in past months)
  const highlightDate = highlightBestDay
    ? '' // No highlighting for past months
    : new Date().toISOString().split('T')[0];

  return (
    <ChartContainer config={chartConfig} className="h-65 w-full">
      <BarChart data={chartData} margin={{ top: 12, right: 16, bottom: 0, left: 16 }}>
        <CartesianGrid strokeDasharray="3 3" className="stroke-muted" vertical={false} />
        <XAxis
          dataKey="date"
          tickLine={false}
          axisLine={false}
          padding={{ left: 8, right: 8 }}
          tick={(props) => <CustomXAxisTick {...props} data={chartData} highlightDate={highlightDate} />}
          tickMargin={8}
          interval={0}
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          width={52}
          tick={{ fontSize: 16 }}
          tickMargin={8}
          allowDataOverflow
          type="number"
          domain={domain}
          ticks={ticks}
          tickFormatter={formatTick}
        />
        <ChartTooltip
          content={
            <ChartTooltipContent
              className="min-w-50 p-4"
              labelFormatter={(label, payload): React.ReactNode => {
                if (payload && payload.length > 0) {
                  const data = (payload[0] as { payload: DailyData }).payload;
                  return <span className="text-lg font-semibold">{data.fullDay}</span>;
                }
                return label as React.ReactNode;
              }}
              formatter={(value, _name) => {
                const amount = formatCurrency(value as number);
                return (
                  <div className="flex items-center gap-2">
                    <span className="font-mono font-semibold text-base tabular-nums">{amount}</span>
                    <span className="text-muted-foreground text-base">inntjening</span>
                  </div>
                );
              }}
            />
          }
        />
        <Bar
          dataKey="earnings"
          stroke="hsl(var(--brand-gradientMid))"
          strokeWidth={2}
          radius={[8, 8, 0, 0]}
        >
          {chartData.map((entry) => {
            // When no highlight date, show all bars at full color
            // When highlight date exists, only that day is full color
            const isHighlighted = !highlightDate || entry.fullDate === highlightDate;

            return (
              <Cell
                key={entry.fullDate}
                fill={
                  isHighlighted
                    ? "hsl(var(--brand-gradientMid))"
                    : "hsl(var(--brand-gradientMid) / 0.2)"
                }
              />
            );
          })}
        </Bar>
      </BarChart>
    </ChartContainer>
  );
}
