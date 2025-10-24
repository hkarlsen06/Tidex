"use client";

import { createContext, useContext, useState, useCallback, useEffect, useMemo, ReactNode } from "react";

function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function serializeMonth(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-01`;
}

function deserializeMonth(iso: string): Date {
  const [year, month] = iso.split("-").map(Number);
  return new Date(year, month - 1, 1);
}

interface MonthContextType {
  selectedMonth: Date;
  setSelectedMonth: (month: Date) => void;
  goToPreviousMonth: () => void;
  goToNextMonth: () => void;
  direction: 'next' | 'previous' | null;
}

const MonthContext = createContext<MonthContextType | undefined>(undefined);

export function MonthProvider({ children }: { children: ReactNode }) {
  // Always start with current month to avoid SSR hydration mismatch
  const initialMonth = useMemo(() => startOfMonth(new Date()), []);
  const [selectedMonth, setSelectedMonthState] = useState<Date>(initialMonth);
  const [direction, setDirection] = useState<'next' | 'previous' | null>(null);

  // Restore from localStorage after mount (client-side only)
  useEffect(() => {
    const stored = localStorage.getItem("selectedMonth");
    if (stored) {
      try {
        const restoredMonth = deserializeMonth(stored);
        // Only update if different from initial month to avoid unnecessary re-renders
        if (restoredMonth.getTime() !== initialMonth.getTime()) {
          // Note: This setState is intentional to restore persisted state after SSR hydration
          // eslint-disable-next-line react-hooks/set-state-in-effect
          setSelectedMonthState(restoredMonth);
        }
      } catch (err) {
        console.warn("Failed to restore selectedMonth from localStorage:", err);
      }
    }
  }, [initialMonth]);

  // Sync to localStorage whenever selectedMonth changes
  useEffect(() => {
    localStorage.setItem("selectedMonth", serializeMonth(selectedMonth));
  }, [selectedMonth]);

  const setSelectedMonth = useCallback((month: Date) => {
    const normalized = startOfMonth(month);
    setSelectedMonthState(normalized);
    setDirection(null); // Reset direction for manual selection
  }, []);

  const goToPreviousMonth = useCallback(() => {
    setDirection('previous');
    setSelectedMonthState((prev) => {
      const newMonth = new Date(prev.getFullYear(), prev.getMonth() - 1, 1);
      return newMonth;
    });
  }, []);

  const goToNextMonth = useCallback(() => {
    setDirection('next');
    setSelectedMonthState((prev) => {
      const newMonth = new Date(prev.getFullYear(), prev.getMonth() + 1, 1);
      return newMonth;
    });
  }, []);

  return (
    <MonthContext.Provider
      value={{
        selectedMonth,
        setSelectedMonth,
        goToPreviousMonth,
        goToNextMonth,
        direction,
      }}
    >
      {children}
    </MonthContext.Provider>
  );
}

export function useMonth() {
  const context = useContext(MonthContext);
  if (context === undefined) {
    throw new Error("useMonth must be used within a MonthProvider");
  }
  return context;
}
