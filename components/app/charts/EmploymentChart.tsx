"use client";

import { Bar, BarChart, CartesianGrid, XAxis, YAxis, Cell } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { ClickTooltip } from "@/components/app/Tooltip";
import { Info } from "lucide-react";
import type { EmploymentMonthlyData } from "@/data-access/stats";
import { useTranslations } from "@/lib/i18n/client";

type EmploymentChartProps = {
  data: EmploymentMonthlyData[];
  yearlyAverage: number | null;
  focusYear: number;
};

const chartConfig = {
  employment: {
    label: "stilling",
    color: "hsl(var(--brand-gradientMid))",
  },
};

// Custom tick component to color current month's label
function CustomXAxisTick({
  x,
  y,
  payload,
  data,
  currentMonth,
  currentYear,
  focusYear,
}: {
  x: number;
  y: number;
  payload: { value: string };
  data: EmploymentMonthlyData[];
  currentMonth: number;
  currentYear: number;
  focusYear: number;
}) {
  const monthData = data.find(d => d.month === payload.value);
  const isCurrentMonth = monthData?.monthNumber === currentMonth && monthData?.year === currentYear;
  const isPreviousYear = monthData?.year !== focusYear;

  // Grey out labels from previous years
  const fill = isPreviousYear
    ? "hsl(var(--muted-foreground))"
    : isCurrentMonth
      ? "hsl(var(--brand-gradientMid))"
      : "hsl(var(--foreground))";

  return (
    <g transform={`translate(${x},${y})`}>
      <text
        x={0}
        y={0}
        dy={8}
        textAnchor="middle"
        fontSize={16}
        fill={fill}
        fontWeight={isCurrentMonth ? 600 : 400}
      >
        {payload.value}
      </text>
    </g>
  );
}

export function EmploymentChart({ data, yearlyAverage, focusYear }: EmploymentChartProps) {
  const { t } = useTranslations();
  const now = new Date();
  const currentMonth = now.getMonth() + 1; // Date#getMonth is 0-based
  const currentYear = now.getFullYear();

  // Select a 6-month window from the data, shifting forward to avoid leading zeros.
  // The backend provides 11 months (6 before + 5 after focus month).
  // We want to show 6 consecutive months, preferring to start from the first non-zero month.
  // Only show fewer than 6 months if both ends of the possible window have zeros.
  const filteredData = (() => {
    const TARGET_MONTHS = 6;

    // Find first non-zero index
    const firstNonZeroIndex = data.findIndex(d => d.averagePercentage > 0);

    // If all zeros, show first 6 months
    if (firstNonZeroIndex === -1) {
      return data.slice(0, TARGET_MONTHS);
    }

    // Calculate the ideal start index to show 6 months starting from first non-zero
    // But we need to ensure we don't go past the end of the data
    const idealStart = firstNonZeroIndex;
    const maxStart = data.length - TARGET_MONTHS;

    // Clamp the start index
    const startIndex = Math.min(idealStart, Math.max(0, maxStart));
    const endIndex = startIndex + TARGET_MONTHS;

    // Extract the 6-month window
    let window = data.slice(startIndex, endIndex);

    // If the window still has leading zeros AND trailing zeros, trim to just the data range
    const windowFirstNonZero = window.findIndex(d => d.averagePercentage > 0);
    const windowLastNonZero = window.findLastIndex(d => d.averagePercentage > 0);

    if (windowFirstNonZero > 0 && windowLastNonZero < window.length - 1) {
      // Both ends have zeros - show only the months with data
      window = window.slice(windowFirstNonZero, windowLastNonZero + 1);
    }

    return window;
  })();

  return (
    <div className="flex flex-col">
      {/* Elevated header with yearly average */}
      <div className="bg-surface-secondary rounded-t-lg px-4 py-3 border-b border-border">
        <div className="flex items-center justify-between">
          <p className="flex items-baseline gap-2">
            <span className="text-2xl font-bold tabular-nums text-text-primary">
              {yearlyAverage !== null ? `${yearlyAverage}%` : "---"}
            </span>
            <span className="text-sm font-medium text-text-muted">
              {t.components.charts.employment.yearlyAverage}
            </span>
          </p>
          <ClickTooltip
            trigger={<Info className="h-4 w-4" />}
            triggerClassName="p-1 rounded-full text-text-muted hover:text-text-secondary hover:bg-surface-primary transition-colors"
            ariaLabel={t.components.charts.employment.averageInfoLabel}
            className="max-w-[200px]"
          >
            <p>{t.components.charts.employment.averageInfo}</p>
          </ClickTooltip>
        </div>
      </div>

      {/* Bar chart */}
      <ChartContainer config={chartConfig} className="h-[260px] w-full pt-4">
        <BarChart data={filteredData} margin={{ top: 12, right: 16, bottom: 16, left: 16 }}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-muted" vertical={false} />
          <XAxis
            dataKey="month"
            tickLine={false}
            axisLine={false}
            padding={{ left: 8, right: 8 }}
            tick={(props) => (
              <CustomXAxisTick
                {...props}
                data={filteredData}
                currentMonth={currentMonth}
                currentYear={currentYear}
                focusYear={focusYear}
              />
            )}
            tickMargin={8}
          />
          <YAxis
            tickLine={false}
            axisLine={false}
            width={44}
            tick={{ fontSize: 16 }}
            tickMargin={8}
            tickFormatter={(value) => `${value}%`}
            domain={[0, 'auto']}
          />
          <ChartTooltip
            content={
              <ChartTooltipContent
                className="min-w-[200px] p-4"
                labelFormatter={(label, payload) => {
                  if (payload && payload.length > 0) {
                    const chartData = payload[0].payload as EmploymentMonthlyData;
                    return <span className="text-lg font-semibold">{chartData.fullMonth}</span>;
                  }
                  return label;
                }}
                formatter={(value) => {
                  const percentage = value as number;
                  return (
                    <div className="flex items-center gap-2">
                      <span className="font-mono font-semibold text-base tabular-nums">{percentage.toFixed(1)}%</span>
                      <span className="text-muted-foreground text-base">{t.components.charts.employment.employment}</span>
                    </div>
                  );
                }}
              />
            }
          />
          <Bar
            dataKey="averagePercentage"
            radius={[8, 8, 0, 0]}
            minPointSize={0}
          >
            {filteredData.map((entry) => {
              const isCurrentMonth =
                entry.monthNumber === currentMonth && entry.year === currentYear;
              const isPreviousYear = entry.year !== focusYear;

              // Determine fill color: grey for previous year, brand color for current year
              let fill: string;
              let stroke: string;
              if (isPreviousYear) {
                // Grey for months from a different year than the focus year
                fill = "hsl(var(--muted-foreground) / 0.3)";
                stroke = "hsl(var(--muted-foreground) / 0.5)";
              } else if (isCurrentMonth) {
                // Solid brand color for the actual current month
                fill = "hsl(var(--brand-gradientMid))";
                stroke = "hsl(var(--brand-gradientMid))";
              } else {
                // Dimmed brand color for other months in the focus year
                fill = "hsl(var(--brand-gradientMid) / 0.2)";
                stroke = "hsl(var(--brand-gradientMid))";
              }

              return (
                <Cell
                  key={`${entry.year}-${entry.monthNumber}`}
                  fill={fill}
                  stroke={stroke}
                  strokeWidth={2}
                />
              );
            })}
          </Bar>
        </BarChart>
      </ChartContainer>
    </div>
  );
}
