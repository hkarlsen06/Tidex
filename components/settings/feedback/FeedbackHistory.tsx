'use client';

import { useState, useEffect } from 'react';
import { Card } from '@/components/app/Card';
import { getUserFeedback, type UserFeedbackItem } from '@/app/[locale]/(app)/settings/feedback/_actions/getUserFeedback';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { ChevronDown, ChevronUp, MessageCircle, CheckCircle2, Clock } from 'lucide-react';

interface FeedbackHistoryProps {
  t: Dictionary;
  refreshTrigger?: number;
}

export function FeedbackHistory({ t, refreshTrigger }: FeedbackHistoryProps) {
  const [feedbackItems, setFeedbackItems] = useState<UserFeedbackItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  useEffect(() => {
    const fetchHistory = async () => {
      setLoading(true);
      try {
        const items = await getUserFeedback();
        setFeedbackItems(items);
      } catch (error) {
        console.error('Failed to fetch feedback history:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchHistory();
  }, [refreshTrigger]);

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  };

  const truncateMessage = (message: string, maxLength = 100) => {
    if (message.length <= maxLength) return message;
    return message.slice(0, maxLength) + '...';
  };

  if (loading) {
    return (
      <Card className="p-6">
        <h3 className="text-lg font-semibold mb-4">{t.pages.settings.feedback.history?.title || 'Your Feedback'}</h3>
        <div className="text-center py-6 text-text-muted">Loading...</div>
      </Card>
    );
  }

  if (feedbackItems.length === 0) {
    return null; // Don't show history section if empty
  }

  return (
    <Card className="p-6">
      <h3 className="text-lg font-semibold mb-4">{t.pages.settings.feedback.history?.title || 'Your Feedback'}</h3>

      <div className="space-y-3">
        {feedbackItems.map((item) => (
          <div
            key={item.id}
            className="border border-border rounded-lg overflow-hidden"
          >
            <button
              type="button"
              className="flex items-center justify-between p-3 cursor-pointer hover:bg-surface-secondary/50 w-full text-left"
              onClick={() => setExpandedId(expandedId === item.id ? null : item.id)}
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs text-text-muted">
                    {t.pages.settings.feedback.history?.submittedOn || 'Submitted'} {formatDate(item.created_at)}
                  </span>
                  {item.response ? (
                    <span className="inline-flex items-center gap-1 text-xs text-green-600">
                      <CheckCircle2 className="h-3 w-3" />
                      {t.pages.settings.feedback.history?.respondedOn || 'Responded'}
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1 text-xs text-text-muted">
                      <Clock className="h-3 w-3" />
                      {t.pages.settings.feedback.history?.noResponse || 'Awaiting response'}
                    </span>
                  )}
                </div>
                <p className="text-sm text-text-primary truncate">
                  {truncateMessage(item.message)}
                </p>
              </div>
              <div className="ml-2 shrink-0">
                {expandedId === item.id ? (
                  <ChevronUp className="h-4 w-4 text-text-muted" />
                ) : (
                  <ChevronDown className="h-4 w-4 text-text-muted" />
                )}
              </div>
            </button>

            {expandedId === item.id && (
              <div className="px-3 pb-3 pt-0 space-y-3">
                {/* User's message */}
                <div className="bg-surface-secondary rounded p-3">
                  <p className="text-sm whitespace-pre-wrap">{item.message}</p>
                </div>

                {/* Response from Tidex */}
                {item.response && (
                  <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded p-3">
                    <div className="flex items-center gap-2 mb-2">
                      <MessageCircle className="h-4 w-4 text-green-600" />
                      <span className="text-sm font-medium text-green-700 dark:text-green-400">
                        {t.pages.settings.feedback.history?.response || 'Response from Tidex'}
                      </span>
                      {item.responded_at && (
                        <span className="text-xs text-green-600 dark:text-green-500">
                          ({formatDate(item.responded_at)})
                        </span>
                      )}
                    </div>
                    <p className="text-sm whitespace-pre-wrap text-green-800 dark:text-green-200">
                      {item.response}
                    </p>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
      </div>
    </Card>
  );
}
