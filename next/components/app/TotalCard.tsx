'use client';

import React from 'react';
import { ArrowDown, ArrowUp, HelpCircle } from 'lucide-react';
import { SafeAnimateNumber } from '@/components/app/SafeAnimateNumber';
import { Card, CardContent } from '@/components/app/Card';
import { ClickTooltip } from '@/components/app/Tooltip';
import { useTranslations } from '@/lib/i18n/client';
import { useCurrency } from '@/components/providers/CurrencyProvider';

interface TotalCardProps {
  total: string;
  percentageChange?: number;
  isLoading?: boolean;
  onClick?: () => void;
  className?: string;
  projectedTotal?: string;
  grossBeforeTax?: string;
  /** @deprecated No longer used - animations are now number-based */
  animationDirection?: 'next' | 'previous' | null;
  subtitlePlaceholder?: string;
  useZeroPlaceholder?: boolean;
  /** Shows a help icon with tooltip when total shows dashes but user has pending shifts */
  hasPendingShifts?: boolean;
  /** Number of future/planned shifts for the projection */
  plannedShiftsCount?: number;
  /** Total number of shifts in the month (for fallback display) */
  totalShiftsCount?: number;
}

// Extract numeric value from formatted string like "16 851 kr"
function extractNumber(value: string): number {
  const numericString = value.replace(/[^\d]/g, '');
  return parseInt(numericString, 10) || 0;
}

// Animated currency display using motion-plus AnimateNumber
interface AnimatedCurrencyProps {
  value: string;
  className?: string;
  style?: React.CSSProperties;
  currencySymbol: string;
  currencyDisplay: 'prefix' | 'suffix';
}

function AnimatedCurrency({ value, className, style, currencySymbol, currencyDisplay }: AnimatedCurrencyProps) {
  const numericValue = extractNumber(value);
  const useCompact = numericValue > 99999;

  return (
    <SafeAnimateNumber
      layout={false}
      format={{
        maximumFractionDigits: 0,
        ...(useCompact && {
          notation: 'compact',
          compactDisplay: 'short',
        }),
      }}
      locales="nb-NO"
      prefix={currencyDisplay === 'prefix' ? currencySymbol : undefined}
      suffix={currencyDisplay === 'suffix' ? ` ${currencySymbol}` : undefined}
      className={className}
      style={style}
      transition={{
        visualDuration: 1.2,
        type: 'spring',
        bounce: 0.1,
      }}
      routePattern="/"
    >
      {numericValue}
    </SafeAnimateNumber>
  );
}

