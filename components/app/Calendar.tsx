"use client";

import * as React from "react";
import { DayPicker, type DayPickerProps } from "react-day-picker";
import { cn } from "@/lib/cn";

export type CalendarProps = DayPickerProps;

export function Calendar({ className, ...props }: CalendarProps) {
  return (
    <DayPicker
      className={cn("p-3", className)}
      {...props}
    />
  );
}

// Re-export types and utilities from react-day-picker
export type {
  DateRange,
  DayPickerProps,
  Matcher,
  SelectionState,
  Mode,
} from "react-day-picker";
