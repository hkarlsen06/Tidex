'use client';

import React, { useMemo, useState } from 'react';
import { SafeAnimateNumber } from '@/components/app/SafeAnimateNumber';
import { Card, CardHeader } from '@/components/app/Card';
import { cn } from '@/lib/cn';
import { useNavigationFeedback } from './navigation-feedback';
import { useTranslations } from '@/lib/i18n/client';
import { getDateFormatter } from '@/lib/i18n/locale';
import { adjustPayrollDate } from '@/lib/payroll/adjust-payroll-date';
import type { Locale } from '@/lib/i18n';
import { PartyPopper } from 'lucide-react';
import { useCurrency } from '@/components/providers/CurrencyProvider';

interface NextPayrollCardProps {
  payrollDay: number;
  netAmount: number;
  grossAmount?: number;
  baseAmount?: number;
  supplementAmount?: number;
  taxAmount?: number;
  taxEnabled: boolean;
  isLoading?: boolean;
  className?: string;
  selectedMonth?: Date;
  hasPayout?: boolean;
  showPreviousPayroll?: boolean;
  /** Progress through the month until payroll (1-100), shows a subtle progress bar when provided */
  progress?: number;
  /** Whether payroll is today - shows "I dag" with party popper icon */
  isPayrollToday?: boolean;
}

function getPayrollDateForMonth(
  payrollDay: number,
  selectedMonth: Date | undefined,
  locale: Locale
): Date {
  const referenceDate = selectedMonth ?? new Date();

  return adjustPayrollDate(
    payrollDay,
    referenceDate.getMonth(),
    referenceDate.getFullYear(),
    locale
  );
}

