"use client";

import { Bar, BarChart, CartesianGrid, XAxis, YAxis, Cell } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { DayOfWeekData } from "@/app/(app)/stats/_data/getStatsData";

type DayOfWeekChartProps = {
  data: DayOfWeekData[];
};

const chartConfig = {
  averageEarnings: {
    label: "Gjennomsnitt",
    color: "hsl(var(--brand-gradientEnd))",
  },
};

export function DayOfWeekChart({ data }: DayOfWeekChartProps) {
  // Calculate domain for y-axis to focus on the range where data varies
  const earnings = data.map((d) => d.averageEarnings);
  const maxEarnings = Math.max(...earnings);
  const minEarnings = Math.min(...earnings.filter((e) => e > 0)); // Exclude zero values

  // Add padding to the range (20% below min, 10% above max)
  const range = maxEarnings - minEarnings;
  const yMin = Math.max(0, minEarnings - range * 0.2);
  const yMax = maxEarnings + range * 0.1;

  // Calculate nice tick interval
  const roughInterval = (yMax - yMin) / 5; // Aim for ~5 ticks
  const magnitude = Math.pow(10, Math.floor(Math.log10(roughInterval)));
  const normalized = roughInterval / magnitude;
  let niceInterval;
  if (normalized <= 1) niceInterval = magnitude;
  else if (normalized <= 2) niceInterval = 2 * magnitude;
  else if (normalized <= 5) niceInterval = 5 * magnitude;
  else niceInterval = 10 * magnitude;

  // Round domain to nice values
  const nicerMin = Math.floor(yMin / niceInterval) * niceInterval;
  const nicerMax = Math.ceil(yMax / niceInterval) * niceInterval;

  // Generate tick values
  const ticks = [];
  for (let tick = nicerMin; tick <= nicerMax; tick += niceInterval) {
    ticks.push(tick);
  }

  return (
    <ChartContainer config={chartConfig} className="h-[220px] w-full">
      <BarChart data={data} margin={{ top: 12, right: 16, bottom: 16, left: 16 }}>
        <CartesianGrid strokeDasharray="3 3" className="stroke-muted" vertical={false} />
        <XAxis
          dataKey="day"
          tickLine={false}
          axisLine={false}
          padding={{ left: 8, right: 8 }}
          tick={{ fontSize: 16 }}
          tickMargin={8}
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          width={52}
          tick={{ fontSize: 16 }}
          tickMargin={8}
          domain={[nicerMin, nicerMax]}
          ticks={ticks}
          tickFormatter={(value) => {
            if (value === 0) return '0';
            if (value >= 1000) return `${(value / 1000).toFixed(1)}k`;
            return Math.round(value).toString();
          }}
        />
        <ChartTooltip
          content={
            <ChartTooltipContent
              className="min-w-[220px] p-4"
              labelFormatter={(label, payload) => {
                if (payload && payload.length > 0) {
                  const data = payload[0].payload as DayOfWeekData;
                  return <span className="text-lg font-semibold">{data.fullDay}</span>;
                }
                return label;
              }}
              formatter={(value, name) => {
                const amount = Math.round(value as number).toLocaleString('nb-NO');
                return (
                  <div className="flex items-center gap-2">
                    <span className="font-mono font-semibold text-base tabular-nums">{amount} kr</span>
                    <span className="text-muted-foreground text-base">gjennomsnitt per vakt</span>
                  </div>
                );
              }}
            />
          }
        />
        <Bar
          dataKey="averageEarnings"
          fill="hsl(var(--brand-gradientEnd) / 0.2)"
          stroke="hsl(var(--brand-gradientEnd))"
          strokeWidth={2}
          radius={[8, 8, 0, 0]}
        />
      </BarChart>
    </ChartContainer>
  );
}
