"use client";

import { useMemo } from "react";
import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { MonthlyData } from "@/data-access/stats";
import { formatCurrency } from "@/lib/formatters";

type CumulativeAreaChartProps = {
  data: MonthlyData[];
};

const chartConfig = {
  cumulative: {
    label: "Kumulativ inntjening",
    color: "hsl(var(--brand-highlight))",
  },
};

export function CumulativeAreaChart({ data }: CumulativeAreaChartProps) {
  // Calculate cumulative earnings using reduce without mutation
  const cumulativeData = useMemo(() => {
    const result: Array<MonthlyData & { cumulative: number }> = [];
    data.reduce((cumulative, item) => {
      const newCumulative = cumulative + item.earnings;
      result.push({ ...item, cumulative: newCumulative });
      return newCumulative;
    }, 0);
    return result;
  }, [data]);

  return (
    <ChartContainer config={chartConfig} className="h-[220px] w-full">
      <AreaChart data={cumulativeData} margin={{ top: 12, right: 20, bottom: 16, left: 16 }}>
        <defs>
          <linearGradient id="fillCumulative" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="hsl(var(--brand-highlight))" stopOpacity={0.3} />
            <stop offset="95%" stopColor="hsl(var(--brand-highlight))" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" className="stroke-muted" vertical={false} />
        <XAxis
          dataKey="month"
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
          tickFormatter={(value) => `${Math.round(value / 1000)}k`}
        />
        <ChartTooltip
          content={
            <ChartTooltipContent
              className="min-w-[200px] p-4"
              labelFormatter={(label, payload) => {
                if (payload && payload.length > 0) {
                  const data = payload[0].payload as MonthlyData;
                  return <span className="text-lg font-semibold">{data.fullMonth}</span>;
                }
                return label;
              }}
              formatter={(value, _name) => {
                const amount = formatCurrency(value as number);
                return (
                  <div className="flex items-center gap-2">
                    <span className="font-mono font-semibold text-base tabular-nums">{amount}</span>
                    <span className="text-muted-foreground text-base">totalt</span>
                  </div>
                );
              }}
            />
          }
        />
        <Area
          type="monotone"
          dataKey="cumulative"
          stroke="hsl(var(--brand-highlight))"
          fill="url(#fillCumulative)"
          strokeWidth={2}
        />
      </AreaChart>
    </ChartContainer>
  );
}
