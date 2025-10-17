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
          width={44}
          tick={{ fontSize: 16 }}
          tickMargin={8}
          tickFormatter={(value) => {
            if (value === 0) return '0';
            if (value >= 1000) return `${(value / 1000).toFixed(0)}k`;
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
