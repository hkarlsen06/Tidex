"use client";

import React from "react";
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
import { useIsMobile } from "@/lib/hooks/useIsMobile";

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

// Filter out leading and trailing zero months
function trimZeroMonths(data: EmploymentMonthlyData[]): EmploymentMonthlyData[] {
  const firstNonZeroIndex = data.findIndex(d => d.averagePercentage > 0);
  if (firstNonZeroIndex === -1) return data; // All zeros, return as-is

  const lastNonZeroIndex = data.findLastIndex(d => d.averagePercentage > 0);
  return data.slice(firstNonZeroIndex, lastNonZeroIndex + 1);
}

// Custom tick component to color current month's label
function CustomXAxisTick({
  x,
  y,
  payload,
  data,
  currentMonth,
  currentYear,
  index,
  isMobile,
}: {
  x: number;
  y: number;
  payload: { value: string };
  data: EmploymentMonthlyData[];
  currentMonth: number;
  currentYear: number;
  index: number;
  isMobile: boolean | undefined;
}) {
  const monthData = data.find(d => d.month === payload.value);
  const isCurrentMonth = monthData?.monthNumber === currentMonth && monthData?.year === currentYear;

  // On mobile, show first label and then every other month
  const shouldShow = !isMobile || index === 0 || index % 2 === 0;

  if (!shouldShow) return null;

  const fill = isCurrentMonth
    ? "hsl(var(--brand-gradientMid))"
    : "hsl(var(--foreground))";

  return (
    <g transform={`translate(${x},${y})`}>
      <text
        x={0}
        y={0}
        dy={8}
        textAnchor="middle"
        fontSize={12}
        fill={fill}
        fontWeight={isCurrentMonth ? 600 : 400}
      >
        {payload.value}
      </text>
    </g>
  );
}

export function EmploymentChart({ data, yearlyAverage, focusYear: _focusYear }: EmploymentChartProps) {
  const { t } = useTranslations();
  const isMobile = useIsMobile();
  const now = new Date();
  const currentMonth = now.getMonth() + 1; // Date#getMonth is 0-based
  const currentYear = now.getFullYear();

  // Filter out leading/trailing zero months
  const filteredData = trimZeroMonths(data);

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
            className="max-w-50"
          >
            <p>{t.components.charts.employment.averageInfo}</p>
          </ClickTooltip>
        </div>
      </div>

      {/* Bar chart */}
      <ChartContainer config={chartConfig} className="h-65 w-full pt-4">
        <BarChart data={filteredData} margin={{ top: 12, right: 8, bottom: 0, left: 16 }}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-muted" vertical={false} />
          <XAxis
            dataKey="month"
            tickLine={false}
            axisLine={false}
            padding={{ left: 4, right: 4 }}
            tick={(props) => (
              <CustomXAxisTick
                {...props}
                data={filteredData}
                currentMonth={currentMonth}
                currentYear={currentYear}
                isMobile={isMobile}
              />
            )}
            tickMargin={8}
            interval={0}
          />
          <YAxis
            tickLine={false}
            axisLine={false}
            width={40}
            tick={{ fontSize: 14 }}
            tickMargin={4}
            tickFormatter={(value) => `${value}%`}
            domain={[0, 'auto']}
          />
          <ChartTooltip
            content={
              <ChartTooltipContent
                className="min-w-50 p-4"
                labelFormatter={(label, payload): React.ReactNode => {
                  if (payload && payload.length > 0) {
                    const chartData = (payload[0] as { payload: EmploymentMonthlyData }).payload;
                    return <span className="text-lg font-semibold">{chartData.fullMonth}</span>;
                  }
                  return label as React.ReactNode;
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
            radius={[6, 6, 0, 0]}
            minPointSize={0}
          >
            {filteredData.map((entry) => {
              const isCurrentMonth =
                entry.monthNumber === currentMonth && entry.year === currentYear;

              // Determine fill color: solid brand for current month, dimmed for others
              const fill = isCurrentMonth
                ? "hsl(var(--brand-gradientMid))"
                : "hsl(var(--brand-gradientMid) / 0.2)";
              const stroke = "hsl(var(--brand-gradientMid))";

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
