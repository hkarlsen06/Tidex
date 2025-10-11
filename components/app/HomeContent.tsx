"use client";

import { useState, useMemo } from "react";
import { TotalCard } from "@/components/app/TotalCard";
import { NextPayrollCard } from "@/components/app/NextPayrollCard";
import { MonthPicker } from "./MonthPicker";
import { ShiftCard } from "@/components/app/ShiftCard";
import ShiftDetails from "@/components/shifts/ShiftDetails";
import { ShiftWithComputations, UserSettings } from "@/lib/payroll";
import { getRelativeTime } from "@/lib/utils/relativeTime";

type HomeContentProps = {
  shifts: ShiftWithComputations[];
  settings: UserSettings;
};

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

function formatCurrency(value: number): string {
  return `${numberFormatter.format(Math.round(value))} kr`;
}

function calculateMonthData(
  shifts: ShiftWithComputations[],
  month: Date,
  settings: UserSettings
): {
  total: string;
  percentageChange?: number;
  tillegg: string;
  grossBeforeTax?: string;
  lastMonthNet?: number;
} {
  const targetYear = month.getFullYear();
  const targetMonth = month.getMonth() + 1;

  // Filter current month shifts
  const currentMonthShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return (
      shiftDate.getFullYear() === targetYear &&
      shiftDate.getMonth() + 1 === targetMonth
    );
  });

  // Filter last month shifts
  const lastMonthDate = new Date(targetYear, targetMonth - 2, 1);
  const lastMonthYear = lastMonthDate.getFullYear();
  const lastMonth = lastMonthDate.getMonth() + 1;

  const lastMonthShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return (
      shiftDate.getFullYear() === lastMonthYear &&
      shiftDate.getMonth() + 1 === lastMonth
    );
  });

  // Calculate totals
  const gross = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  const bonusPay = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.bonusPay || 0),
    0
  );

  const lastMonthGross = lastMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  // Calculate tax deduction if enabled
  const taxDeductionEnabled = settings.tax_deduction_enabled ?? false;
  const taxPercentage = Number(settings.tax_percentage) || 0;

  const netAmount = taxDeductionEnabled
    ? gross * (1 - taxPercentage / 100)
    : gross;

  const lastMonthNetAmount = taxDeductionEnabled
    ? lastMonthGross * (1 - taxPercentage / 100)
    : lastMonthGross;

  // Calculate percentage change based on display amount (net if tax enabled, gross otherwise)
  let percentageChange: number | undefined;
  const displayLastMonth = taxDeductionEnabled ? lastMonthNetAmount : lastMonthGross;
  const displayCurrent = taxDeductionEnabled ? netAmount : gross;

  if (displayLastMonth > 0) {
    percentageChange = Math.round(
      ((displayCurrent - displayLastMonth) / displayLastMonth) * 100
    );
  }

  return {
    total: formatCurrency(taxDeductionEnabled ? netAmount : gross),
    percentageChange,
    tillegg: formatCurrency(bonusPay),
    grossBeforeTax: taxDeductionEnabled ? formatCurrency(gross) : undefined,
    lastMonthNet: lastMonthNetAmount,
  };
}

function isCurrentMonth(date: Date): boolean {
  const now = new Date();
  return (
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth()
  );
}

