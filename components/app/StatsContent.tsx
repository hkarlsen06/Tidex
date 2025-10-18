"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/app/Card";
import { StatsData } from "@/app/(app)/stats/_data/getStatsData";
import { MonthlyBarChart } from "@/components/app/charts/MonthlyBarChart";
import { WeeklyBarChart } from "@/components/app/charts/WeeklyBarChart";
import { DayOfWeekChart } from "@/components/app/charts/DayOfWeekChart";
import { CumulativeAreaChart } from "@/components/app/charts/CumulativeAreaChart";
import { MonthlyCumulativeChart } from "@/components/app/charts/MonthlyCumulativeChart";
import { TrendingUp, TrendingDown, Clock, Briefcase, DollarSign } from "lucide-react";

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
  trend?: {
    value: number;
    isPositive: boolean;
  };
  icon?: React.ReactNode;
};

function StatCard({ label, value, suffix, trend, icon }: StatCardProps) {
  return (
    <Card className="border-border bg-surface-primary overflow-hidden">
      <CardContent className="p-5">
        <div className="flex items-start justify-between mb-3">
          <p className="text-base font-semibold text-text-muted">
            {label}
          </p>
          {icon && <div className="text-text-muted opacity-50">{icon}</div>}
        </div>
        <div className="flex items-baseline gap-1.5">
          <p className="text-3xl font-bold tabular-nums leading-none text-text-primary">
            {value}
          </p>
          {suffix && (
            <p className="text-xl font-medium flex-shrink-0 text-text-secondary">
              {suffix}
            </p>
          )}
        </div>
        {trend && (
          <div className="flex items-center gap-1.5 mt-3">
            {trend.isPositive ? (
              <TrendingUp className="w-4 h-4 text-success" />
            ) : (
              <TrendingDown className="w-4 h-4 text-error" />
            )}
            <p className={`text-base font-medium ${trend.isPositive ? "text-success" : "text-error"}`}>
              {trend.isPositive ? "+" : ""}{trend.value}%
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export function StatsContent({ data }: StatsContentProps) {
  const currentMonthName = new Date().toLocaleDateString("nb-NO", { month: "long" });
  const trend = data.percentageChange !== null ? {
    value: data.percentageChange,
    isPositive: data.percentageChange >= 0,
  } : undefined;

  return (
    <div className="flex flex-col w-full max-w-md mx-auto pb-6 pt-2 space-y-6">
      {/* Hero section with key metrics */}
      <div className="space-y-5">
        <h1 className="text-2xl font-bold text-text-primary capitalize">{currentMonthName}</h1>

        <Card className="border-border bg-surface-primary overflow-hidden">
          <CardContent className="p-6">
            <p className="text-lg font-semibold text-text-muted mb-3">
              Inntjening denne måneden
            </p>
            <div className="flex items-baseline gap-2">
              <p className="text-5xl font-bold tabular-nums text-text-primary">
                {formatCurrency(data.currentMonth.totalEarnings, true)}
              </p>
              <p className="text-2xl font-medium text-text-secondary">kr</p>
            </div>
            {trend && (
              <div className="flex items-center gap-2 mt-4">
                {trend.isPositive ? (
                  <TrendingUp className="w-5 h-5 text-success" />
                ) : (
                  <TrendingDown className="w-5 h-5 text-error" />
                )}
                <p className={`text-lg font-medium ${trend.isPositive ? "text-success" : "text-error"}`}>
                  {trend.isPositive ? "+" : ""}{trend.value}% fra forrige måned
                </p>
              </div>
            )}
          </CardContent>
        </Card>

        <div className="grid grid-cols-2 gap-3">
          <StatCard
            label="Timer"
            value={formatHours(data.currentMonth.totalHours)}
            icon={<Clock className="w-5 h-5" />}
          />
          <StatCard
            label="Vakter"
            value={data.currentMonth.shiftCount.toString()}
            icon={<Briefcase className="w-5 h-5" />}
          />
        </div>
      </div>

      {/* Monthly earnings chart */}
      <Card className="border-border bg-surface-primary">
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            Siste 6 måneder
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          <MonthlyBarChart data={data.last6Months} />
        </CardContent>
      </Card>

      {/* Monthly cumulative comparison chart */}
      <Card className="border-border bg-surface-primary">
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            Månedens utvikling
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          <MonthlyCumulativeChart data={data.thisMonthCumulative} />
        </CardContent>
      </Card>

      {/* Weekly earnings chart */}
      <Card className="border-border bg-surface-primary">
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            Denne uken
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          <WeeklyBarChart data={data.thisWeek} />
        </CardContent>
      </Card>

      {/* Additional stats grid */}
      <div className="grid grid-cols-1 gap-3">
        <StatCard
          label="Gjennomsnitt"
          value={formatCurrency(data.currentMonth.averageRate, true)}
          suffix="kr/t"
          icon={<DollarSign className="w-4 h-4" />}
        />
      </div>

      {/* Cumulative earnings chart */}
      <Card className="border-border bg-surface-primary">
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            Kumulativ utvikling
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          <CumulativeAreaChart data={data.last6Months} />
        </CardContent>
      </Card>

      {/* Day of week breakdown */}
      <Card className="border-border bg-surface-primary">
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            Gjennomsnitt per ukedag
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          <DayOfWeekChart data={data.byDayOfWeek} />
        </CardContent>
      </Card>

      {/* Year to date summary */}
      <div className="space-y-5">
        <h2 className="text-xl font-bold text-text-primary">
          {new Date().getFullYear()} totalt
        </h2>
        <div className="grid grid-cols-1 gap-3">
          <StatCard
            label="Totalt"
            value={formatCurrency(data.yearToDate.totalEarnings)}
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
