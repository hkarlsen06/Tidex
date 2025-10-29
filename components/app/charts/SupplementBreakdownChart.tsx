"use client";

import { Pie, PieChart, Cell } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { SupplementBreakdown } from "@/data-access/stats";
import { useTranslations } from "@/lib/i18n/client";
import { formatCurrency } from "@/lib/formatters";

type SupplementBreakdownChartProps = {
  data: SupplementBreakdown;
};

export function SupplementBreakdownChart({ data }: SupplementBreakdownChartProps) {
  const { t } = useTranslations();

  const chartConfig = {
    basePay: {
      label: t.components.charts.supplementBreakdown.basePay,
      color: "hsl(var(--brand-gradientStart))",
    },
    supplementPay: {
      label: t.components.charts.supplementBreakdown.supplements,
      color: "hsl(var(--brand-gradientEnd))",
    },
  };

  // Handle case where there are no earnings
  if (data.basePay === 0 && data.supplementPay === 0) {
    return (
      <div className="flex items-center justify-center h-[280px] text-text-muted">
        <p className="text-center">
          {t.components.charts.supplementBreakdown.noData}
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
            {formatCurrency(data.basePay)}
          </p>
          <p className="text-base text-text-muted">
            {t.components.charts.supplementBreakdown.percentBasePay}
          </p>
        </div>
        <p className="text-sm text-text-secondary max-w-[280px] text-center">
          {t.components.charts.supplementBreakdown.noSupplements}
        </p>
      </div>
    );
  }

  const chartData = [
    {
      name: "basePay",
      value: data.basePay,
      percentage: data.basePercentage,
      label: t.components.charts.supplementBreakdown.basePay,
    },
    {
      name: "supplementPay",
      value: data.supplementPay,
      percentage: data.supplementPercentage,
      label: t.components.charts.supplementBreakdown.supplements,
    },
  ];

  const totalEarnings = data.basePay + data.supplementPay;

  return (
    <div className="flex items-center gap-4 sm:gap-6 w-full h-[180px] sm:h-[200px]">
      {/* Left cell: Total and legend - centered, takes remaining space */}
      <div className="flex-1 flex items-center justify-center">
        <div className="flex flex-col gap-2.5 sm:gap-3">
          {/* Total earnings */}
          <div>
            <p className="text-xl sm:text-2xl font-bold text-text-primary tabular-nums">
              {formatCurrency(totalEarnings)}
            </p>
          </div>

          {/* Legend items */}
          <div className="flex flex-col gap-1.5 sm:gap-2">
            {chartData.map((item, index) => (
              <div key={`legend-${index}`} className="flex items-center gap-2">
                <div
                  className="w-2.5 h-2.5 sm:w-3 sm:h-3 rounded-full flex-shrink-0"
                  style={{
                    backgroundColor: item.name === "basePay"
                      ? chartConfig.basePay.color
                      : chartConfig.supplementPay.color
                  }}
                />
                <span className="text-xs sm:text-sm text-text-secondary whitespace-nowrap">
                  {item.label} ({item.percentage.toFixed(1)}%)
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Right cell: Pie chart - takes full height, width determined by aspect ratio */}
      <div className="flex items-center justify-center h-full">
        <div className="relative h-full aspect-square">
          <ChartContainer config={chartConfig} className="h-full w-full">
          <PieChart>
          <ChartTooltip
            content={
              <ChartTooltipContent
                className="min-w-[200px] p-4"
                hideLabel
                formatter={(value, _name, item) => {
                  const amount = formatCurrency(value as number);
                  const percentage = (item.payload.percentage as number).toFixed(1);
                  const label = item.payload.label as string;
                  return (
                    <div className="flex flex-col gap-1">
                      <span className="text-lg font-semibold">{label}</span>
                      <div className="flex items-baseline gap-2">
                        <span className="font-mono font-semibold text-base tabular-nums">
                          {amount}
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
            cy="50%"
            innerRadius="35%"
            outerRadius="55%"
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
        </PieChart>
      </ChartContainer>
        </div>
      </div>
    </div>
  );
}
