'use client';

import React, { useMemo } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Card, CardHeader } from '@/components/app/Card';
import { cn } from '@/lib/cn';
import { useNavigationFeedback } from './navigation-feedback';
import { useTranslations } from '@/lib/i18n/client';
import { formatPlainAmount } from '@/lib/formatters';
import { useFormatCurrency } from '@/lib/hooks/useFormatCurrency';
import { getDateFormatter } from '@/lib/i18n/locale';
import { adjustPayrollDate } from '@/lib/payroll/adjust-payroll-date';
import type { Locale } from '@/lib/i18n';
import { PartyPopper } from 'lucide-react';

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
  const formatCurrency = useFormatCurrency();

  // Create locale-aware date formatter
  const dateFormatter = useMemo(() => {
    return getDateFormatter(locale, {
      day: 'numeric',
      month: 'long',
    });
  }, [locale]);

  const payrollDate = getPayrollDateForMonth(payrollDay, selectedMonth, locale);
  const formattedDate = dateFormatter.format(payrollDate);

  const showNoPayoutPlaceholder = !hasPayout;
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

  // Calculate breakdown based on tax settings
  let breakdown: string;
  if (showNoPayoutPlaceholder) {
    breakdown = '---';
  } else if (taxEnabled && grossAmount !== undefined && taxAmount !== undefined) {
    breakdown = `${formatPlainAmount(grossAmount)} - ${formatPlainAmount(taxAmount)}`;
  } else if (baseAmount !== undefined && supplementAmount !== undefined) {
    breakdown = supplementAmount > 0
      ? `${formatPlainAmount(baseAmount)} + ${formatPlainAmount(supplementAmount)}`
      : formatPlainAmount(baseAmount);
  } else {
    breakdown = formatPlainAmount(netAmount);
  }

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
  const dateDisplay = isPayrollToday ? (
    <span className="inline-flex items-center gap-2">
      {t.components.nextPayrollCard.today}
      <PartyPopper className="h-5 w-5 text-brand-highlight" aria-hidden="true" />
    </span>
  ) : (
    formattedDate
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
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6 relative z-10">
        {isLoading ? (
          <div className="animate-pulse flex-1 space-y-3" aria-hidden="true">
            <div className="h-4 w-32 rounded-lg bg-text-muted/20" />
            <div className="h-4 w-24 rounded-lg bg-text-muted/20" />
          </div>
        ) : (
          <>
            <div className="space-y-1">
              <p className="text-lg font-medium text-text-primary">
                {dateDisplay}
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
                  {payrollLabel}
                </span>
              </div>
            </div>
            <div className="text-right">
              <AnimatePresence mode="wait">
                {showNoPayoutPlaceholder ? (
                  <motion.div
                    key="payout-placeholder"
                    initial={{ opacity: 1 }}
                    exit={{ opacity: 0, x: 10 }}
                    transition={{ duration: 0.2 }}
                  >
                    <p className="text-2xl font-semibold tracking-tight text-text-primary">---</p>
                    <p className="text-xs">---</p>
                  </motion.div>
                ) : (
                  <motion.div
                    key="payout-value"
                    initial={{ opacity: 0, x: 10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: -10 }}
                    transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
                  >
                    <p className="text-2xl font-semibold tracking-tight text-text-primary">
                      {formatCurrency(netAmount)}
                    </p>
                    <p className="text-xs">{breakdown}</p>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </>
        )}
      </CardHeader>
    </Card>
  );
};

export default NextPayrollCard;
