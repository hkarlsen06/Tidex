'use client';

import { useState } from 'react';
import { FeedbackForm } from './FeedbackForm';
import { FeedbackHistory } from './FeedbackHistory';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface FeedbackPageProps {
  t: Dictionary;
}

export function FeedbackPage({ t }: FeedbackPageProps) {
  const [refreshTrigger, setRefreshTrigger] = useState(0);

  const handleFeedbackSubmitted = () => {
    setRefreshTrigger((n) => n + 1);
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">
          {t.pages.settings.feedback?.title || 'Feedback'}
        </h2>
        <p className="text-text-secondary mt-1">
          {t.pages.settings.feedback?.subtitle || 'Help us improve by sharing your thoughts'}
        </p>
      </div>

      <FeedbackForm t={t} onSuccess={handleFeedbackSubmitted} />

      <FeedbackHistory t={t} refreshTrigger={refreshTrigger} />
    </div>
  );
}
