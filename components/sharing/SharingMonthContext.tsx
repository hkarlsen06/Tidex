"use client";

import { createContext, useContext, useState, useCallback, useMemo, useRef, ReactNode } from "react";

function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

interface SharingMonthContextType {
  selectedMonth: Date;
  setSelectedMonth: (month: Date) => void;
  goToPreviousMonth: () => void;
  goToNextMonth: () => void;
  direction: 'next' | 'previous' | null;
  /** Always true for sharing - no sessionStorage hydration needed */
  isHydrated: boolean;
}

const SharingMonthContext = createContext<SharingMonthContextType | undefined>(undefined);

/**
 * Isolated MonthProvider for the sharing page.
 * Unlike the main MonthProvider, this does NOT sync to sessionStorage
 * and maintains completely independent state to prevent AnimatePresence
 * conflicts during route transitions.
 */
export function SharingMonthProvider({ children }: { children: ReactNode }) {
  // Always start with current month
  const initialMonth = useMemo(() => startOfMonth(new Date()), []);
  const [selectedMonth, setSelectedMonthState] = useState<Date>(initialMonth);
  const [direction, setDirection] = useState<'next' | 'previous' | null>(null);
  const prevMonthRef = useRef<Date>(initialMonth);

  const setSelectedMonth = useCallback((month: Date) => {
    const normalized = startOfMonth(month);
    const prevTime = prevMonthRef.current.getTime();
    const newTime = normalized.getTime();
    if (newTime > prevTime) {
      setDirection('next');
    } else if (newTime < prevTime) {
      setDirection('previous');
    }
    prevMonthRef.current = normalized;
    setSelectedMonthState(normalized);
  }, []);

  const goToPreviousMonth = useCallback(() => {
    setDirection('previous');
    setSelectedMonthState((prev) => {
      const newMonth = new Date(prev.getFullYear(), prev.getMonth() - 1, 1);
      prevMonthRef.current = newMonth;
      return newMonth;
    });
  }, []);

  const goToNextMonth = useCallback(() => {
    setDirection('next');
    setSelectedMonthState((prev) => {
      const newMonth = new Date(prev.getFullYear(), prev.getMonth() + 1, 1);
      prevMonthRef.current = newMonth;
      return newMonth;
    });
  }, []);

  return (
    <SharingMonthContext.Provider
      value={{
        selectedMonth,
        setSelectedMonth,
        goToPreviousMonth,
        goToNextMonth,
        direction,
        isHydrated: true, // No sessionStorage, always hydrated
      }}
    >
      {children}
    </SharingMonthContext.Provider>
  );
}

export function useSharingMonth() {
  const context = useContext(SharingMonthContext);
  if (context === undefined) {
    throw new Error("useSharingMonth must be used within a SharingMonthProvider");
  }
  return context;
}