export function HomeContent({ shifts, settings }: HomeContentProps) {
  const [month, setMonth] = useState(new Date());
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [selectedShift, setSelectedShift] = useState<ShiftWithComputations | null>(null);

  const data = useMemo(
    () => calculateMonthData(shifts, month, settings),
    [shifts, month, settings]
  );

  const payrollDay = Number(settings.payroll_day) || 1;

  // Calculate payroll data and date based on selected month
  const payrollData = useMemo(() => {
    const selectedMonthIsCurrent = isCurrentMonth(month);
    const today = new Date();

    let payrollMonthDate: Date;
    let earningsMonthDate: Date;

    if (selectedMonthIsCurrent) {
      // For current month: check if payday has passed
      if (today.getDate() >= payrollDay) {
        // Payday has passed - show next month's payroll paying for current month
        payrollMonthDate = new Date(
          today.getFullYear(),
          today.getMonth() + 1,
          1
        );
        earningsMonthDate = new Date(today.getFullYear(), today.getMonth(), 1);
      } else {
        // Payday hasn't passed - show current month's payroll paying for last month
        payrollMonthDate = new Date(today.getFullYear(), today.getMonth(), 1);
        earningsMonthDate = new Date(
          today.getFullYear(),
          today.getMonth() - 1,
          1
        );
      }
    } else {
      // For non-current months: show the selected month's payroll paying for previous month
      payrollMonthDate = new Date(month.getFullYear(), month.getMonth(), 1);
      earningsMonthDate = new Date(
        month.getFullYear(),
        month.getMonth() - 1,
        1
      );
    }

    // Get earnings from the earnings month
    const targetYear = earningsMonthDate.getFullYear();
    const targetMonth = earningsMonthDate.getMonth() + 1;

    const relevantShifts = shifts.filter((shift) => {
      const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
      return (
        shiftDate.getFullYear() === targetYear &&
        shiftDate.getMonth() + 1 === targetMonth
      );
    });

    const gross = relevantShifts.reduce(
      (sum, shift) => sum + (shift.computed.gross || 0),
      0
    );

    const basePay = relevantShifts.reduce(
      (sum, shift) => sum + (shift.computed.basePay || 0),
      0
    );

    const bonusPay = relevantShifts.reduce(
      (sum, shift) => sum + (shift.computed.bonusPay || 0),
      0
    );

    const taxDeductionEnabled = settings.tax_deduction_enabled ?? false;
    const taxPercentage = Number(settings.tax_percentage) || 0;
    const taxAmount = taxDeductionEnabled ? gross * (taxPercentage / 100) : 0;
    const netAmount = gross - taxAmount;

    return {
      netAmount,
      grossAmount: gross,
      baseAmount: basePay,
      bonusAmount: bonusPay,
      taxAmount,
      payrollMonthDate,
    };
  }, [month, settings, shifts, payrollDay]);

  // Find shift to display based on selected month
  const displayShift = useMemo(() => {
    if (shifts.length === 0) return null;

    const selectedMonthIsCurrent = isCurrentMonth(month);

    if (selectedMonthIsCurrent) {
      // For current month: show next upcoming shift or last shift
      const now = new Date();

      // Sort shifts by date and time
      const sortedShifts = [...shifts].sort((a, b) => {
        const dateCompare = a.shift_date.localeCompare(b.shift_date);
        if (dateCompare !== 0) return dateCompare;
        return a.start_time.localeCompare(b.start_time);
      });

      // Find next upcoming shift
      for (const shift of sortedShifts) {
        const [hours, minutes] = shift.start_time.split(':').map(Number);
        const shiftDateTime = new Date(shift.shift_date + 'T00:00:00');
        shiftDateTime.setHours(hours, minutes, 0, 0);

        if (shiftDateTime > now) {
          return shift;
        }
      }

      // No future shifts, return the last shift
      return sortedShifts[sortedShifts.length - 1];
    } else {
      // For other months: show shift with highest earnings in selected month
      const targetYear = month.getFullYear();
      const targetMonth = month.getMonth() + 1;

      const monthShifts = shifts.filter((shift) => {
        const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
        return (
          shiftDate.getFullYear() === targetYear &&
          shiftDate.getMonth() + 1 === targetMonth
        );
      });

      if (monthShifts.length === 0) return null;

      // Find maximum gross earnings
      const maxGross = Math.max(...monthShifts.map(s => s.computed.gross || 0));

      // Get all shifts with max earnings, then sort chronologically
      const topShifts = monthShifts
        .filter(s => s.computed.gross === maxGross)
        .sort((a, b) => {
          const dateCompare = a.shift_date.localeCompare(b.shift_date);
          if (dateCompare !== 0) return dateCompare;
          return a.start_time.localeCompare(b.start_time);
        });

      // Return the first one chronologically
      return topShifts[0];
    }
  }, [shifts, month]);

  const relativeTimeText = useMemo(() => {
    if (!displayShift) return null;

    const selectedMonthIsCurrent = isCurrentMonth(month);

    if (selectedMonthIsCurrent) {
      return getRelativeTime(displayShift.shift_date, displayShift.start_time);
    } else {
      return "Beste vakt";
    }
  }, [displayShift, month]);

  const goToPreviousMonth = () => {
    setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1));
  };

  const goToNextMonth = () => {
    setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1));
  };

  const taxDeductionEnabled = settings.tax_deduction_enabled ?? false;

  return (
    <>
      <div className="flex items-center justify-center h-full">
        <div className="flex flex-col gap-6 w-full max-w-md">
          {payrollDay && (
            <NextPayrollCard
              payrollDay={payrollDay}
              netAmount={payrollData.netAmount}
              grossAmount={payrollData.grossAmount}
              baseAmount={payrollData.baseAmount}
              bonusAmount={payrollData.bonusAmount}
              taxAmount={payrollData.taxAmount}
              taxEnabled={taxDeductionEnabled}
              selectedMonth={payrollData.payrollMonthDate}
            />
          )}
          <TotalCard
            total={data.total}
            percentageChange={data.percentageChange}
            tillegg={data.tillegg}
            taxDeductionEnabled={taxDeductionEnabled}
            grossBeforeTax={data.grossBeforeTax}
          />
          <div className="flex items-center justify-between">
            <MonthPicker
              month={month}
              onPreviousMonth={goToPreviousMonth}
              onNextMonth={goToNextMonth}
            />
            <span className="font-medium text-text-muted">{month.getFullYear()}</span>
          </div>
          {displayShift && (
            <div className="flex flex-col gap-2">
              <ShiftCard
                shift={displayShift}
                onClick={() => {
                  setSelectedShift(displayShift);
                  setDetailsOpen(true);
                }}
              />
              {relativeTimeText && (
                <p className="text-xs text-text-muted text-center">{relativeTimeText}</p>
              )}
            </div>
          )}
        </div>
      </div>
      <ShiftDetails
        isOpen={detailsOpen}
        shift={selectedShift}
        onClose={() => {
          setDetailsOpen(false);
          setSelectedShift(null);
        }}
      />
    </>
  );
}
