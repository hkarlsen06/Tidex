import React from 'react';
import { IconArrowUp, IconArrowDown } from '@tabler/icons-react';

interface TotalCardProps {
  /** The main total amount to display */
  total: string;
  /** Current month label (e.g., "Januar", "Februar") */
  monthLabel?: string;
  /** Percentage change from last month (e.g., "+12" or "-5") */
  percentageChange?: number;
  /** Tillegg (bonus pay) amount */
  tillegg?: string;
  /** Whether the card is in loading state */
  isLoading?: boolean;
  /** Optional click handler */
  onClick?: () => void;
  /** Optional class name for custom styling */
  className?: string;
}

/**
 * TotalCard - A hero card component for displaying wage totals
 *
 * This component displays the total earnings with percentage change and bonus pay.
 *
 * @example
 * ```tsx
 * <TotalCard
 *   total="15 234 kr"
 *   percentageChange={12}
 *   tillegg="2 450 kr"
 * />
 * ```
 */
export const TotalCard: React.FC<TotalCardProps> = ({
  total,
  monthLabel,
  percentageChange,
  tillegg,
  isLoading = false,
  onClick,
  className = '',
}) => {
  const baseClasses = `
    relative overflow-hidden rounded-3xl
    bg-surface-primary border border-border-subtle
    p-8 shadow-app-lg
    transition-all duration-300
    ${onClick ? 'cursor-pointer hover:shadow-app-lg hover:bg-surface-secondary focus:outline-none focus:ring-2 focus:ring-brand-highlight focus:ring-offset-2' : ''}
  `.trim();

  const isPositive = percentageChange !== undefined && percentageChange >= 0;
  const hasChange = percentageChange !== undefined && percentageChange !== 0;
  const ArrowIcon = isPositive ? IconArrowUp : IconArrowDown;

  return (
    <div
      className={`${baseClasses} ${className}`}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onClick();
        }
      } : undefined}
    >
      {isLoading ? (
        <div className="animate-pulse space-y-4 text-center" aria-hidden="true">
          <div className="mx-auto h-6 w-24 rounded-lg bg-text-muted/20"></div>
          <div className="mx-auto h-16 w-56 rounded-lg bg-text-muted/30"></div>
          <div className="mx-auto h-5 w-32 rounded-lg bg-text-muted/20"></div>
        </div>
      ) : (
        <div className="text-center">
          {monthLabel && (
            <div className="flex items-center justify-center gap-2 text-sm">
              <span className="font-medium text-text-secondary">{monthLabel}</span>
              {hasChange && (
                <>
                  <ArrowIcon
                    className={`h-4 w-4 ${isPositive ? 'text-success' : 'text-error'}`}
                    stroke={2}
                  />
                  <span className={`font-semibold ${isPositive ? 'text-success' : 'text-error'}`}>
                    {isPositive ? '+' : ''}{percentageChange}%
                  </span>
                </>
              )}
            </div>
          )}
          <div className="mt-2 text-6xl font-bold text-brand-highlight">
            {total}
          </div>
          {tillegg && (
            <div className="mt-3 text-sm text-text-secondary">
              Tillegg: <span className="font-semibold text-text-primary">{tillegg}</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default TotalCard;
