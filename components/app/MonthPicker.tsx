"use client";

import { IconChevronLeft, IconChevronRight } from "@tabler/icons-react";

type MonthPickerProps = {
  month: Date;
  onPreviousMonth: () => void;
  onNextMonth: () => void;
};

function formatMonth(date: Date): string {
  return new Intl.DateTimeFormat("nb-NO", {
    month: "long",
  }).format(date);
}

export function MonthPicker({ month, onPreviousMonth, onNextMonth }: MonthPickerProps) {
  return (
    <div className="flex items-center gap-1">
      <button
        onClick={onPreviousMonth}
        className="flex h-7 w-7 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-none focus-visible:outline-none"
        aria-label="Forrige måned"
      >
        <IconChevronLeft size={18} />
      </button>
      <span className="w-24 text-center font-medium capitalize text-text-primary">
        {formatMonth(month)}
      </span>
      <button
        onClick={onNextMonth}
        className="flex h-7 w-7 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-none focus-visible:outline-none"
        aria-label="Neste måned"
      >
        <IconChevronRight size={18} />
      </button>
    </div>
  );
}
