"use client";

import React from "react";
import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { YearlyCumulativeData } from "@/data-access/stats";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";

type YearlyCumulativeChartProps = {
  data: YearlyCumulativeData[];
};

const chartConfig = {
  cumulative: {
    label: "Kumulativ inntjening",
    color: "hsl(var(--brand-highlight))",
  },
  projected: {
    label: "Projeksjon",
    color: "hsl(var(--text-muted))",
  },
};

// Custom tick component to color current month's label
function CustomXAxisTick({
  x,
  y,
  payload,
  data,
  currentMonth
}: {
  x: number;
  y: number;
  payload: any;
  data: YearlyCumulativeData[];
  currentMonth: number;
}) {
  const monthData = data.find(d => d.month === payload.value);
  const isCurrentMonth = monthData?.monthNumber === currentMonth;

  return (
    <g transform={`translate(${x},${y})`}>
      <text
        x={0}
        y={0}
        dy={8}
        textAnchor="middle"
        fontSize={12}
        fill={isCurrentMonth ? "hsl(var(--brand-highlight))" : "hsl(var(--foreground))"}
        fontWeight={isCurrentMonth ? 600 : 400}
      >
        {payload.value}
      </text>
    </g>
  );
}

export function YearlyCumulativeChart({ data }: YearlyCumulativeChartProps) {
  const formatCurrency = useFormatCurrency();
  // Create chart data with separate values for actual and projected
  const chartData = data.map((item, index) => {
    // For the transition point, include value in both actual and projected
    const isPreviousActual = index > 0 && !data[index - 1].isProjected;
    const isTransitionPoint = item.isProjected && isPreviousActual;

    return {
      ...item,
      actual: !item.isProjected ? item.cumulative : (isTransitionPoint ? item.cumulative : null),
      projected: item.isProjected ? item.cumulative : (isTransitionPoint ? item.cumulative : null),
    };
  });

  // Get current month to highlight
  const now = new Date();
  const currentMonth = now.getMonth() + 1;

  return (
    <ChartContainer config={chartConfig} className="h-65 w-full">
      <AreaChart data={chartData} margin={{ top: 12, right: 20, bottom: 0, left: 16 }}>
        <defs>
          <linearGradient id="fillActual" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="hsl(var(--brand-highlight))" stopOpacity={0.3} />
            <stop offset="95%" stopColor="hsl(var(--brand-highlight))" stopOpacity={0} />
          </linearGradient>
          <linearGradient id="fillProjected" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="hsl(var(--text-muted))" stopOpacity={0.15} />
            <stop offset="95%" stopColor="hsl(var(--text-muted))" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" className="stroke-muted" vertical={false} />
        <XAxis
          dataKey="month"
          tickLine={false}
          axisLine={false}
          interval={1}
          padding={{ left: 8, right: 8 }}
          tick={(props) => <CustomXAxisTick {...props} data={data} currentMonth={currentMonth} />}
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
              className="min-w-50 p-4"
              labelFormatter={(label, payload): React.ReactNode => {
                if (payload && payload.length > 0) {
                  const data = (payload[0] as { payload: YearlyCumulativeData }).payload;
                  return (
                    <div className="flex items-center gap-2">
                      <span className="text-lg font-semibold">{data.fullMonth}</span>
                      {data.isProjected && (
                        <span className="text-xs text-muted-foreground">(projisert)</span>
                      )}
                    </div>
                  );
                }
                return label as React.ReactNode;
              }}
              formatter={(value, name) => {
                const amount = formatCurrency(value as number);
                const label = name === "projected" ? "Projisert totalt" : "Totalt";
                return (
                  <div className="flex items-center gap-2">
                    <span className="font-mono font-semibold text-base tabular-nums">{amount}</span>
                    <span className="text-muted-foreground text-base">{label}</span>
                  </div>
                );
              }}
            />
          }
        />
        {/* Actual data area */}
        <Area
          type="monotone"
          dataKey="actual"
          stroke="hsl(var(--brand-highlight))"
          fill="url(#fillActual)"
          strokeWidth={2}
          connectNulls={false}
        />
        {/* Projected data area */}
        <Area
          type="monotone"
          dataKey="projected"
          stroke="hsl(var(--text-muted))"
          fill="url(#fillProjected)"
          strokeWidth={2}
          strokeDasharray="5 5"
          connectNulls={false}
        />
      </AreaChart>
    </ChartContainer>
  );
}
