'use client';

import React, { useEffect, useState, useRef } from 'react';
import { ArrowDown, ArrowUp, HelpCircle } from 'lucide-react';
import { useMotionValue, animate, motion, AnimatePresence } from 'framer-motion';
import { Card, CardContent } from '@/components/app/Card';
import { ClickTooltip } from '@/components/app/Tooltip';
import { useTranslations } from '@/lib/i18n/client';

interface TotalCardProps {
  total: string;
  percentageChange?: number;
  isLoading?: boolean;
  onClick?: () => void;
  className?: string;
  projectedTotal?: string;
  grossBeforeTax?: string;
  animationDirection?: 'next' | 'previous' | null;
  subtitlePlaceholder?: string;
  useZeroPlaceholder?: boolean;
  /** Shows a help icon with tooltip when total shows dashes but user has pending shifts */
  hasPendingShifts?: boolean;
}

// Helper to get animation classes based on direction
function getAnimationClasses(direction: 'next' | 'previous' | null): string {
  if (!direction) return '';

  if (direction === 'next') {
    // Going to next month: slide out right, slide in from right
    return 'animate-[slide-in-from-right_0.4s_ease-out]';
  } else {
    // Going to previous month: slide out left, slide in from left
    return 'animate-[slide-in-from-left_0.4s_ease-out]';
  }
}

// Extract numeric value from formatted string like "16 851 kr"
function extractNumber(value: string): number {
  const numericString = value.replace(/[^\d]/g, '');
  return parseInt(numericString, 10) || 0;
}

// Format number with spaces as thousand separators (Norwegian style)
function formatNumber(num: number, template: string): string {
  const suffix = template.replace(/[\d\s]/g, '').trim();
  const formatted = Math.round(num)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  return suffix ? `${formatted} ${suffix}` : formatted;
}

// Animated counter that counts up from 0 to target value
interface AnimatedCounterProps {
  value: string;
  className?: string;
  style?: React.CSSProperties;
}

