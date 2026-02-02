'use client';

import { createContext, useContext, type ReactNode } from 'react';
import {
  getCurrencyConfig,
  type CurrencyDisplay,
} from '@/lib/currency/currencies';

interface CurrencyContextValue {
  /** The currency symbol/text to display (e.g., "$", "€", "kr", "NOK") */
  symbol: string;
  /** Whether symbol appears before or after the amount */
  display: CurrencyDisplay;
}

const CurrencyContext = createContext<CurrencyContextValue | null>(null);

interface CurrencyProviderProps {
  /** The currency value from user settings (stored symbol) */
  currency: string;
  children: ReactNode;
}

/**
 * Provides currency configuration to Client Components.
 * Wraps the app layout to make currency available everywhere.
 */
export function CurrencyProvider({ currency, children }: CurrencyProviderProps) {
  const config = getCurrencyConfig(currency);

  return (
    <CurrencyContext.Provider
      value={{
        symbol: config.value,
        display: config.display,
      }}
    >
      {children}
    </CurrencyContext.Provider>
  );
}

/**
 * Hook to access currency configuration.
 * Must be used within a CurrencyProvider.
 */
export function useCurrency(): CurrencyContextValue {
  const context = useContext(CurrencyContext);
  if (!context) {
    throw new Error('useCurrency must be used within a CurrencyProvider');
  }
  return context;
}
