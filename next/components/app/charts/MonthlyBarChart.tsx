"use client";

import React from "react";
import { Bar, BarChart, CartesianGrid, XAxis, YAxis, Cell } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { MonthlyData } from "@/data-access/stats";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";
import { useIsMobile } from "@/lib/hooks/useIsMobile";

type MonthlyBarChartProps = {
  data: MonthlyData[];
};

const chartConfig = {
  earnings: {
    label: "inntjening",
    color: "hsl(var(--brand-gradientMid))",
  },
};

// Filter out leading and trailing zero months
function trimZeroMonths(data: MonthlyData[]): MonthlyData[] {
  const firstNonZeroIndex = data.findIndex(d => d.earnings > 0);
  if (firstNonZeroIndex === -1) return data; // All zeros, return as-is

  const lastNonZeroIndex = data.findLastIndex(d => d.earnings > 0);
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
  data: MonthlyData[];
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

  return (
    <g transform={`translate(${x},${y})`}>
      <text
        x={0}
        y={0}
        dy={8}
        textAnchor="middle"
        fontSize={12}
        fill={isCurrentMonth ? "hsl(var(--brand-gradientMid))" : "hsl(var(--foreground))"}
        fontWeight={isCurrentMonth ? 600 : 400}
      >
        {payload.value}
      </text>
    </g>
  );
}

export function MonthlyBarChart({ data }: MonthlyBarChartProps) {
  const formatCurrency = useFormatCurrency();
  const isMobile = useIsMobile();
  const now = new Date();
  const currentMonth = now.getMonth() + 1; // Date#getMonth is 0-based
  const currentYear = now.getFullYear();

  // Filter out leading/trailing zero months
  const filteredData = trimZeroMonths(data);

  return (
    <ChartContainer config={chartConfig} className="h-65 w-full">
      <BarChart data={filteredData} margin={{ top: 12, right: 8, bottom: 0, left: 8 }}>
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
          tickFormatter={(value) => {
            if (value === 0) return '0';
            return `${(value / 1000).toFixed(0)}k`;
          }}
        />
        <ChartTooltip
          content={
            <ChartTooltipContent
              className="min-w-50 p-4"
              labelFormatter={(label, payload): React.ReactNode => {
                if (payload && payload.length > 0) {
                  const data = (payload[0] as { payload: MonthlyData }).payload;
                  return <span className="text-lg font-semibold">{data.fullMonth}</span>;
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
          radius={[6, 6, 0, 0]}
        >
          {filteredData.map((entry) => {
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
  );
}
