import React from 'react';
import { IconArrowDown, IconArrowUp } from '@tabler/icons-react';
import { Card, CardContent } from '@appui/Card';

interface TotalCardProps {
  total: string;
  percentageChange?: number;
  tillegg?: string;
  isLoading?: boolean;
  onClick?: () => void;
  className?: string;
}

export const TotalCard: React.FC<TotalCardProps> = ({
  total,
  percentageChange,
  tillegg,
  isLoading = false,
  onClick,
  className = '',
}) => {
  const cardClasses = [
    'relative overflow-hidden',
    'bg-surface-primary border-border-subtle',
    'shadow-app-lg',
    'total-card',
    'transition-all duration-300',
    onClick
      ? 'cursor-pointer hover:shadow-app-lg hover:bg-surface-secondary focus:outline-none focus:ring-2 focus:ring-brand-highlight focus:ring-offset-2'
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
              <div className="flex items-center justify-center gap-2">
                <ArrowIcon
                  className={`h-4 w-4 ${isPositive ? 'text-success' : 'text-error'}`}
                  stroke={2}
                />
                <span className={`font-semibold ${isPositive ? 'text-success' : 'text-error'}`}>
                  {Math.abs(percentageChange as number)}%
                </span>
              </div>
            )}
            <div className="mt-2 text-6xl font-bold text-brand-highlight">{total}</div>
            {tillegg && (
              <div className="mt-3 text-text-secondary">
                Tillegg: <span className="font-semibold text-text-primary">{tillegg}</span>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default TotalCard;
