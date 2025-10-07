"use client";

import { IconPencil, IconTrash, IconClock } from "@tabler/icons-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@components/app/Dialog";
import { Button } from "@components/app/Button";
import type { ShiftWithComputations } from "@/lib/payroll";

export type ShiftDetailsProps = {
  isOpen: boolean;
  shift: ShiftWithComputations | null;
  onClose: () => void;
  onEdit?: (shiftId: string) => void;
  onDelete?: (shiftId: string) => void;
};

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

const hoursFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const dayFormatter = new Intl.DateTimeFormat("nb-NO", { weekday: "long" });
const dateFormatter = new Intl.DateTimeFormat("nb-NO", {
  day: "2-digit",
  month: "long",
});

function capitalize(input: string) {
  return input.charAt(0).toUpperCase() + input.slice(1);
}

function formatDate(dateISO: string) {
  const d = new Date(`${dateISO}T00:00:00Z`);
  const day = capitalize(dayFormatter.format(d));
  const label = capitalize(dateFormatter.format(d));
  return `${label} · ${day}`;
}

function formatTimeRange(start: string, end: string) {
  return `${start} – ${end}`;
}

function formatHours(value: number) {
  return `${hoursFormatter.format(value)}t`;
}

function formatCurrencyNOKInt(value: number) {
  return `${numberFormatter.format(Math.round(value))} kr`;
}

export function ShiftDetails({ isOpen, shift, onClose, onEdit, onDelete }: ShiftDetailsProps) {
  return (
    <Dialog open={isOpen} onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent className="sm:rounded-3xl max-w-[480px]">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-text-primary">
            <IconClock className="h-5 w-5 text-text-muted" aria-hidden />
            Vaktdetaljer
          </DialogTitle>
        </DialogHeader>

        {!shift ? (
          <div className="py-6 text-center text-text-secondary">Fant ikke vakten.</div>
        ) : (
          <div className="space-y-4 pt-2">
            <div className="flex items-center justify-between">
              <div className="text-sm text-text-secondary">Dato</div>
              <div className="text-base font-medium text-text-primary">
                {formatDate(shift.shift_date)}
              </div>
            </div>
            <div className="flex items-center justify-between">
              <div className="text-sm text-text-secondary">Tid</div>
              <div className="text-base font-medium text-text-primary">
                {formatTimeRange(shift.start_time, shift.end_time)}
              </div>
            </div>
            <div className="flex items-center justify-between">
              <div className="text-sm text-text-secondary">Betalte timer</div>
              <div className="text-base font-medium text-text-primary">
                {formatHours(shift.computed.paidHours)}
              </div>
            </div>

            <div className="h-px bg-border-subtle" />

            <div className="flex items-center justify-between">
              <div className="text-sm text-text-secondary">Grunnlønn</div>
              <div className="text-base font-medium text-text-primary">
                {formatCurrencyNOKInt(shift.computed.basePay)}
              </div>
            </div>
            {shift.computed.bonusPay > 0 && (
              <div className="flex items-center justify-between">
                <div className="text-sm text-text-secondary">Tillegg</div>
                <div className="text-base font-medium text-text-primary">
                  {formatCurrencyNOKInt(shift.computed.bonusPay)}
                </div>
              </div>
            )}

            <div className="flex items-center justify-between pt-2">
              <div className="text-sm text-text-secondary">Total</div>
              <div className="text-xl font-semibold text-text-primary">
                {formatCurrencyNOKInt(shift.computed.gross)}
              </div>
            </div>
          </div>
        )}

        <DialogFooter className="mt-4">
          {shift && (
            <div className="flex w-full items-center justify-between">
              <div className="flex items-center gap-2">
                <Button
                  variant="secondary"
                  onClick={() => shift && onEdit?.(shift.id)}
                  className="gap-2"
                >
                  <IconPencil className="h-4 w-4" />
                  Rediger
                </Button>
                <Button
                  variant="destructive"
                  onClick={() => shift && onDelete?.(shift.id)}
                  className="gap-2"
                >
                  <IconTrash className="h-4 w-4" />
                  Slett
                </Button>
              </div>
            </div>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default ShiftDetails;
