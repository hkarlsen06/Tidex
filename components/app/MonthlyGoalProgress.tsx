"use client";

import { useCallback } from "react";
import { Card, CardContent } from "@/components/app/Card";
import { MonthlyGoal } from "@/data-access/stats";
import { Target, TrendingUp } from "lucide-react";
import { useTranslations } from "@/lib/i18n/client";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";

type MonthlyGoalProgressProps = {
  data: MonthlyGoal;
};

export function MonthlyGoalProgress({ data }: MonthlyGoalProgressProps) {
  const { t } = useTranslations();
  const formatCurrency = useFormatCurrency();

  // Format currency with full symbol (handles prefix/suffix positioning)
  const formatCurrencyFull = useCallback(
    (value: number, compact = false): string => {
      if (compact && value >= 100000) {
        return formatCurrency(value, { notation: "compact" });
      }
      return formatCurrency(value);
    },
    [formatCurrency]
  );

  if (!data.enabled) {
    return null;
  }

  // Cap percentage at 150% for display purposes
  const displayPercentage = Math.min(data.percentage, 150);
  const isGoalReached = data.percentage >= 100;

  // Color coding based on progress
  let progressColor = "hsl(var(--text-muted))"; // < 50%: muted

  if (data.percentage >= 100) {
    // 100%+: brand/purple (celebration)
    progressColor = "hsl(var(--brand-highlight))";
  } else if (data.percentage >= 80) {
    // 80-99%: success/green
    progressColor = "hsl(var(--success))";
  } else if (data.percentage >= 50) {
    // 50-79%: warning/yellow
    progressColor = "hsl(var(--warning))";
  }

  return (
    <Card className="border-border bg-surface-primary overflow-hidden">
      <CardContent className="p-6">
        {/* Title row */}
        <div className="flex items-start justify-between mb-4">
          <h3 className="text-xl font-bold text-text-primary">
            {t.pages.stats.monthlyGoal.title}
          </h3>
          <div className="text-text-muted opacity-50">
            <Target className="w-5 h-5" />
          </div>
        </div>

        <div className="flex flex-col space-y-3">
          <p className="text-sm text-text-secondary">
            {t.pages.stats.monthlyGoal.goalLabel}:{" "}
            {formatCurrencyFull(data.target)}
          </p>

          {/* Progress bar */}
          <div className="w-full">
            <div className="h-2 bg-surface-secondary rounded-full overflow-hidden">
              <div
                className="h-full rounded-full transition-all duration-500"
                style={{
                  width: `${Math.min(displayPercentage, 100)}%`,
                  backgroundColor: progressColor,
                }}
              />
            </div>
          </div>

          {/* Status message - always on same line */}
          <div className="flex items-center justify-between">
            <p className="text-base font-medium text-text-secondary">
              {t.pages.stats.monthlyGoal.remaining.replace(
                "{amount}",
                formatCurrencyFull(data.remaining)
              )}
            </p>
            {isGoalReached && (
              <div className="flex items-center gap-2">
                <TrendingUp
                  className="w-5 h-5"
                  style={{ color: progressColor }}
                />
                <p
                  className="text-base font-medium"
                  style={{ color: progressColor }}
                >
                  {t.pages.stats.monthlyGoal.goalReached}
                </p>
              </div>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
