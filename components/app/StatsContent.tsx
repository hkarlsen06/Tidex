"use client";

import { useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/app/Card";
import { StatsData } from "@/app/(app)/stats/_data/getStatsData";
import { MonthlyBarChart } from "@/components/app/charts/MonthlyBarChart";
import { WeeklyBarChart } from "@/components/app/charts/WeeklyBarChart";
import { DayOfWeekChart } from "@/components/app/charts/DayOfWeekChart";
import { YearlyCumulativeChart } from "@/components/app/charts/YearlyCumulativeChart";
import { MonthlyCumulativeChart } from "@/components/app/charts/MonthlyCumulativeChart";
import { TrendingUp, TrendingDown, Clock, Briefcase, DollarSign } from "lucide-react";
import { MonthPicker } from "@/components/app/MonthPicker";
import { useMonth } from "@/components/app/MonthContext";

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
  icon?: ReactNode;
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
  const {
    selectedMonth,
    goToPreviousMonth,
    goToNextMonth,
  } = useMonth();

  const [activeData, setActiveData] = useState<StatsData>(data);
  const [isLoading, setIsLoading] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);

  const selectedYear = selectedMonth.getFullYear();
  const selectedMonthNumber = selectedMonth.getMonth() + 1;

  const focusYear = activeData.focusMonth.year;
  const focusMonth = activeData.focusMonth.month;

  useEffect(() => {
    if (focusYear === selectedYear && focusMonth === selectedMonthNumber) {
      return;
    }

    const controller = new AbortController();
    const query = new URLSearchParams({
      year: selectedYear.toString(),
      month: selectedMonthNumber.toString(),
    });

    setIsLoading(true);
    setFetchError(null);

    fetch(`/api/stats?${query.toString()}`, {
      method: "GET",
      credentials: "include",
      cache: "no-store",
      signal: controller.signal,
    })
      .then((response) => {
        if (response.status === 401) {
          // Session expired, force reload to trigger middleware redirect
          if (typeof window !== "undefined") {
            window.location.href = "/login";
          }
          throw new Error("Unauthorized");
        }
        if (!response.ok) {
          throw new Error(`Failed to load stats (${response.status})`);
        }
        return response.json() as Promise<StatsData>;
      })
      .then((payload) => {
        if (!controller.signal.aborted) {
          setActiveData(payload);
        }
      })
      .catch((error) => {
        if (controller.signal.aborted) {
          return;
        }
        console.error("Failed to load stats data", error);
        setFetchError("Kunne ikke oppdatere statistikken. Prøv igjen senere.");
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setIsLoading(false);
        }
      });

    return () => {
      controller.abort();
    };
  }, [focusMonth, focusYear, selectedMonthNumber, selectedYear]);

  const grossEarnings = activeData.currentMonth.totalEarnings;
  const netEarnings = activeData.currentMonth.totalEarningsNet;
  const displayedEarnings = activeData.tax.enabled ? netEarnings : grossEarnings;

  const selectedHours = activeData.currentMonth.totalHours;
  const selectedShiftCount = activeData.currentMonth.shiftCount;
  const selectedAverageRate = activeData.currentMonth.averageRate;

  const trend = activeData.percentageChange !== null
    ? {
        value: activeData.percentageChange,
        isPositive: activeData.percentageChange >= 0,
      }
    : undefined;

  const selectedMonthLabel = useMemo(() => {
    const name = new Intl.DateTimeFormat("nb-NO", { month: "long" }).format(selectedMonth);
    return name.charAt(0).toUpperCase() + name.slice(1);
  }, [selectedMonth]);

  const realNow = useMemo(() => new Date(), []);
  const isCurrentMonthSelected =
    selectedYear === realNow.getUTCFullYear() &&
    selectedMonthNumber === realNow.getUTCMonth() + 1;

  return (
    <div className="flex flex-col w-full max-w-md mx-auto pb-6 pt-2 space-y-6">
      {/* Hero section with key metrics */}
      <div className="space-y-5">
        <div className="flex items-center justify-between -mb-3">
          <MonthPicker
            month={selectedMonth}
            onPreviousMonth={goToPreviousMonth}
            onNextMonth={goToNextMonth}
          />
          <span className="font-medium text-text-muted mr-3">{selectedMonth.getFullYear()}</span>
        </div>
        {isLoading && (
          <span className="text-sm text-text-muted">Oppdaterer...</span>
        )}
        {fetchError && (
          <p className="text-sm text-error">
            {fetchError}
          </p>
        )}

        <Card className="border-border bg-surface-primary overflow-hidden">
          <CardContent className="p-6">
            <p className="text-lg font-semibold text-text-muted mb-3">
              Inntjening denne måneden
            </p>
            <div className="flex items-baseline gap-2">
              <p className="text-5xl font-bold tabular-nums text-text-primary">
                {formatCurrency(displayedEarnings, true)}
              </p>
              <p className="text-2xl font-medium text-text-secondary">kr</p>
            </div>
            {activeData.tax.enabled && (
              <div className="mt-3 space-y-1">
                <p className="text-base font-medium text-text-secondary">
                  Etter skatt
                </p>
                <p className="text-sm text-text-muted">
                  Før skatt: {formatCurrency(grossEarnings, true)} kr
                </p>
              </div>
            )}
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
            value={formatHours(selectedHours)}
            icon={<Clock className="w-5 h-5" />}
          />
          <StatCard
            label="Vakter"
            value={selectedShiftCount.toString()}
            icon={<Briefcase className="w-5 h-5" />}
          />
        </div>
      </div>

      {/* Monthly cumulative comparison chart */}
      <Card className="border-border bg-surface-primary">
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            Månedens utvikling
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          <MonthlyCumulativeChart data={activeData.thisMonthCumulative} />
        </CardContent>
      </Card>

      {/* Weekly earnings chart - only show for current month */}
      {isCurrentMonthSelected && (
        <Card className="border-border bg-surface-primary">
          <CardHeader className="pb-3">
            <CardTitle className="text-xl font-bold text-text-primary">
              Denne uken
            </CardTitle>
          </CardHeader>
          <CardContent className="px-3 pb-4 pt-1">
            <WeeklyBarChart data={activeData.thisWeek} />
          </CardContent>
        </Card>
      )}

      {/* Additional stats grid */}
      <div className="grid grid-cols-1 gap-3">
        <StatCard
          label="Gjennomsnitt"
          value={formatCurrency(selectedAverageRate, true)}
          suffix="kr/t"
          icon={<DollarSign className="w-4 h-4" />}
        />
      </div>

      {/* Year to date summary */}
      <div className="space-y-5">
        <h2 className="text-xl font-bold text-text-primary">
          {selectedYear} totalt
        </h2>

        {/* Cumulative earnings chart */}
        <Card className="border-border bg-surface-primary">
          <CardHeader className="pb-3">
            <CardTitle className="text-xl font-bold text-text-primary">
              Kumulativ utvikling
            </CardTitle>
          </CardHeader>
          <CardContent className="px-3 pb-4 pt-1">
            <YearlyCumulativeChart data={activeData.yearlyCumulative} />
          </CardContent>
        </Card>

        <Card className="border-border bg-surface-primary">
          <CardHeader className="pb-3">
            <CardTitle className="text-xl font-bold text-text-primary">
              Siste 6 måneder
            </CardTitle>
          </CardHeader>
          <CardContent className="px-3 pb-4 pt-1">
            <MonthlyBarChart data={activeData.last6Months} />
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
            <DayOfWeekChart data={activeData.byDayOfWeek} />
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 gap-3">
          <StatCard
            label="Totalt"
            value={formatCurrency(activeData.yearToDate.totalEarnings)}
            suffix="kr"
          />
          <StatCard
            label="Timer"
            value={formatHours(activeData.yearToDate.totalHours)}
          />
          <StatCard
            label="Vakter"
            value={activeData.yearToDate.shiftCount.toString()}
          />
        </div>
      </div>
    </div>
  );
}
