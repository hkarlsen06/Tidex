"use client";

import { Card, CardContent } from "@/components/app/Card";
import { MonthlyGoal } from "@/app/(app)/stats/_data/getStatsData";
import { Target, TrendingUp } from "lucide-react";

type MonthlyGoalProgressProps = {
  data: MonthlyGoal;
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

function formatCurrency(value: number, compact = false): string {
  if (compact && value >= 100000) {
    return compactFormatter.format(Math.round(value));
  }
  return numberFormatter.format(Math.round(value));
}

export function MonthlyGoalProgress({ data }: MonthlyGoalProgressProps) {
  if (!data.enabled) {
    return null;
  }

  // Cap percentage at 150% for display purposes
  const displayPercentage = Math.min(data.percentage, 150);
  const isGoalReached = data.percentage >= 100;
  const progressOverTarget = data.progress - data.target;

  // Color coding based on progress
  let progressColor = "hsl(var(--text-muted))"; // < 50%: muted
  let progressBg = "hsl(var(--text-muted) / 0.1)";

  if (data.percentage >= 100) {
    // 100%+: brand/purple (celebration)
    progressColor = "hsl(var(--brand-highlight))";
    progressBg = "hsl(var(--brand-highlight) / 0.1)";
  } else if (data.percentage >= 80) {
    // 80-99%: success/green
    progressColor = "hsl(var(--success))";
    progressBg = "hsl(var(--success) / 0.1)";
  } else if (data.percentage >= 50) {
    // 50-79%: warning/yellow
    progressColor = "hsl(var(--warning))";
    progressBg = "hsl(var(--warning) / 0.1)";
  }

  // SVG circle parameters
  const size = 160;
  const strokeWidth = 12;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (displayPercentage / 100) * circumference;

  return (
    <Card className="border-border bg-surface-primary overflow-hidden">
      <CardContent className="p-6">
        {/* Title row */}
        <div className="flex items-start justify-between mb-4">
          <h3 className="text-xl font-bold text-text-primary">
            Månedsmål
          </h3>
          <div className="text-text-muted opacity-50">
            <Target className="w-5 h-5" />
          </div>
        </div>

        <div className="grid grid-cols-[1fr,auto] gap-6 items-center">
          {/* Left side: Text content */}
          <div className="flex flex-col items-center justify-center space-y-3">
            <p className="text-sm text-text-secondary">
              Mål: {formatCurrency(data.target)} kr
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

            {/* Status message */}
            {isGoalReached ? (
              <div className="flex items-center gap-2">
                <TrendingUp className="w-5 h-5" style={{ color: progressColor }} />
                <p className="text-base font-medium" style={{ color: progressColor }}>
                  Mål nådd! +{formatCurrency(progressOverTarget)} kr over
                </p>
              </div>
            ) : (
              <p className="text-base font-medium text-text-secondary">
                {formatCurrency(data.remaining)} kr gjenstår
              </p>
            )}
          </div>

          {/* Right side: Circular progress indicator */}
          <div className="relative flex-shrink-0">
            <svg width={size} height={size} className="transform -rotate-90">
              {/* Background circle */}
              <circle
                cx={size / 2}
                cy={size / 2}
                r={radius}
                fill="none"
                stroke={progressBg}
                strokeWidth={strokeWidth}
              />
              {/* Progress circle */}
              <circle
                cx={size / 2}
                cy={size / 2}
                r={radius}
                fill="none"
                stroke={progressColor}
                strokeWidth={strokeWidth}
                strokeDasharray={circumference}
                strokeDashoffset={offset}
                strokeLinecap="round"
                style={{
                  transition: "stroke-dashoffset 0.5s ease",
                }}
              />
            </svg>
            {/* Center text */}
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <p
                className="text-3xl font-bold tabular-nums"
                style={{ color: progressColor }}
              >
                {data.percentage.toFixed(0)}%
              </p>
              <p className="text-sm text-text-muted mt-1">
                {formatCurrency(data.progress, true)} kr
              </p>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
