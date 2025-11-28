import React, { useEffect, useRef, useLayoutEffect, useCallback } from 'react';
import { ArrowDown, ArrowUp } from 'lucide-react';
import { Card, CardContent } from '@/components/app/Card';
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
}

// Maximum font size in pixels for the total amount
const MAX_FONT_SIZE_PX = 72;
// Minimum font size in pixels (fallback floor)
const MIN_FONT_SIZE_PX = 28;

/**
 * Helper to calculate optimal font size via binary search
 * Measures text width against container width
 */
function calculateOptimalFontSize(
  container: HTMLElement,
  text: string,
  maxFontSize: number,
  minFontSize: number
): number {
  const measureEl = document.createElement('span');
  measureEl.style.cssText = `
    position: absolute;
    visibility: hidden;
    white-space: nowrap;
    font-weight: 700;
    font-family: inherit;
  `;
  measureEl.textContent = text;
  document.body.appendChild(measureEl);

  const containerWidth = container.offsetWidth;
  let low = minFontSize;
  let high = maxFontSize;
  let optimal = minFontSize;

  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    measureEl.style.fontSize = `${mid}px`;

    if (measureEl.offsetWidth <= containerWidth) {
      optimal = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  document.body.removeChild(measureEl);
  return optimal;
}

/**
 * Hook to auto-scale font size to fit container width.
 * Uses direct DOM manipulation to avoid React setState warnings in effects.
 * Returns refs that must be attached to container and text elements.
 */
function useAutoScaleFont(
  text: string,
  maxFontSize: number = MAX_FONT_SIZE_PX,
  minFontSize: number = MIN_FONT_SIZE_PX
): {
  containerRef: React.RefObject<HTMLDivElement | null>;
  textRef: React.RefObject<HTMLSpanElement | null>;
} {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const textRef = useRef<HTMLSpanElement | null>(null);

  // Function to update font size directly on the DOM element
  const updateFontSize = useCallback(() => {
    const container = containerRef.current;
    const textEl = textRef.current;
    if (!container || !textEl) return;

    const optimal = calculateOptimalFontSize(container, text, maxFontSize, minFontSize);
    textEl.style.fontSize = `${optimal}px`;
  }, [text, maxFontSize, minFontSize]);

  // Initial measurement on mount and when text changes
  useLayoutEffect(() => {
    updateFontSize();
  }, [updateFontSize]);

  // Handle resize via ResizeObserver
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const resizeObserver = new ResizeObserver(() => {
      updateFontSize();
    });

    resizeObserver.observe(container);
    return () => resizeObserver.disconnect();
  }, [updateFontSize]);

  return { containerRef, textRef };
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

  // Auto-scale font size for the total amount
  const displayTotal = useZeroPlaceholder && total === '0 kr' ? '---' : total;
  const { containerRef: totalContainerRef, textRef: totalTextRef } = useAutoScaleFont(displayTotal);

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
                key={`percentage-${isPercentageReady ? percentageChange : 'placeholder'}`}
                className={`flex items-center justify-center gap-2 ${getAnimationClasses(animationDirection)}`}
              >
                {hasChange ? (
                  <>
                    <ArrowIcon
                      className={`h-6 w-6 ${isPositive ? 'text-brand-highlight' : 'text-text-secondary'}`}
                      strokeWidth={2}
                    />
                    <span className={`text-lg font-semibold ${isPositive ? 'text-brand-highlight' : 'text-text-secondary'}`}>
                      {Math.abs(percentageChange as number)}%
                    </span>
                  </>
                ) : (
                  <span className="text-lg font-semibold text-text-muted">— — —</span>
                )}
              </div>
            )}
            <div
              ref={totalContainerRef}
              key={`total-${total}`}
              className={`mt-3 whitespace-nowrap ${getAnimationClasses(animationDirection)}`}
              style={{ lineHeight: 1.1 }}
            >
              <span
                ref={totalTextRef}
                className="font-bold text-brand-highlight"
                style={{ fontSize: `${MAX_FONT_SIZE_PX}px` }}
              >
                {displayTotal}
              </span>
            </div>
            {shouldShowSubtitle && (
              <div
                key={`subtitle-${total}`}
                className={`mt-4 text-lg text-text-secondary ${getAnimationClasses(animationDirection)}`}
              >
                {subtitleContent}
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default TotalCard;
