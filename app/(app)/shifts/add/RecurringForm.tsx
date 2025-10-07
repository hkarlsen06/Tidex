"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Input } from "@/components/app/Input";
import { Button } from "@/components/app/Button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/app/Dialog";
import { createShifts } from "./actions";

function toLocalISODate(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function parseISODate(s: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const [y, m, d] = s.split("-").map((n) => parseInt(n, 10));
  const dt = new Date(y, m - 1, d);
  // Basic guard that the date stayed correct
  if (dt.getFullYear() !== y || dt.getMonth() !== m - 1 || dt.getDate() !== d) return null;
  return dt;
}

export default function RecurringForm() {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  const [startDate, setStartDate] = useState<string>(() => toLocalISODate(new Date()));
  const [endDate, setEndDate] = useState<string>(() => toLocalISODate(new Date(new Date().setMonth(new Date().getMonth() + 1))));
  const [intervalWeeks, setIntervalWeeks] = useState<number>(1);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");

  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const dates = useMemo(() => {
    const out: string[] = [];
    const s = parseISODate(startDate);
    const e = parseISODate(endDate);
    const n = Math.max(1, Math.floor(intervalWeeks || 1));
    if (!s || !e || s > e) return out;
    let cur = new Date(s);
    while (cur <= e) {
      out.push(toLocalISODate(cur));
      cur = new Date(cur);
      cur.setDate(cur.getDate() + 7 * n);
    }
    return out;
  }, [startDate, endDate, intervalWeeks]);

  const canSubmit = dates.length > 0 && /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end);

  const onPreview = () => {
    if (!canSubmit) return;
    setError(null);
    setOpen(true);
  };

  const onConfirm = () => {
    setError(null);
    startTransition(async () => {
      try {
        const sid = crypto.randomUUID();
        await createShifts({ dates, start, end, seriesId: sid });
        router.push("/shifts");
        router.refresh();
      } catch (e: any) {
        setError(e?.message || "Kunne ikke lagre skift");
      } finally {
        setOpen(false);
      }
    });
  };

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3">
        <label className="space-y-1">
          <span className="text-sm text-text-secondary">Startdato</span>
          <Input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
        </label>
        <label className="space-y-1">
          <span className="text-sm text-text-secondary">Sluttdato</span>
          <Input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
        </label>
      </div>

      <label className="space-y-1">
        <span className="text-sm text-text-secondary">Hver N. uke</span>
        <Input
          type="number"
          min={1}
          value={intervalWeeks}
          onChange={(e) => setIntervalWeeks(Number(e.target.value) || 1)}
        />
      </label>

      <div className="grid grid-cols-2 gap-3">
        <label className="space-y-1">
          <span className="text-sm text-text-secondary">Start</span>
          <Input type="time" step={900} value={start} onChange={(e) => setStart(e.target.value)} />
        </label>
        <label className="space-y-1">
          <span className="text-sm text-text-secondary">Slutt</span>
          <Input type="time" step={900} value={end} onChange={(e) => setEnd(e.target.value)} />
        </label>
      </div>

      {error && (
        <div className="text-sm text-error" role="alert">
          {error}
        </div>
      )}

      <Button onClick={onPreview} disabled={!canSubmit} loading={pending}>
        Opprett {dates.length || 0} skift
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Bekreft serie</DialogTitle>
            <DialogDescription>
              Du er i ferd med å opprette {dates.length} skift.
            </DialogDescription>
          </DialogHeader>
          <div className="max-h-48 overflow-auto text-sm">
            {dates.slice(0, 20).map((d) => (
              <div key={d} className="py-0.5">
                {d} {start}–{end}
              </div>
            ))}
            {dates.length > 20 && (
              <div className="text-text-muted">…og {dates.length - 20} til</div>
            )}
          </div>
          <DialogFooter>
            <Button type="button" onClick={() => setOpen(false)}>
              Avbryt
            </Button>
            <Button type="button" onClick={onConfirm} loading={pending}>
              Bekreft
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