export const NextPayrollCard: React.FC<NextPayrollCardProps> = ({
  payrollDay,
  netAmount,
  grossAmount,
  baseAmount,
  supplementAmount,
  taxAmount,
  taxEnabled,
  isLoading = false,
  className = '',
  selectedMonth,
  hasPayout = true,
  showPreviousPayroll,
  progress,
  isPayrollToday = false,
}) => {
  const { navigate } = useNavigationFeedback();
  const { t, locale } = useTranslations();
  const { symbol: currencySymbol, display: currencyDisplay } = useCurrency();

  // Keep track of last displayed values so we can animate smoothly during loading
  // Uses useState with a functional update that only changes state when we have "real" data
  // React 19 allows calling setState during render if it returns the same value (bailout)
  const [displayValues, setDisplayValues] = useState({
    netAmount,
    grossAmount,
    baseAmount,
    supplementAmount,
    taxAmount,
    taxEnabled,
    hasPayout,
  });

  // Check if current props represent "real" data:
  // - Either there's actual money (netAmount > 0)
  // - Or it's explicitly no payout (hasPayout is false AND we're not loading)
  // This prevents flashing to zeros/placeholder during month transitions
  const hasRealData = netAmount > 0 || (!isLoading && !hasPayout);

  // Check if we need to update - only when we have real data AND values are different
  const needsUpdate = hasRealData && (
    displayValues.netAmount !== netAmount ||
    displayValues.grossAmount !== grossAmount ||
    displayValues.baseAmount !== baseAmount ||
    displayValues.supplementAmount !== supplementAmount ||
    displayValues.taxAmount !== taxAmount ||
    displayValues.taxEnabled !== taxEnabled ||
    displayValues.hasPayout !== hasPayout
  );

  // Use conditional setState during render - this is the React 19 pattern for
  // updating state based on props. The key is to only call it when values differ.
  if (needsUpdate) {
    setDisplayValues({
      netAmount,
      grossAmount,
      baseAmount,
      supplementAmount,
      taxAmount,
      taxEnabled,
      hasPayout,
    });
  }

  // Create locale-aware date formatters for day and month separately
  const monthFormatter = useMemo(() => {
    return getDateFormatter(locale, { month: 'long' });
  }, [locale]);

  const payrollDate = getPayrollDateForMonth(payrollDay, selectedMonth, locale);
  const dayNumber = payrollDate.getDate();
  const monthName = monthFormatter.format(payrollDate);

  const showNoPayoutPlaceholder = !displayValues.hasPayout;
  const today = useMemo(() => {
    const now = new Date();
    // Normalize to start of day for accurate date comparison
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  }, []);
  const matchesCurrentMonth = selectedMonth
    ? selectedMonth.getFullYear() === today.getFullYear() &&
      selectedMonth.getMonth() === today.getMonth()
    : true;
  // Compare full dates (not just day numbers) to handle adjusted dates correctly
  const defaultShowPreviousPayroll = matchesCurrentMonth && today > payrollDate;
  const shouldShowPreviousPayroll =
    showPreviousPayroll ?? defaultShowPreviousPayroll;
  const payrollLabel = matchesCurrentMonth
    ? shouldShowPreviousPayroll
      ? t.components.nextPayrollCard.previousPayroll
      : t.components.nextPayrollCard.nextPayroll
    : t.components.nextPayrollCard.payroll;

  // Calculate breakdown based on tax settings (using displayValues for smooth loading)
  // Determine if breakdown adds meaningful information
  const hasSupplements = (displayValues.supplementAmount ?? 0) > 0;
  const showBreakdown = displayValues.taxEnabled || hasSupplements;

  // Breakdown type and values for animated display
  const breakdownType: 'tax' | 'supplement' | 'none' =
    showNoPayoutPlaceholder ? 'none' :
    displayValues.taxEnabled && displayValues.grossAmount !== undefined && displayValues.taxAmount !== undefined ? 'tax' :
    displayValues.baseAmount !== undefined && displayValues.supplementAmount !== undefined && hasSupplements ? 'supplement' : 'none';

  const breakdownValues = {
    first: breakdownType === 'tax' ? displayValues.grossAmount! : breakdownType === 'supplement' ? displayValues.baseAmount! : 0,
    second: breakdownType === 'tax' ? displayValues.taxAmount! : breakdownType === 'supplement' ? displayValues.supplementAmount! : 0,
    operator: breakdownType === 'tax' ? '−' : '+',
  };

  const handleClick = () => {
    navigate('/settings/pay');
  };

  const handleKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      handleClick();
    }
  };

  const hasProgress = typeof progress === 'number' && progress >= 1 && progress <= 100;

  // Display text for the date - show "I dag" with party popper on payroll day
  // Norwegian format: "15. januar", English format: "January 15"
  // Note: Date is rendered statically (no AnimateNumber) because:
  // 1. The date changes discretely, not numerically (no smooth animation needed)
  // 2. AnimateNumber's internal state can get corrupted with cacheComponents
  const dateDisplay = isPayrollToday ? (
    <span className="inline-flex items-center gap-2">
      {t.components.nextPayrollCard.today}
      <PartyPopper className="h-5 w-5 text-brand-highlight" aria-hidden="true" />
    </span>
  ) : (
    <span>
      {locale === 'no' ? `${dayNumber}. ${monthName}` : `${monthName} ${dayNumber}`}
    </span>
  );

  return (
    <Card
      className={cn(
        "bg-surface-primary rounded-3xl cursor-pointer transition-colors hover:bg-surface-secondary relative overflow-hidden",
        className
      )}
      onClick={handleClick}
      role="button"
      tabIndex={0}
      onKeyDown={handleKeyDown}
    >
      {/* Progress bar background - uses CSS animation to animate from 0 to current progress */}
      {hasProgress && (
        <div
          className="absolute inset-0 bg-brand-highlight/10 animate-progress-grow"
          style={{ '--progress-target': `${progress}%` } as React.CSSProperties}
          aria-hidden="true"
        />
      )}
      <CardHeader className={cn(
        "flex flex-row justify-between gap-4 space-y-0 py-6 relative z-10",
        !showNoPayoutPlaceholder && !showBreakdown ? "items-center" : "items-start",
        isLoading && "opacity-60"
      )}>
        <div className="space-y-1">
          <span className="block text-lg font-medium text-text-primary">
            {dateDisplay}
          </span>
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
              {payrollLabel}
            </span>
          </div>
        </div>
        <div className="text-right">
          {showNoPayoutPlaceholder ? (
            <div>
              <p className="text-2xl font-semibold tracking-tight text-text-muted">
                {currencyDisplay === 'prefix' ? `${currencySymbol}——` : `—— ${currencySymbol}`}
              </p>
              <p className="text-sm text-text-muted">——</p>
            </div>
          ) : (
            <div>
              <span className="block text-2xl font-semibold tracking-tight text-text-primary">
                <SafeAnimateNumber
                  layout={false}
                  format={{
                    style: 'currency',
                    currency: 'NOK',
                    maximumFractionDigits: 0,
                  }}
                  locales="nb-NO"
                  transition={{
                    visualDuration: 0.8,
                    type: 'spring',
                    bounce: 0.1,
                  }}
                  routePattern="/"
                >
                  {displayValues.netAmount}
                </SafeAnimateNumber>
              </span>
              {showBreakdown && breakdownType !== 'none' && (
                <span className="block text-sm text-text-muted">
                  <SafeAnimateNumber
                    layout={false}
                    format={{ maximumFractionDigits: 0 }}
                    locales="nb-NO"
                    transition={{ visualDuration: 0.6, type: 'spring', bounce: 0.1 }}
                    routePattern="/"
                  >
                    {breakdownValues.first}
                  </SafeAnimateNumber>
                  {' '}{breakdownValues.operator}{' '}
                  <SafeAnimateNumber
                    layout={false}
                    format={{ maximumFractionDigits: 0 }}
                    locales="nb-NO"
                    transition={{ visualDuration: 0.6, type: 'spring', bounce: 0.1 }}
                    routePattern="/"
                  >
                    {breakdownValues.second}
                  </SafeAnimateNumber>
                </span>
              )}
            </div>
          )}
        </div>
      </CardHeader>
    </Card>
  );
};

export default NextPayrollCard;
