"use client";

import { Pie, PieChart, Cell, Legend } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { SupplementBreakdown } from "@/app/(app)/stats/_data/getStatsData";

type SupplementBreakdownChartProps = {
  data: SupplementBreakdown;
};

const chartConfig = {
  basePay: {
    label: "Grunnlønn",
    color: "hsl(var(--brand-gradientStart))",
  },
  supplementPay: {
    label: "Tillegg",
    color: "hsl(var(--brand-gradientEnd))",
  },
};

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

export function SupplementBreakdownChart({ data }: SupplementBreakdownChartProps) {
  // Handle case where there are no earnings
  if (data.basePay === 0 && data.supplementPay === 0) {
    return (
      <div className="flex items-center justify-center h-[280px] text-text-muted">
        <p className="text-center">
          Ingen lønnsdata for denne måneden
        </p>
      </div>
    );
  }

  // Handle case where there are no supplements
  if (data.supplementPay === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-[280px] gap-4">
        <div className="text-center">
          <p className="text-2xl font-bold text-text-primary mb-2">
            {numberFormatter.format(data.basePay)} kr
          </p>
          <p className="text-base text-text-muted">
            100% grunnlønn
          </p>
        </div>
        <p className="text-sm text-text-secondary max-w-[280px] text-center">
          Du har ikke tjent tillegg denne måneden. Tillegg opptjenes ved kvelds-, natt- og helgevakter.
        </p>
      </div>
    );
  }

  const chartData = [
    {
      name: "basePay",
      value: data.basePay,
      percentage: data.basePercentage,
      label: "Grunnlønn",
    },
    {
      name: "supplementPay",
      value: data.supplementPay,
      percentage: data.supplementPercentage,
      label: "Tillegg",
    },
  ];

  const totalEarnings = data.basePay + data.supplementPay;

  return (
    <div className="relative h-[280px] w-full">
      <ChartContainer config={chartConfig} className="h-full w-full">
        <PieChart>
          <ChartTooltip
            content={
              <ChartTooltipContent
                className="min-w-[200px] p-4"
                hideLabel
                formatter={(value, _name, item) => {
                  const amount = numberFormatter.format(value as number);
                  const percentage = (item.payload.percentage as number).toFixed(1);
                  const label = item.payload.label as string;
                  return (
                    <div className="flex flex-col gap-1">
                      <span className="text-lg font-semibold">{label}</span>
                      <div className="flex items-baseline gap-2">
                        <span className="font-mono font-semibold text-base tabular-nums">
                          {amount} kr
                        </span>
                        <span className="text-muted-foreground text-sm">
                          ({percentage}%)
                        </span>
                      </div>
                    </div>
                  );
                }}
              />
            }
          />
          <Pie
            data={chartData}
            dataKey="value"
            nameKey="name"
            cx="50%"
            cy="45%"
            innerRadius={70}
            outerRadius={105}
            paddingAngle={2}
            strokeWidth={0}
          >
            {chartData.map((entry, index) => (
              <Cell
                key={`cell-${index}`}
                fill={
                  entry.name === "basePay"
                    ? chartConfig.basePay.color
                    : chartConfig.supplementPay.color
                }
              />
            ))}
          </Pie>
          <Legend
            verticalAlign="bottom"
            height={36}
            content={({ payload }) => {
              if (!payload) return null;
              return (
                <div className="flex justify-center gap-6 mt-4">
                  {payload.map((entry, index) => {
                    const item = chartData[index];
                    return (
                      <div key={`legend-${index}`} className="flex items-center gap-2">
                        <div
                          className="w-3 h-3 rounded-full"
                          style={{ backgroundColor: entry.color }}
                        />
                        <span className="text-sm text-text-secondary">
                          {item.label} ({item.percentage.toFixed(1)}%)
                        </span>
                      </div>
                    );
                  })}
                </div>
              );
            }}
          />
        </PieChart>
      </ChartContainer>
      {/* Absolutely positioned text in the center */}
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none pb-12">
        <p className="text-2xl font-bold text-text-primary tabular-nums">
          {numberFormatter.format(totalEarnings)} kr
        </p>
      </div>
    </div>
  );
}
