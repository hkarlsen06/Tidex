import React from 'react';

interface TotalCardProps {
  /** The label to display (e.g., "Brutto", "Netto") */
  label: string;
  /** The main amount to display with currency */
  amount: string;
  /** Optional secondary information (e.g., tax info, hours worked) */
  secondaryInfo?: string;
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
 * This component displays the total earnings with an elevated card design,
 * featuring a gradient background, hover effects, and loading skeleton state.
 *
 * @example
 * ```tsx
 * <TotalCard
 *   label="Brutto"
 *   amount="15 234 kr"
 *   secondaryInfo="Netto: 11 425 kr (25% skatt)"
 * />
 * ```
 */
export const TotalCard: React.FC<TotalCardProps> = ({
  label,
  amount,
  secondaryInfo,
  isLoading = false,
  onClick,
  className = '',
}) => {
  return (
    <div
      className={`total-card ${className}`}
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
        <div className="total-skeleton skeleton" aria-hidden="true">
          <div className="skeleton-line"></div>
          <div className="skeleton-line"></div>
          <div className="skeleton-line"></div>
        </div>
      ) : (
        <>
          <div className="total-label">{label}</div>
          <div className="total-amount">{amount}</div>
          {secondaryInfo && (
            <div className="total-secondary-info">{secondaryInfo}</div>
          )}
        </>
      )}
    </div>
  );
};

export default TotalCard;
