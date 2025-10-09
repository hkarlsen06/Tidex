"use client";

import { Card, CardContent } from "@/components/app/Card";
import { StatsData } from "@/app/(app)/stats/_data/getStatsData";

type StatsContentProps = {
  data: StatsData;
};

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

const compactFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
  notation: "compact",
});

const hourFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 1,
});

function formatCurrency(value: number, compact = false): string {
  if (compact && value >= 100000) {
    return compactFormatter.format(Math.round(value));
  }
  return numberFormatter.format(Math.round(value));
}

function formatHours(value: number): string {
  return hourFormatter.format(value);
}

type StatCardProps = {
  label: string;
  value: string;
  suffix?: string;
  highlight?: boolean;
  gradient?: boolean;
  subtitle?: string;
};

function StatCard({ label, value, suffix, highlight = false, gradient = false, subtitle }: StatCardProps) {
  return (
    <Card
      className={`
        border-border overflow-hidden transition-all duration-300 hover:scale-[1.02]
        ${gradient ? "bg-gradient-to-br from-brand-gradientStart to-brand-gradientEnd text-white border-none" : "bg-surface-primary"}
        ${highlight ? "ring-2 ring-brand-gradientStart/20" : ""}
      `}
    >
      <CardContent className="p-4">
        <p className={`text-xs uppercase tracking-wider mb-2 font-semibold ${gradient ? "text-white/80" : "text-text-muted"}`}>
          {label}
        </p>
        <div className="flex items-baseline gap-1">
          <p className={`text-2xl sm:text-3xl font-bold tabular-nums leading-none ${gradient ? "text-white" : "text-text-primary"}`}>
            {value}
          </p>
          {suffix && (
            <p className={`text-base sm:text-lg font-medium flex-shrink-0 ${gradient ? "text-white/70" : "text-text-secondary"}`}>
              {suffix}
            </p>
          )}
        </div>
        {subtitle && (
          <p className={`text-xs mt-2 ${gradient ? "text-white/60" : "text-text-muted"}`}>
            {subtitle}
          </p>
        )}
      </CardContent>
    </Card>
  );
}

export function StatsContent({ data }: StatsContentProps) {
  const currentMonthName = new Date().toLocaleDateString("nb-NO", { month: "long" });
  const lastMonthName = new Date(new Date().getFullYear(), new Date().getMonth() - 1, 1)
    .toLocaleDateString("nb-NO", { month: "long" });

  const getChangeText = () => {
    if (data.percentageChange === null) return null;
    const isPositive = data.percentageChange >= 0;
    return `${isPositive ? '+' : ''}${data.percentageChange}% fra ${lastMonthName}`;
  };

  return (
    <div className="pb-6 pt-2 space-y-6">
      {/* Hero stat - Current month earnings */}
      <div className="space-y-3">
        <div className="flex items-baseline gap-2">
          <div className="h-1 w-12 bg-gradient-to-r from-brand-gradientStart to-brand-gradientEnd rounded-full" />
          <h1 className="text-xl font-bold text-text-primary capitalize">{currentMonthName}</h1>
        </div>
        <StatCard
          label="Inntjening"
          value={formatCurrency(data.currentMonth.totalEarnings, true)}
          suffix="kr"
          gradient={true}
          subtitle={getChangeText() || undefined}
        />
      </div>

      {/* Current month details */}
      <div className="space-y-4">
        <h2 className="text-sm font-semibold text-text-muted uppercase tracking-wider">Denne måneden</h2>
        <div className="grid grid-cols-3 gap-3">
          <StatCard
            label="Timer"
            value={formatHours(data.currentMonth.totalHours)}
          />
          <StatCard
            label="Vakter"
            value={data.currentMonth.shiftCount.toString()}
          />
          <StatCard
            label="Timelønn"
            value={formatCurrency(data.currentMonth.averageRate, true)}
            suffix="kr/t"
            highlight={true}
          />
        </div>
      </div>

      {/* Last month comparison */}
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="h-px flex-1 bg-border" />
          <h2 className="text-sm font-semibold text-text-muted uppercase tracking-wider capitalize">
            {lastMonthName}
          </h2>
          <div className="h-px flex-1 bg-border" />
        </div>
        <div className="grid grid-cols-3 gap-3">
          <StatCard
            label="Inntjening"
            value={formatCurrency(data.lastMonth.totalEarnings, true)}
            suffix="kr"
          />
          <StatCard
            label="Timer"
            value={formatHours(data.lastMonth.totalHours)}
          />
          <StatCard
            label="Vakter"
            value={data.lastMonth.shiftCount.toString()}
          />
        </div>
      </div>

      {/* Year to date */}
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="h-px flex-1 bg-border" />
          <h2 className="text-sm font-semibold text-text-muted uppercase tracking-wider">
            {new Date().getFullYear()} (hittil)
          </h2>
          <div className="h-px flex-1 bg-border" />
        </div>
        <div className="grid grid-cols-3 gap-3">
          <StatCard
            label="Inntjening"
            value={formatCurrency(data.yearToDate.totalEarnings, true)}
            suffix="kr"
          />
          <StatCard
            label="Timer"
            value={formatHours(data.yearToDate.totalHours)}
          />
          <StatCard
            label="Vakter"
            value={data.yearToDate.shiftCount.toString()}
          />
        </div>
      </div>
    </div>
  );
}
