import React, { useEffect, useMemo, useState } from 'react';
import { IconArrowDown, IconArrowUp } from '@tabler/icons-react';
import { Card, CardContent } from '@appui/Card';

interface TotalCardProps {
  total: string;
  percentageChange?: number;
  tillegg?: string;
  isLoading?: boolean;
  onClick?: () => void;
  className?: string;
  taxDeductionEnabled?: boolean;
  grossBeforeTax?: string;
  earnedToDate?: string;
  animationDirection?: 'next' | 'previous' | null;
}

const ROTATION_INTERVAL_MS = 4500;

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
  tillegg,
  isLoading = false,
  onClick,
  className = '',
  taxDeductionEnabled = false,
  grossBeforeTax,
  earnedToDate,
  animationDirection = null,
}) => {
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

  const isPositive = percentageChange !== undefined && percentageChange >= 0;
  const hasChange = percentageChange !== undefined && percentageChange !== 0;
  const ArrowIcon = isPositive ? IconArrowUp : IconArrowDown;

  const handleKeyDown = onClick
    ? (event: React.KeyboardEvent<HTMLDivElement>) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          onClick();
        }
      }
    : undefined;

  const primaryContent = useMemo(() => {
    if (taxDeductionEnabled && grossBeforeTax) {
      return (
        <>
          <span className="font-semibold text-text-primary">{grossBeforeTax}</span> før skatt
        </>
      );
    }

    if (tillegg) {
      return (
        <>
          Tillegg: <span className="font-semibold text-text-primary">{tillegg}</span>
        </>
      );
    }

    return null;
  }, [taxDeductionEnabled, grossBeforeTax, tillegg]);

  const alternateContent = useMemo(() => {
    if (!earnedToDate) {
      return null;
    }

    return (
      <>
        <span className="font-semibold text-text-primary">{earnedToDate}</span> til nå
      </>
    );
  }, [earnedToDate]);

  const textOptions = useMemo(() => {
    const options: React.ReactNode[] = [];

    if (alternateContent) {
      options.push(alternateContent);
    }

    if (primaryContent) {
      options.push(primaryContent);
    }

    return options;
  }, [alternateContent, primaryContent]);

  const [displayIndex, setDisplayIndex] = useState(0);
  const [nextDisplayIndex, setNextDisplayIndex] = useState<number | null>(null);
  const [isTransitioning, setIsTransitioning] = useState(false);

  useEffect(() => {
    if (isLoading) {
      return;
    }

    setDisplayIndex(0);
    setNextDisplayIndex(null);
    setIsTransitioning(false);

    if (textOptions.length < 2) {
      return;
    }

    const intervalId = window.setInterval(() => {
      setDisplayIndex((currentIndex) => {
        const nextIndex = (currentIndex + 1) % textOptions.length;
        setNextDisplayIndex(nextIndex);
        setIsTransitioning(true);
        return currentIndex; // Don't update displayIndex yet - wait for animation
      });
    }, ROTATION_INTERVAL_MS);

    return () => window.clearInterval(intervalId);
  }, [textOptions, isLoading]);

  const handleExitAnimationEnd = () => {
    if (nextDisplayIndex !== null) {
      setDisplayIndex(nextDisplayIndex);
      setNextDisplayIndex(null);
    }
  };

  const handleEnterAnimationEnd = () => {
    setIsTransitioning(false);
  };

  return (
    <Card
      className={`${cardClasses} ${className}`.trim()}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={handleKeyDown}
    >
      <CardContent className="px-4 py-6">
        {isLoading ? (
          <div className="animate-pulse space-y-4 text-center" aria-hidden="true">
            <div className="mx-auto h-6 w-24 rounded-lg bg-text-muted/20" />
            <div className="mx-auto h-16 w-56 rounded-lg bg-text-muted/30" />
            <div className="mx-auto h-5 w-32 rounded-lg bg-text-muted/20" />
          </div>
        ) : (
          <div className="text-center">
            {hasChange && (
              <div
                key={`percentage-${percentageChange}`}
                className={`flex items-center justify-center gap-2 ${getAnimationClasses(animationDirection)}`}
              >
                <ArrowIcon
                  className={`h-6 w-6 ${isPositive ? 'text-success' : 'text-error'}`}
                  stroke={2}
                />
                <span className={`text-lg font-semibold ${isPositive ? 'text-success' : 'text-error'}`}>
                  {Math.abs(percentageChange as number)}%
                </span>
              </div>
            )}
            <div
              key={`total-${total}`}
              className={`mt-3 text-6xl font-bold text-brand-highlight ${getAnimationClasses(animationDirection)}`}
            >{total}</div>
            {textOptions.length > 0 ? (
              <div
                key={`subtitle-container-${total}`}
                className={`relative mx-auto mt-4 overflow-hidden ${getAnimationClasses(animationDirection)}`}
                style={{ width: '66.67%', minHeight: '1.75rem' }}
              >
                {/* Current text - exits when transitioning */}
                <div
                  className={`absolute inset-0 text-lg text-text-secondary ${
                    isTransitioning ? 'animate-[swipe-out-left_0.4s_ease-in-out]' : ''
                  }`}
                  style={{
                    opacity: isTransitioning && nextDisplayIndex !== null ? 0 : 1,
                    pointerEvents: isTransitioning && nextDisplayIndex !== null ? 'none' : 'auto',
                  }}
                  onAnimationEnd={handleExitAnimationEnd}
                >
                  {textOptions[displayIndex]}
                </div>

                {/* Next text - enters when transitioning */}
                {isTransitioning && nextDisplayIndex !== null && (
                  <div
                    className="absolute inset-0 text-lg text-text-secondary animate-[swipe-in-right_0.4s_ease-in-out]"
                    onAnimationEnd={handleEnterAnimationEnd}
                  >
                    {textOptions[nextDisplayIndex]}
                  </div>
                )}
              </div>
            ) : null}
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default TotalCard;
