import { ShiftWithComputations } from "@/lib/payroll";

type ShiftCardProps = {
  shift: ShiftWithComputations;
};

const currency = new Intl.NumberFormat("nb-NO", {
  style: "currency",
  currency: "NOK",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const decimal = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const dateFormatter = new Intl.DateTimeFormat("nb-NO", {
  weekday: "long",
  year: "numeric",
  month: "long",
  day: "numeric",
});

function minutesToLabel(minutes: number) {
  const total = Math.max(0, Math.round(minutes));
  const dayOffset = Math.floor(total / (24 * 60));
  const inDay = total % (24 * 60);
  const hours = Math.floor(inDay / 60)
    .toString()
    .padStart(2, "0");
  const mins = (inDay % 60).toString().padStart(2, "0");
  return dayOffset > 0 ? `${hours}:${mins} (+${dayOffset}d)` : `${hours}:${mins}`;
}

function formatShiftDate(date: string) {
  const parsed = new Date(`${date}T00:00:00Z`);
  return dateFormatter.format(parsed);
}

function formatTimeRange(start: string, end: string) {
  return `${start} – ${end}`;
}

export function ShiftCard({ shift }: ShiftCardProps) {
  const { computed } = shift;
  const { basePay, bonusPay, gross, durationHours, paidHours, wagePeriods, breakAudit } = computed;

  const hasBonus = bonusPay > 0;

  return (
    <article className="w-full max-w-3xl rounded-3xl border border-border-strong bg-surface-primary/80 p-8 shadow-xl shadow-black/30 backdrop-blur">
      <header className="flex flex-col gap-6 md:flex-row md:items-start md:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-text-muted">Skift</p>
          <h2 className="mt-2 text-2xl font-semibold capitalize text-text-primary">
            {formatShiftDate(shift.shift_date)}
          </h2>
          <p className="mt-3 text-sm text-text-secondary">
            {formatTimeRange(shift.start_time, shift.end_time)} · {decimal.format(durationHours)} t brutto · {decimal.format(paidHours)} t betalt
          </p>
        </div>
        <div className="inline-flex min-w-[12rem] flex-col items-stretch justify-center rounded-2xl bg-gradient-to-br from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd p-[1px]">
          <div className="rounded-2xl bg-surface-primary/90 px-5 py-4 text-right text-text-primary">
            <p className="text-xs font-medium uppercase tracking-wide text-text-muted">Brutto utbetaling</p>
            <p className="text-3xl font-semibold leading-tight">{currency.format(gross)}</p>
            <p className="mt-1 text-xs text-text-secondary">
              {currency.format(basePay)} base{hasBonus ? ` + ${currency.format(bonusPay)} tillegg` : ""}
            </p>
          </div>
        </div>
      </header>

      <dl className="mt-8 grid gap-4 md:grid-cols-3">
        <div className="rounded-2xl bg-surface-secondary/60 p-4">
          <dt className="text-xs font-medium uppercase tracking-wide text-text-muted">Betalte timer</dt>
          <dd className="mt-2 text-2xl font-semibold text-text-primary">{decimal.format(paidHours)} t</dd>
          <dd className="mt-1 text-xs text-text-secondary">Av {decimal.format(durationHours)} t planlagt</dd>
        </div>
        <div className="rounded-2xl bg-surface-secondary/60 p-4">
          <dt className="text-xs font-medium uppercase tracking-wide text-text-muted">Pausefradrag</dt>
          <dd className="mt-2 text-2xl font-semibold text-text-primary">{decimal.format(breakAudit.deductedHours)} t</dd>
          <dd className="mt-1 text-xs text-text-secondary">Policy: {breakAudit.policy.replace(/_/g, " ")}</dd>
        </div>
        <div className="rounded-2xl bg-surface-secondary/60 p-4">
          <dt className="text-xs font-medium uppercase tracking-wide text-text-muted">Tillegg totalt</dt>
          <dd className="mt-2 text-2xl font-semibold text-text-primary">{hasBonus ? currency.format(bonusPay) : "—"}</dd>
          <dd className="mt-1 text-xs text-text-secondary">Grunnlønn {currency.format(basePay)}</dd>
        </div>
      </dl>

      <section className="mt-8 rounded-3xl border border-border-subtle/60 bg-surface-secondary/40 p-6">
        <header className="flex items-center justify-between gap-4">
          <div>
            <h3 className="text-sm font-semibold text-text-primary">Lønnsegmenter</h3>
            <p className="text-xs text-text-secondary">Bonus fordelt etter tidsrom</p>
          </div>
          <span className="rounded-full border border-brand-gradientMid/40 bg-brand-highlight/10 px-3 py-1 text-xs font-medium text-brand-highlight">
            {hasBonus ? `${currency.format(bonusPay)}` : "Ingen tillegg"}
          </span>
        </header>
        <ul className="mt-4 space-y-3">
          {wagePeriods.map((period, index) => {
            const key = `${period.fromMin}-${period.toMin}-${index}`;
            const fromLabel = minutesToLabel(period.fromMin);
            const toLabel = minutesToLabel(period.toMin);
            const hours = (period.toMin - period.fromMin) / 60;
            return (
              <li
                key={key}
                className="flex flex-wrap items-baseline justify-between gap-2 rounded-2xl bg-surface-primary/60 px-4 py-3 text-sm text-text-secondary"
              >
                <div className="flex items-center gap-3">
                  <span className="rounded-full border border-border-subtle/50 bg-surface-secondary/80 px-3 py-1 text-xs font-semibold uppercase tracking-wider text-text-muted">
                    {decimal.format(hours)} t
                  </span>
                  <span className="font-medium text-text-primary">
                    {fromLabel} – {toLabel}
                  </span>
                </div>
                <div className="text-right text-xs md:text-sm">
                  <p className="font-medium text-text-primary">
                    {currency.format(period.totalRate)} / t
                  </p>
                  <p>
                    {currency.format(period.baseRate)} grunn{period.bonusRate > 0 ? ` + ${currency.format(period.bonusRate)} tillegg` : ""}
                  </p>
                </div>
              </li>
            );
          })}
        </ul>
        {breakAudit.notes?.length ? (
          <div className="mt-5 rounded-2xl border border-border-subtle/60 bg-surface-primary/60 px-4 py-3 text-xs text-text-secondary">
            <p className="font-semibold text-text-primary">Notater</p>
            <ul className="mt-2 space-y-1">
              {breakAudit.notes.map((note, idx) => (
                <li key={idx} className="leading-relaxed">
                  • {note}
                </li>
              ))}
            </ul>
          </div>
        ) : null}
      </section>
    </article>
  );
}

export default ShiftCard;