export const TotalCard: React.FC<TotalCardProps> = ({
  total,
  percentageChange,
  isLoading = false,
  onClick,
  className = '',
  projectedTotal,
  grossBeforeTax,
  animationDirection: _animationDirection = null,
  subtitlePlaceholder,
  useZeroPlaceholder = true,
  hasPendingShifts = false,
  plannedShiftsCount,
  totalShiftsCount,
}) => {
  const { t } = useTranslations();
  const { symbol: currencySymbol, display: currencyDisplay } = useCurrency();

  // Construct subtitle text for typewriter
  const subtitleText = (() => {
    const showDashes = (useZeroPlaceholder && (projectedTotal ? projectedTotal === '0 kr' : total === '0 kr'));
    if (showDashes) return '— — —';

    // Build subtitle value
    const hasFuture = projectedTotal && projectedTotal !== total && projectedTotal !== '0 kr';
    const displayTotalVal = useZeroPlaceholder && total === '0 kr' ? '— — —' : total;
    const showGross = !hasFuture && grossBeforeTax && grossBeforeTax !== '0 kr' && grossBeforeTax !== total;
    const hasRealEarned = hasFuture && displayTotalVal !== '— — —';
    const showPlanned = !showDashes && hasFuture && !hasRealEarned && plannedShiftsCount !== undefined && plannedShiftsCount > 0;
    const showCount = !showDashes && !hasRealEarned && !showGross && !showPlanned && totalShiftsCount !== undefined;

    const value = hasRealEarned ? displayTotalVal : showGross ? grossBeforeTax : showPlanned ? String(plannedShiftsCount) : showCount ? String(totalShiftsCount) : null;
    const label = hasRealEarned ? t.components.totalCard.earnedToDate
      : showGross ? t.components.totalCard.beforeTax
        : showPlanned ? (plannedShiftsCount === 1 ? t.components.totalCard.shiftPlanned : t.components.totalCard.shiftsPlanned)
          : showCount ? (totalShiftsCount === 1 ? t.components.totalCard.shift : t.components.totalCard.shifts)
            : null;

    if (value && label) return `${value} ${label}`;
    return null;
  })();

  const cardClasses = [
    'relative overflow-hidden',
    'bg-surface-primary border-border-subtle',
    'shadow-app dark:shadow-app-lg',
    'total-card',
    'transition-all duration-300',
    onClick
      ? 'cursor-pointer hover:shadow-app dark:hover:shadow-app-lg hover:bg-surface-secondary focus:outline-none focus:ring-2 focus:ring-brand-highlight focus:ring-offset-2'
      : '',
  ]
    .filter(Boolean)
    .join(' ');

  const isPercentageReady = typeof percentageChange === 'number' && isFinite(percentageChange);
  const isPositive = isPercentageReady && (percentageChange as number) >= 0;
  const hasChange = isPercentageReady && (percentageChange as number) !== 0;
  const showPercentageDash = !isPercentageReady || percentageChange === 0;
  const ArrowIcon = isPositive ? ArrowUp : ArrowDown;

  const handleKeyDown = onClick
    ? (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        onClick();
      }
    }
    : undefined;

  // Determine what to show:
  // - Main display (big blue number): projected total for the whole month
  // - Subtitle: earnings up to today (when there are future shifts) OR gross before tax (when no future shifts)
  const hasFutureShifts = projectedTotal && projectedTotal !== total && projectedTotal !== '0 kr';

  // Main display: use projected total if available, otherwise use total
  const mainDisplayValue = hasFutureShifts ? projectedTotal! : total;
  const displayMain = useZeroPlaceholder && mainDisplayValue === '0 kr' ? '— — —' : mainDisplayValue;

  // Show help tooltip when displaying placeholder but user has pending shifts
  const showPendingShiftsHelp = displayMain === '— — —' && hasPendingShifts;

  return (
    <Card
      className={`${cardClasses} ${className}`.trim()}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={handleKeyDown}
    >
      <CardContent className="pt-5 pb-4">
        {isLoading ? (
          <div className="animate-pulse space-y-4 text-center" aria-hidden="true">
            <div className="mx-auto h-6 w-24 rounded-lg bg-text-muted/20" />
            <div className="mx-auto h-16 w-56 rounded-lg bg-text-muted/30" />
            <div className="mx-auto h-5 w-32 rounded-lg bg-text-muted/20" />
          </div>
        ) : (
          <div className="flex flex-col items-center gap-1 text-center">
            {/* Percentage change indicator */}
            <div className="flex items-center justify-center">
              <span className={`inline-flex items-center gap-1 text-lg font-semibold ${hasChange ? (isPositive ? 'text-brand-highlight' : 'text-text-secondary') : 'text-text-muted'}`}>
                {hasChange && (
                  <ArrowIcon
                    className="h-5 w-5 shrink-0"
                    strokeWidth={2.5}
                  />
                )}
                {showPercentageDash ? (
                  <span>—</span>
                ) : (
                  <SafeAnimateNumber
                    layout={false}
                    suffix="%"
                    locales="nb-NO"
                    transition={{
                      visualDuration: 0.8,
                      type: 'spring',
                      bounce: 0.1,
                    }}
                    routePattern="/"
                  >
                    {Math.abs(percentageChange as number)}
                  </SafeAnimateNumber>
                )}
              </span>
            </div>
            {/* Main total display */}
            <div className="relative flex items-center justify-center w-full">
              {/*
                Container query container - font scales based on container width.
                Uses clamp() with cqi units: min 28px, preferred 22cqi, max 72px.
                No JavaScript measurement needed - browser handles it natively.
              */}
              <div
                className="w-full whitespace-nowrap text-center"
                style={{ containerType: 'inline-size', lineHeight: 1.1 }}
              >
                {displayMain === '— — —' ? (
                  <span
                    className="font-bold text-brand-highlight"
                    style={{ fontSize: 'clamp(28px, 22cqi, 72px)' }}
                  >
                    {displayMain}
                  </span>
                ) : (
                  <AnimatedCurrency
                    value={displayMain}
                    className="font-bold text-brand-highlight"
                    style={{ fontSize: 'clamp(28px, 22cqi, 72px)' }}
                    currencySymbol={currencySymbol}
                    currencyDisplay={currencyDisplay}
                  />
                )}
              </div>
              {showPendingShiftsHelp && (
                <div className="absolute left-[calc(50%+3.5rem)] top-1/2 -translate-y-1/4">
                  <ClickTooltip
                    trigger={
                      <HelpCircle
                        className="h-7 w-7 text-brand-highlight"
                        aria-hidden="true"
                      />
                    }
                    side="bottom"
                    ariaLabel={t.components.totalCard.pendingShiftsTooltip}
                    className="max-w-55 bg-surface-secondary border border-border-subtle shadow-lg px-3 py-2"
                  >
                    <p className="text-sm text-text-primary">{t.components.totalCard.pendingShiftsTooltip}</p>
                  </ClickTooltip>
                </div>
              )}
            </div>
            {/* Subtitle row - typewriter animation */}
            <div className="text-lg text-text-secondary min-h-7 relative flex items-baseline justify-center">
              {subtitlePlaceholder ? (
                <span>{subtitlePlaceholder}</span>
              ) : subtitleText ? (
                <span>{subtitleText}</span>
              ) : null}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default TotalCard;