function AnimatedCounter({ value, className, style }: AnimatedCounterProps) {
  const targetNumber = extractNumber(value);
  const count = useMotionValue(0);
  // Start at 0 (formatted) - animation begins immediately from 0 to target
  const [displayValue, setDisplayValue] = useState(() => formatNumber(0, value));
  const prevValueRef = useRef(value);
  const controlsRef = useRef<ReturnType<typeof animate> | null>(null);

  useEffect(() => {
    // Reset motion value when the target value changes
    if (value !== prevValueRef.current) {
      count.set(0);
      prevValueRef.current = value;
    }

    // Start animation immediately - requestAnimationFrame ensures DOM is ready
    const frameId = requestAnimationFrame(() => {
      controlsRef.current = animate(count, targetNumber, {
        duration: 1.2,
        ease: [0.25, 0.1, 0.25, 1],
        onUpdate: (latest) => {
          setDisplayValue(formatNumber(latest, value));
        },
      });
    });

    return () => {
      cancelAnimationFrame(frameId);
      controlsRef.current?.stop();
    };
  }, [value, targetNumber, count]);

  return (
    <span className={className} style={style}>
      {displayValue}
    </span>
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
  animationDirection = null,
  subtitlePlaceholder,
  useZeroPlaceholder = true,
  hasPendingShifts = false,
}) => {
  const { t } = useTranslations();
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

  const isPercentageReady = typeof percentageChange === 'number';
  const isPositive = isPercentageReady && (percentageChange as number) >= 0;
  const hasChange = isPercentageReady && (percentageChange as number) !== 0;
  const isZeroChange = isPercentageReady && (percentageChange as number) === 0;
  const ArrowIcon = isPositive ? ArrowUp : ArrowDown;

  const handleKeyDown = onClick
    ? (event: React.KeyboardEvent<HTMLDivElement>) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          onClick();
        }
      }
    : undefined;

  const displayTotal = useZeroPlaceholder && total === '0 kr' ? '---' : total;

  // Show help tooltip when displaying placeholder but user has pending shifts
  const showPendingShiftsHelp = displayTotal === '---' && hasPendingShifts;

  // Determine what to show in subtitle:
  // - If projected equals earned (no future shifts), show gross before tax (if tax enabled)
  // - Otherwise show projected total for the whole month
  const hasFutureShifts = projectedTotal && projectedTotal !== total && projectedTotal !== '0 kr';
  const showGrossBeforeTax = !hasFutureShifts && grossBeforeTax && grossBeforeTax !== '0 kr' && grossBeforeTax !== total;

  const subtitleContent = subtitlePlaceholder
    ? (
        <>{subtitlePlaceholder}</>
      )
    : hasFutureShifts
      ? (
        <>
          <span className="font-semibold text-text-primary">{projectedTotal}</span> {t.components.totalCard.wholeMonth}
        </>
      )
      : (
        <>
          <span className="font-semibold text-text-primary">{grossBeforeTax}</span> {t.components.totalCard.beforeTax}
        </>
      );

  const shouldShowSubtitle =
    Boolean(subtitlePlaceholder) || (!subtitlePlaceholder && (hasFutureShifts || showGrossBeforeTax));

  return (
    <Card
      className={`${cardClasses} ${className}`.trim()}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={handleKeyDown}
    >
      <CardContent className="py-6">
        {isLoading ? (
          <div className="animate-pulse space-y-4 text-center" aria-hidden="true">
            <div className="mx-auto h-6 w-24 rounded-lg bg-text-muted/20" />
            <div className="mx-auto h-16 w-56 rounded-lg bg-text-muted/30" />
            <div className="mx-auto h-5 w-32 rounded-lg bg-text-muted/20" />
          </div>
        ) : (
          <div className="text-center">
            {(hasChange || !isPercentageReady || isZeroChange) && (
              <div
                className={`flex items-center justify-center gap-2 ${getAnimationClasses(animationDirection)}`}
              >
                <AnimatePresence mode="wait">
                  {hasChange ? (
                    <motion.div
                      key="percentage-value"
                      initial={{ opacity: 0, y: -8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: 8 }}
                      transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
                      className="flex items-center gap-2"
                    >
                      <ArrowIcon
                        className={`h-6 w-6 ${isPositive ? 'text-brand-highlight' : 'text-text-secondary'}`}
                        strokeWidth={2}
                      />
                      <span className={`text-lg font-semibold ${isPositive ? 'text-brand-highlight' : 'text-text-secondary'}`}>
                        {Math.abs(percentageChange as number)}%
                      </span>
                    </motion.div>
                  ) : (
                    <motion.span
                      key="percentage-placeholder"
                      initial={{ opacity: 1 }}
                      exit={{ opacity: 0, y: -8 }}
                      transition={{ duration: 0.2 }}
                      className="text-lg font-semibold text-text-muted"
                    >
                      — — —
                    </motion.span>
                  )}
                </AnimatePresence>
              </div>
            )}
            <div
              key={`total-${total}`}
              className={`mt-3 relative flex items-center justify-center ${getAnimationClasses(animationDirection)}`}
            >
              {/*
                Container query container - font scales based on container width.
                Uses clamp() with cqi units: min 28px, preferred 22cqi, max 72px.
                No JavaScript measurement needed - browser handles it natively.
              */}
              <div
                className="w-full whitespace-nowrap text-center"
                style={{ containerType: 'inline-size', lineHeight: 1.1 }}
              >
                {displayTotal === '---' ? (
                  <span
                    className="font-bold text-brand-highlight"
                    style={{ fontSize: 'clamp(28px, 22cqi, 72px)' }}
                  >
                    {displayTotal}
                  </span>
                ) : (
                  <AnimatedCounter
                    value={displayTotal}
                    className="font-bold text-brand-highlight"
                    style={{ fontSize: 'clamp(28px, 22cqi, 72px)' }}
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
            {/* Always render subtitle row to prevent layout shift */}
            <div
              key={`subtitle-${total}`}
              className={`mt-4 text-lg text-text-secondary min-h-7 ${getAnimationClasses(animationDirection)}`}
            >
              <AnimatePresence mode="wait">
                {shouldShowSubtitle ? (
                  <motion.span
                    key="subtitle-value"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.3 }}
                  >
                    {subtitleContent}
                  </motion.span>
                ) : (
                  <motion.span
                    key="subtitle-placeholder"
                    initial={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.2 }}
                    className="text-text-muted"
                  >
                    — — —
                  </motion.span>
                )}
              </AnimatePresence>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default TotalCard;
