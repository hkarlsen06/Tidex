'use client';

import { useEffect, useState } from 'react';
import AddShiftForm from './AddShiftForm';
import type { UserSettings, SupplementRule, WageSnapshot } from '@/lib/payroll';
import { ScrollablePageWrapper } from '@/components/app/ScrollablePageWrapper';

type ExistingShift = {
  shift_date: string;
  start_time: string;
  end_time: string;
};

type AddShiftData = {
  existingShifts: ExistingShift[];
  userSettings: UserSettings;
  presetRules: SupplementRule[];
  wageSnapshots: WageSnapshot[];
};

type Props = {
  initialData: AddShiftData;
};

/**
 * Wrapper for AddShiftForm that handles offline scenarios
 * Falls back to API route when server-side rendering fails (offline)
 */
export function AddShiftFormWrapper({ initialData }: Props) {
  // Check if we need to fetch data (server-side loading failed)
  // userSettings is empty object {} when server-side loading fails offline
  const needsFetch = !initialData.userSettings ||
                     Object.keys(initialData.userSettings).length === 0;

  const [data, setData] = useState<AddShiftData>(initialData);
  const [isLoading, setIsLoading] = useState(needsFetch);
  const [error, setError] = useState<string | null>(null);

  // If initial data is empty/missing (offline SSR failed), fetch from API
  useEffect(() => {
    if (needsFetch) {
      fetch('/api/shifts/add-data', {
        credentials: 'same-origin',
        headers: { 'Accept': 'application/json' }
      })
        .then(res => {
          if (!res.ok) {
            throw new Error(`HTTP ${res.status}: ${res.statusText}`);
          }
          return res.json();
        })
        .then(apiData => {
          setData(apiData);
          setError(null);
        })
        .catch(() => {
          // If offline and we have no data, show a better error
          setError(navigator.onLine ? 'Failed to load shift data' : 'Offline - data not cached yet');
        })
        .finally(() => {
          setIsLoading(false);
        });
    }
  }, [needsFetch]);

  if (isLoading) {
    return (
      <ScrollablePageWrapper routeKey="add-shift">
        <div className="flex items-center justify-center min-h-[50vh]">
          <div className="text-center">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-brand-primary"></div>
            <p className="mt-4 text-text-secondary">Loading...</p>
          </div>
        </div>
      </ScrollablePageWrapper>
    );
  }

  if (error) {
    return (
      <ScrollablePageWrapper routeKey="add-shift">
        <div className="flex items-center justify-center min-h-[50vh]">
          <div className="text-center">
            <p className="text-red-500">{error}</p>
            <button
              onClick={() => window.location.reload()}
              className="mt-4 px-4 py-2 bg-brand-primary text-white rounded-lg"
            >
              Retry
            </button>
          </div>
        </div>
      </ScrollablePageWrapper>
    );
  }

  return (
    <ScrollablePageWrapper routeKey="add-shift">
      <AddShiftForm
        existingShifts={data.existingShifts}
        userSettings={data.userSettings}
        presetRules={data.presetRules}
        wageSnapshots={data.wageSnapshots}
      />
    </ScrollablePageWrapper>
  );
}
