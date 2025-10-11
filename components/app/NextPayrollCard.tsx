'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { Card, CardHeader } from '@appui/Card';
import { cn } from '@/lib/cn';

interface NextPayrollCardProps {
  payrollDay: number;
  netAmount: number;
  grossAmount?: number;
  baseAmount?: number;
  bonusAmount?: number;
  taxAmount?: number;
  taxEnabled: boolean;
  isLoading?: boolean;
  className?: string;
  selectedMonth?: Date;
}

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

const dateFormatter = new Intl.DateTimeFormat("nb-NO", {
  day: "numeric",
  month: "long",
});

function getPayrollDateForMonth(payrollDay: number, selectedMonth?: Date): Date {
  // If a month is selected, return the payroll date for that selected month
  // (which pays for the previous month's work)
  if (selectedMonth) {
    return new Date(
      selectedMonth.getFullYear(),
      selectedMonth.getMonth(),
      payrollDay
    );
  }

  // Otherwise, use the original logic for "next payroll"
  const today = new Date();
  const currentMonth = today.getMonth();
  const currentYear = today.getFullYear();
  const currentDay = today.getDate();

  // Create payroll date for current month
  const currentPayrollDate = new Date(currentYear, currentMonth, payrollDay);

  // If payroll day has passed this month, use next month
  if (currentDay >= payrollDay) {
    return new Date(currentYear, currentMonth + 1, payrollDay);
  }

  return currentPayrollDate;
}

function formatCurrency(value: number): string {
  return `${numberFormatter.format(Math.round(value))} kr`;
}

function formatPlainAmount(value: number): string {
  return numberFormatter.format(Math.round(value));
}

export const NextPayrollCard: React.FC<NextPayrollCardProps> = ({
  payrollDay,
  netAmount,
  grossAmount,
  baseAmount,
  bonusAmount,
  taxAmount,
  taxEnabled,
  isLoading = false,
  className = '',
  selectedMonth,
}) => {
  const router = useRouter();
  const nextPayrollDate = getPayrollDateForMonth(payrollDay, selectedMonth);
  const formattedDate = dateFormatter.format(nextPayrollDate);

  // Calculate breakdown based on tax settings
  let breakdown: string;
  if (taxEnabled && grossAmount !== undefined && taxAmount !== undefined) {
    breakdown = `${formatPlainAmount(grossAmount)} - ${formatPlainAmount(taxAmount)}`;
  } else if (baseAmount !== undefined && bonusAmount !== undefined) {
    breakdown = bonusAmount > 0
      ? `${formatPlainAmount(baseAmount)} + ${formatPlainAmount(bonusAmount)}`
      : formatPlainAmount(baseAmount);
  } else {
    breakdown = formatPlainAmount(netAmount);
  }

  const handleClick = () => {
    router.push('/settings/pay');
  };

  const handleKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      handleClick();
    }
  };

  return (
    <Card
      className={cn(
        "rounded-3xl cursor-pointer transition-colors hover:bg-surface-secondary",
        className
      )}
      onClick={handleClick}
      role="button"
      tabIndex={0}
      onKeyDown={handleKeyDown}
    >
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6">
        {isLoading ? (
          <div className="animate-pulse flex-1 space-y-3" aria-hidden="true">
            <div className="h-4 w-32 rounded-lg bg-text-muted/20" />
            <div className="h-4 w-24 rounded-lg bg-text-muted/20" />
          </div>
        ) : (
          <>
            <div className="space-y-1">
              <p className="text-lg font-medium text-text-primary">
                {formattedDate}
              </p>
              <div className="flex items-center gap-3 text-sm text-text-secondary">
                <span className="inline-flex items-center gap-1 text-text-primary">
                  <svg
                    aria-hidden="true"
                    className="h-4 w-4 text-text-muted"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.5"
                  >
                    <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
                    <line x1="16" y1="2" x2="16" y2="6" />
                    <line x1="8" y1="2" x2="8" y2="6" />
                    <line x1="3" y1="10" x2="21" y2="10" />
                  </svg>
                  Neste lønning
                </span>
              </div>
            </div>
            <div className="text-right">
              <p className="text-2xl font-semibold tracking-tight text-text-primary">
                {formatCurrency(netAmount)}
              </p>
              <p className="text-xs">{breakdown}</p>
            </div>
          </>
        )}
      </CardHeader>
    </Card>
  );
};

export default NextPayrollCard;
