'use client';

import { useCallback } from 'react';
import {
  formatCurrency as formatCurrencyBase,
  type FormatCurrencyOptions,
} from '@/lib/formatters';
import { useCurrency } from '@/components/providers/CurrencyProvider';

/**
 * Hook that returns a formatCurrency function pre-configured with user's currency preference.
 *
 * Usage:
 * ```tsx
 * const formatCurrency = useFormatCurrency();
 * return <span>{formatCurrency(1234)}</span>; // "1 234 kr" or "$1,234" etc.
 * ```
 */
export function useFormatCurrency() {
  const { symbol, display } = useCurrency();

  const formatCurrency = useCallback(
    (value: number, options?: Partial<FormatCurrencyOptions>) => {
      return formatCurrencyBase(value, {
        currencySymbol: symbol,
        display,
        ...options,
      });
    },
    [symbol, display]
  );

  return formatCurrency;
}
