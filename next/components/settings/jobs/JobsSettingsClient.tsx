'use client';

import { useMemo, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/app/Button';
import { Card } from '@/components/app/Card';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/app/Dialog';
import { Input } from '@/components/app/Input';
import { Label } from '@/components/app/Label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/app/Select';
import { useTranslations } from '@/lib/i18n/client';
import type { Job } from '@/lib/payroll';
import {
  archiveJobAction,
  createJobAction,
  deleteJobAction,
  reorderJobAction,
  restoreJobAction,
  setDefaultJobAction,
  updateJobAction,
} from '@/app/[locale]/(app)/settings/jobs/_actions/jobs';

type Props = {
  jobs: Job[];
};

type FormState = {
  name: string;
  color: string;
  payrollDay: string;
  monthlyGoal: string;
  halfTaxMonth: string;
};

type ActionResponse = { success: true; data?: unknown } | { error: string };

const EMPTY_FORM: FormState = {
  name: '',
  color: '#3b82f6',
  payrollDay: '15',
  monthlyGoal: '20000',
  halfTaxMonth: 'none',
};

function toFormState(job?: Job | null): FormState {
  if (!job) return EMPTY_FORM;
  return {
    name: job.name ?? '',
    color: job.color ?? '#3b82f6',
    payrollDay: job.payroll_day?.toString() ?? '15',
    monthlyGoal: job.monthly_goal?.toString() ?? '20000',
    halfTaxMonth: job.half_tax_month?.toString() ?? 'none',
  };
}

export function JobsSettingsClient({ jobs }: Props) {
  const { t, locale } = useTranslations();
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [isOpen, setIsOpen] = useState(false);
  const [editingJob, setEditingJob] = useState<Job | null>(null);
  const [form, setForm] = useState<FormState>(EMPTY_FORM);

  const sortedJobs = useMemo(
    () => [...jobs].sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0)),
    [jobs]
  );
  const activeJobs = useMemo(
    () => sortedJobs.filter((job) => !job.archived_at && !job.deleted_at),
    [sortedJobs]
  );
  const archivedJobs = useMemo(
    () => sortedJobs.filter((job) => !!job.archived_at && !job.deleted_at),
    [sortedJobs]
  );

  const handleOpenCreate = () => {
    setEditingJob(null);
    setForm(EMPTY_FORM);
    setError(null);
    setIsOpen(true);
  };

  const handleOpenEdit = (job: Job) => {
    setEditingJob(job);
    setForm(toFormState(job));
    setError(null);
    setIsOpen(true);
  };

  const runAction = (fn: () => Promise<ActionResponse>) => {
    startTransition(async () => {
      setError(null);
      const result = await fn();
      if ('error' in result) {
        setError(result.error);
        return;
      }
      router.refresh();
    });
  };

  const handleSave = () => {
    const name = form.name.trim();
    if (!name) {
      setError(locale.startsWith('no') ? 'Jobbnavn kan ikke være tomt.' : 'Job name cannot be empty.');
      return;
    }

    const payrollDayValue = Number.parseInt(form.payrollDay, 10);
    const monthlyGoalValue = Number.parseFloat(form.monthlyGoal);
    const halfTaxMonthValue = form.halfTaxMonth === 'none' ? null : Number.parseInt(form.halfTaxMonth, 10);

    const payload = {
      name,
      color: form.color.trim() || null,
      payroll_day: Number.isFinite(payrollDayValue) ? payrollDayValue : null,
      monthly_goal: Number.isFinite(monthlyGoalValue) ? monthlyGoalValue : null,
      half_tax_month: Number.isFinite(halfTaxMonthValue ?? NaN) ? halfTaxMonthValue : null,
    };

    startTransition(async () => {
      setError(null);
      const result = editingJob
        ? await updateJobAction(editingJob.id, payload)
        : await createJobAction(payload);

      if ('error' in result) {
        setError(result.error);
        return;
      }

      setIsOpen(false);
      setEditingJob(null);
      setForm(EMPTY_FORM);
      router.refresh();
    });
  };

  const confirmAndRun = (question: string, fn: () => Promise<ActionResponse>) => {
    if (!window.confirm(question)) return;
    runAction(fn);
  };

  const labelDefault = locale.startsWith('no') ? 'Standard' : 'Default';
  const labelArchived = locale.startsWith('no') ? 'Arkivert' : 'Archived';
  const labelJobs = locale.startsWith('no') ? 'Jobber' : 'Jobs';
  const labelHalfTaxOff = locale.startsWith('no') ? 'Av' : 'Off';
  const labelDelete = locale.startsWith('no') ? 'Slett' : 'Delete';
  const labelRestore = locale.startsWith('no') ? 'Gjenopprett' : 'Restore';
  const labelArchive = locale.startsWith('no') ? 'Arkiver' : 'Archive';
  const labelSetDefault = locale.startsWith('no') ? 'Sett som standard' : 'Set default';
  const labelMoveUp = locale.startsWith('no') ? 'Opp' : 'Up';
  const labelMoveDown = locale.startsWith('no') ? 'Ned' : 'Down';
  const labelEdit = locale.startsWith('no') ? 'Rediger' : 'Edit';

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-text-secondary">
          {activeJobs.length} {labelJobs.toLowerCase()}
        </p>
        <Button onClick={handleOpenCreate} disabled={pending}>
          {t.pages.settings.jobs.add}
        </Button>
      </div>

      {activeJobs.map((job, index) => (
        <Card key={job.id} className="p-4">
          <div className="space-y-3">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span
                    className="inline-block h-3 w-3 rounded-full border border-border-subtle"
                    style={{ backgroundColor: job.color ?? '#64748b' }}
                  />
                  <p className="truncate font-semibold text-text-primary">{job.name}</p>
                  {job.is_default && (
                    <span className="rounded-full bg-surface-secondary px-2 py-0.5 text-xs font-medium text-text-secondary">
                      {labelDefault}
                    </span>
                  )}
                </div>
                <p className="mt-1 text-sm text-text-secondary">
                  {t.pages.settings.pay.other.paymentDayLabel}: {job.payroll_day ?? '-'} ·{' '}
                  {t.pages.settings.pay.other.monthlyGoalLabel}: {job.monthly_goal ?? '-'} kr
                  {' · '}
                  {t.pages.settings.pay.tax.halfTaxMonthLabel}:{' '}
                  {job.half_tax_month ?? labelHalfTaxOff}
                </p>
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              {!job.is_default && (
                <Button
                  variant="outline"
                  size="sm"
                  disabled={pending}
                  onClick={() => runAction(() => setDefaultJobAction(job.id))}
                >
                  {labelSetDefault}
                </Button>
              )}
              <Button variant="outline" size="sm" disabled={pending} onClick={() => handleOpenEdit(job)}>
                {labelEdit}
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={pending || index === 0}
                onClick={() => runAction(() => reorderJobAction(job.id, 'up'))}
              >
                {labelMoveUp}
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={pending || index === activeJobs.length - 1}
                onClick={() => runAction(() => reorderJobAction(job.id, 'down'))}
              >
                {labelMoveDown}
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={pending}
                onClick={() =>
                  confirmAndRun(
                    locale.startsWith('no')
                      ? 'Arkivere denne jobben?'
                      : 'Archive this job?',
                    () => archiveJobAction(job.id)
                  )
                }
              >
                {labelArchive}
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={pending}
                onClick={() =>
                  confirmAndRun(
                    locale.startsWith('no')
                      ? 'Slette denne jobben?'
                      : 'Delete this job?',
                    () => deleteJobAction(job.id)
                  )
                }
              >
                {labelDelete}
              </Button>
            </div>
          </div>
        </Card>
      ))}

      {archivedJobs.length > 0 && (
        <div className="space-y-3 pt-2">
          <h3 className="text-sm font-semibold uppercase tracking-widest text-text-muted">{labelArchived}</h3>
          {archivedJobs.map((job) => (
            <Card key={job.id} className="p-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-2">
                  <span
                    className="inline-block h-3 w-3 rounded-full border border-border-subtle"
                    style={{ backgroundColor: job.color ?? '#64748b' }}
                  />
                  <p className="font-medium text-text-primary">{job.name}</p>
                </div>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={pending}
                    onClick={() => runAction(() => restoreJobAction(job.id))}
                  >
                    {labelRestore}
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={pending}
                    onClick={() =>
                      confirmAndRun(
                        locale.startsWith('no')
                          ? 'Slette denne jobben?'
                          : 'Delete this job?',
                        () => deleteJobAction(job.id)
                      )
                    }
                  >
                    {labelDelete}
                  </Button>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={isOpen} onOpenChange={setIsOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {editingJob ? t.pages.settings.jobs.editTitle : t.pages.settings.jobs.createTitle}
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="job-name">{t.pages.settings.jobs.nameLabel}</Label>
              <Input
                id="job-name"
                value={form.name}
                onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
                maxLength={100}
                disabled={pending}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="job-color">{t.pages.settings.jobs.colorLabel}</Label>
              <Input
                id="job-color"
                type="color"
                value={form.color}
                onChange={(event) => setForm((prev) => ({ ...prev, color: event.target.value }))}
                disabled={pending}
              />
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="job-payroll-day">{t.pages.settings.pay.other.paymentDayLabel}</Label>
                <Input
                  id="job-payroll-day"
                  type="number"
                  min={1}
                  max={31}
                  value={form.payrollDay}
                  onChange={(event) => setForm((prev) => ({ ...prev, payrollDay: event.target.value }))}
                  disabled={pending}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="job-monthly-goal">{t.pages.settings.pay.other.monthlyGoalLabel}</Label>
                <Input
                  id="job-monthly-goal"
                  type="number"
                  min={0}
                  value={form.monthlyGoal}
                  onChange={(event) => setForm((prev) => ({ ...prev, monthlyGoal: event.target.value }))}
                  disabled={pending}
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="job-half-tax">{t.pages.settings.pay.tax.halfTaxMonthLabel}</Label>
              <Select
                value={form.halfTaxMonth}
                onValueChange={(value) => setForm((prev) => ({ ...prev, halfTaxMonth: value }))}
                disabled={pending}
              >
                <SelectTrigger id="job-half-tax">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">{t.pages.settings.pay.tax.halfTaxMonthOff}</SelectItem>
                  <SelectItem value="11">{t.pages.settings.pay.tax.halfTaxMonthNovember}</SelectItem>
                  <SelectItem value="12">{t.pages.settings.pay.tax.halfTaxMonthDecember}</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {error && <p className="text-sm font-medium text-error">{error}</p>}
          </div>

          <DialogFooter>
            <div className="flex w-full flex-wrap justify-end gap-2">
              <Button
                variant="outline"
                disabled={pending}
                onClick={() => {
                  setIsOpen(false);
                  setEditingJob(null);
                  setForm(EMPTY_FORM);
                  setError(null);
                }}
              >
                {t.common.cancel}
              </Button>
              <Button disabled={pending} onClick={handleSave}>
                {editingJob ? t.common.save : t.pages.settings.jobs.add}
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
