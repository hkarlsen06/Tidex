"use client";

import { Bar, BarChart, CartesianGrid, XAxis, YAxis, Cell } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import type { EmploymentMonthlyData } from "@/data-access/stats";
import { useTranslations } from "@/lib/i18n/client";

type EmploymentChartProps = {
  data: EmploymentMonthlyData[];
  yearlyAverage: number | null;
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
  currentYear
}: {
  x: number;
  y: number;
  payload: { value: string };
  data: EmploymentMonthlyData[];
  currentMonth: number;
  currentYear: number;
}) {
  const monthData = data.find(d => d.month === payload.value);
  const isCurrentMonth = monthData?.monthNumber === currentMonth && monthData?.year === currentYear;

  return (
    <g transform={`translate(${x},${y})`}>
      <text
        x={0}
        y={0}
        dy={8}
        textAnchor="middle"
        fontSize={16}
        fill={isCurrentMonth ? "hsl(var(--brand-gradientMid))" : "hsl(var(--foreground))"}
        fontWeight={isCurrentMonth ? 600 : 400}
      >
        {payload.value}
      </text>
    </g>
  );
}

export function EmploymentChart({ data, yearlyAverage }: EmploymentChartProps) {
  const { t } = useTranslations();
  const now = new Date();
  const currentMonth = now.getMonth() + 1; // Date#getMonth is 0-based
  const currentYear = now.getFullYear();

  return (
    <div className="flex flex-col">
      {/* Elevated header with yearly average */}
      <div className="bg-surface-secondary rounded-t-lg px-4 py-3 border-b border-border">
        <p className="text-sm font-medium text-text-muted">
          {t.components.charts.employment.yearlyAverage}
        </p>
        <p className="text-2xl font-bold tabular-nums text-text-primary">
          {yearlyAverage !== null ? `${yearlyAverage}%` : "---"}
        </p>
      </div>

      {/* Bar chart */}
      <ChartContainer config={chartConfig} className="h-[260px] w-full pt-4">
        <BarChart data={data} margin={{ top: 12, right: 16, bottom: 16, left: 16 }}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-muted" vertical={false} />
          <XAxis
            dataKey="month"
            tickLine={false}
            axisLine={false}
            padding={{ left: 8, right: 8 }}
            tick={(props) => (
              <CustomXAxisTick
                {...props}
                data={data}
                currentMonth={currentMonth}
                currentYear={currentYear}
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
            stroke="hsl(var(--brand-gradientMid))"
            strokeWidth={2}
            radius={[8, 8, 0, 0]}
          >
            {data.map((entry) => {
              const isCurrentMonth =
                entry.monthNumber === currentMonth && entry.year === currentYear;

              return (
                <Cell
                  key={`${entry.year}-${entry.monthNumber}`}
                  fill={
                    isCurrentMonth
                      ? "hsl(var(--brand-gradientMid))"
                      : "hsl(var(--brand-gradientMid) / 0.2)"
                  }
                />
              );
            })}
          </Bar>
        </BarChart>
      </ChartContainer>
    </div>
  );
}
