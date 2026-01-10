"use client";

import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogFooter,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogCancel,
  AlertDialogAction,
} from "@/components/app/AlertDialog";
import type { ShiftWithComputations } from "@/lib/payroll";
import { useTranslations } from "@/lib/i18n/client";
import { getDateFormatter } from "@/lib/i18n/locale";
import { useMemo } from "react";

type SwipeDeleteConfirmDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  shift: ShiftWithComputations | null;
  onConfirm: () => void;
  isDeleting?: boolean;
};

function capitalize(input: string) {
  return input.charAt(0).toUpperCase() + input.slice(1);
}

export function SwipeDeleteConfirmDialog({
  open,
  onOpenChange,
  shift,
  onConfirm,
  isDeleting = false,
}: SwipeDeleteConfirmDialogProps) {
  const { t, locale } = useTranslations();

  const dateFormatter = useMemo(() => {
    return getDateFormatter(locale, {
      weekday: "long",
      day: "numeric",
      month: "long",
    });
  }, [locale]);

  const formattedDate = useMemo(() => {
    if (!shift) return "";
    const date = new Date(`${shift.shift_date}T00:00:00Z`);
    return capitalize(dateFormatter.format(date));
  }, [shift, dateFormatter]);

  const description = useMemo(() => {
    const template = t.pages.shifts.swipeActions?.deleteConfirmDescription ??
      "This will permanently delete the shift on {date}.";
    return template.replace("{date}", formattedDate);
  }, [t, formattedDate]);

  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent className="sm:rounded-3xl">
        <AlertDialogHeader>
          <AlertDialogTitle className="text-text-primary">
            {t.pages.shifts.swipeActions?.deleteConfirmTitle ?? "Delete shift?"}
          </AlertDialogTitle>
          <AlertDialogDescription className="text-text-secondary">
            {description}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter className="flex-row gap-3 sm:space-x-0">
          <AlertDialogCancel
            className="mt-0 flex-1 h-11 rounded-full border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900"
            disabled={isDeleting}
          >
            {t.pages.shifts.swipeActions?.cancelButton ?? "Cancel"}
          </AlertDialogCancel>
          <AlertDialogAction
            className="flex-1 h-11 rounded-full bg-red-500 text-white hover:bg-red-600 dark:bg-red-600 dark:hover:bg-red-700"
            onClick={(e) => {
              e.preventDefault();
              onConfirm();
            }}
            disabled={isDeleting}
          >
            {isDeleting ? (
              <span className="flex items-center gap-2">
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                {t.pages.shifts.swipeActions?.confirmButton ?? "Delete"}
              </span>
            ) : (
              t.pages.shifts.swipeActions?.confirmButton ?? "Delete"
            )}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
