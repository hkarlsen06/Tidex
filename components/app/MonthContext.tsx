"use client";

import { createContext, useContext, useEffect, useState, useCallback, ReactNode } from "react";

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
}

const MonthContext = createContext<MonthContextType | undefined>(undefined);

export function MonthProvider({ children }: { children: ReactNode }) {
  const [selectedMonth, setSelectedMonthState] = useState<Date>(() => startOfMonth(new Date()));

  // Restore from localStorage on mount (non-blocking)
  useEffect(() => {
    const stored = localStorage.getItem("selectedMonth");
    if (stored) {
      try {
        const restoredMonth = deserializeMonth(stored);
        setSelectedMonthState(restoredMonth);
      } catch (err) {
        // Invalid format, ignore and use default
        console.warn("Failed to restore selectedMonth from localStorage:", err);
      }
    }
  }, []);

  const setSelectedMonth = useCallback((month: Date) => {
    const normalized = startOfMonth(month);
    setSelectedMonthState(normalized);
    localStorage.setItem("selectedMonth", serializeMonth(normalized));
  }, []);

  const goToPreviousMonth = useCallback(() => {
    setSelectedMonthState((prev) => {
      const newMonth = new Date(prev.getFullYear(), prev.getMonth() - 1, 1);
      localStorage.setItem("selectedMonth", serializeMonth(newMonth));
      return newMonth;
    });
  }, []);

  const goToNextMonth = useCallback(() => {
    setSelectedMonthState((prev) => {
      const newMonth = new Date(prev.getFullYear(), prev.getMonth() + 1, 1);
      localStorage.setItem("selectedMonth", serializeMonth(newMonth));
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
