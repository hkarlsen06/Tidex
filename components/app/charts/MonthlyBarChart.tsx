"use client";

import { Bar, BarChart, CartesianGrid, XAxis, YAxis, Cell } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { MonthlyData } from "@/app/(app)/stats/_data/getStatsData";

type MonthlyBarChartProps = {
  data: MonthlyData[];
};

const chartConfig = {
  earnings: {
    label: "inntjening",
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
  payload: any;
  data: MonthlyData[];
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

export function MonthlyBarChart({ data }: MonthlyBarChartProps) {
  const now = new Date();
  const currentMonth = now.getMonth() + 1; // Date#getMonth is 0-based
  const currentYear = now.getFullYear();

  return (
    <ChartContainer config={chartConfig} className="h-[260px] w-full">
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
          tickFormatter={(value) => {
            if (value === 0) return '0';
            return `${(value / 1000).toFixed(0)}k`;
          }}
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
  );
}
