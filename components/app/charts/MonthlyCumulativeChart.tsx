"use client";

import { Line, LineChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { DailyCumulativeData } from "@/app/(app)/stats/_data/getStatsData";

type MonthlyCumulativeChartProps = {
  data: DailyCumulativeData[];
};

const chartConfig = {
  currentMonth: {
    label: "Denne måneden",
    color: "hsl(var(--brand-highlight))",
  },
  lastMonth: {
    label: "Forrige måned",
    color: "hsl(var(--text-muted))",
  },
};

// Custom tick component to color today's day number
function CustomXAxisTick({
  x,
  y,
  payload,
  data
}: {
  x: number;
  y: number;
  payload: any;
  data: DailyCumulativeData[];
}) {
  const dayData = data.find(d => d.day === payload.value);
  const isToday = dayData?.isToday;

  return (
    <g transform={`translate(${x},${y})`}>
      <text
        x={0}
        y={0}
        dy={8}
        textAnchor="middle"
        fontSize={16}
        fill={isToday ? "hsl(var(--brand-highlight))" : "hsl(var(--foreground))"}
        fontWeight={isToday ? 600 : 400}
      >
        {payload.value}
      </text>
    </g>
  );
}

export function MonthlyCumulativeChart({ data }: MonthlyCumulativeChartProps) {
  // To make the projected line continue from the actual line without a separate animation start,
  // we need to include the last actual data point in the projected data
  const todayIndex = data.findIndex((d) => d.isToday);

  const chartData = data.map((item, index) => ({
    ...item,
    // Actual line: show up to and including today
    currentMonthActual: item.isFuture ? null : item.currentMonth,
    // Projected line: show from today onwards (includes today to connect the lines)
    currentMonthProjected: index >= todayIndex ? item.currentMonth : null,
  }));

  // Generate custom ticks for every 5 days
  const xAxisTicks = data
    .filter((_, index) => index === 0 || (index + 1) % 5 === 0 || index === data.length - 1)
    .map((d) => d.day);

  return (
    <ChartContainer config={chartConfig} className="h-[260px] w-full">
      <LineChart data={chartData} margin={{ top: 12, right: 20, bottom: 16, left: 16 }}>
        <CartesianGrid
          strokeDasharray="3 3"
          className="stroke-muted"
          verticalCoordinatesGenerator={({ xAxis }) => {
            if (!xAxis?.ticks) {
              return [];
            }

            const allowedTicks = new Set(xAxisTicks);

            return xAxis.ticks
              .filter((tick: { value: string | number }) => allowedTicks.has(String(tick.value)))
              .map((tick: { coordinate?: number }) => tick.coordinate)
              .filter((coord: unknown): coord is number => typeof coord === "number");
          }}
        />
        <XAxis
          dataKey="day"
          tickLine={false}
          axisLine={false}
          padding={{ left: 8, right: 8 }}
          tick={(props) => <CustomXAxisTick {...props} data={data} />}
          tickMargin={8}
          ticks={xAxisTicks}
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
              labelFormatter={(label) => {
                return <span className="text-lg font-semibold">Dag {label}</span>;
              }}
              formatter={(value, name, props) => {
                const data = props.payload as DailyCumulativeData & {
                  currentMonthActual: number | null;
                  currentMonthProjected: number | null;
                };

                // Only show once - prefer actual over projected to avoid duplicates at today's date
                if (name === "currentMonthProjected" && data.currentMonthActual !== null) {
                  return null;
                }

                const isCurrent = name === "currentMonthActual" || name === "currentMonthProjected";

                if (isCurrent) {
                  const amount = Math.round(data.currentMonth).toLocaleString('nb-NO');
                  return (
                    <div className="flex flex-col gap-1">
                      <div className="flex items-center gap-2">
                        <span className="font-mono font-semibold text-base tabular-nums">{amount} kr</span>
                        <span className="text-muted-foreground text-base">
                          {data.isFuture ? "(prognose)" : "denne mnd"}
                        </span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-sm tabular-nums text-muted-foreground">
                          {Math.round(data.lastMonth).toLocaleString('nb-NO')} kr
                        </span>
                        <span className="text-muted-foreground text-sm">forrige mnd</span>
                      </div>
                    </div>
                  );
                }
                return null;
              }}
            />
          }
        />

        {/* Last month reference line (thinner, dashed) */}
        <Line
          type="monotone"
          dataKey="lastMonth"
          stroke="hsl(var(--text-muted))"
          strokeWidth={1.5}
          strokeDasharray="5 5"
          dot={false}
          opacity={0.6}
        />

        {/* Current month actual (solid, thicker) */}
        <Line
          type="monotone"
          dataKey="currentMonthActual"
          stroke="hsl(var(--brand-highlight))"
          strokeWidth={3}
          dot={false}
          connectNulls={false}
        />

        {/* Current month projected (dashed, thicker) */}
        <Line
          type="monotone"
          dataKey="currentMonthProjected"
          stroke="hsl(var(--brand-highlight))"
          strokeWidth={3}
          strokeDasharray="8 4"
          dot={false}
          connectNulls={true}
        />
      </LineChart>
    </ChartContainer>
  );
}
