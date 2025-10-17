"use client";

import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { DailyData } from "@/app/(app)/stats/_data/getStatsData";

type WeeklyBarChartProps = {
  data: DailyData[];
};

const chartConfig = {
  earnings: {
    label: "inntjening",
    color: "hsl(var(--brand-gradientMid))",
  },
};

export function WeeklyBarChart({ data }: WeeklyBarChartProps) {
  return (
    <ChartContainer config={chartConfig} className="h-[220px] w-full">
      <BarChart data={data} margin={{ top: 12, right: 16, bottom: 16, left: 16 }}>
        <CartesianGrid strokeDasharray="3 3" className="stroke-muted" vertical={false} />
        <XAxis
          dataKey="date"
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
              className="min-w-[200px] p-4"
              labelFormatter={(label, payload) => {
                if (payload && payload.length > 0) {
                  const data = payload[0].payload as DailyData;
                  return <span className="text-lg font-semibold">{data.fullDay}</span>;
                }
                return label;
              }}
              formatter={(value, name) => {
                const amount = Math.round(value as number).toLocaleString('nb-NO');
                return (
                  <div className="flex items-center gap-2">
                    <span className="font-mono font-semibold text-base tabular-nums">{amount} kr</span>
                    <span className="text-muted-foreground text-base">inntjening</span>
                  </div>
                );
              }}
            />
          }
        />
        <Bar
          dataKey="earnings"
          fill="hsl(var(--brand-gradientMid) / 0.2)"
          stroke="hsl(var(--brand-gradientMid))"
          strokeWidth={2}
          radius={[8, 8, 0, 0]}
        />
      </BarChart>
    </ChartContainer>
  );
}
