"use client";

import { createContext, useContext, useState, useCallback, useEffect, useMemo, useRef, ReactNode } from "react";

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
  /** Whether initial hydration from sessionStorage is complete */
  isHydrated: boolean;
}

const MonthContext = createContext<MonthContextType | undefined>(undefined);

export function MonthProvider({ children }: { children: ReactNode }) {
  // Always start with current month to avoid SSR hydration mismatch
  const initialMonth = useMemo(() => startOfMonth(new Date()), []);
  const [selectedMonth, setSelectedMonthState] = useState<Date>(initialMonth);
  const [direction, setDirection] = useState<'next' | 'previous' | null>(null);
  // Track whether sessionStorage restoration is complete to prevent animation flicker
  const [isHydrated, setIsHydrated] = useState(false);
  // Track the previous month to determine direction for programmatic changes
  const prevMonthRef = useRef<Date>(initialMonth);

  // Restore from sessionStorage after mount (client-side only)
  useEffect(() => {
    const stored = sessionStorage.getItem("selectedMonth");
    if (stored) {
      try {
        const restoredMonth = deserializeMonth(stored);
        // Only update if different from initial month to avoid unnecessary re-renders
        if (restoredMonth.getTime() !== initialMonth.getTime()) {
          // Note: This setState in effect is intentional - we restore persisted state
          // after SSR hydration to sync with sessionStorage. This only runs once on mount.
          setSelectedMonthState(restoredMonth);
          // Update ref to match restored month (no direction animation needed for restoration)
          prevMonthRef.current = restoredMonth;
        }
      } catch (err) {
        console.warn("Failed to restore selectedMonth from sessionStorage:", err);
      }
    }
    // Mark hydration complete after restoration attempt
    setIsHydrated(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Only run once on mount - initialMonth is stable from useMemo

  // Sync to sessionStorage whenever selectedMonth changes
  useEffect(() => {
    sessionStorage.setItem("selectedMonth", serializeMonth(selectedMonth));
  }, [selectedMonth]);

  const setSelectedMonth = useCallback((month: Date) => {
    const normalized = startOfMonth(month);
    // Determine direction based on comparison with previous month
    const prevTime = prevMonthRef.current.getTime();
    const newTime = normalized.getTime();
    if (newTime > prevTime) {
      setDirection('next');
    } else if (newTime < prevTime) {
      setDirection('previous');
    }
    // If same month, keep current direction (or null)
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
    <MonthContext.Provider
      value={{
        selectedMonth,
        setSelectedMonth,
        goToPreviousMonth,
        goToNextMonth,
        direction,
        isHydrated,
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
