'use client';

import { useState, type FormEvent } from 'react';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { submitFeedback } from '@/app/[locale]/(app)/settings/feedback/_actions/submitFeedback';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { CheckCircle2 } from 'lucide-react';
import { cn } from '@/lib/cn';

const MAX_LENGTH = 2000;

interface FeedbackFormProps {
  t: Dictionary;
  onSuccess?: () => void;
}

export function FeedbackForm({ t, onSuccess }: FeedbackFormProps) {
  const [message, setMessage] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);

    const trimmed = message.trim();

    if (!trimmed) {
      setError(t.pages.settings.feedback.errors.empty);
      return;
    }

    if (trimmed.length > MAX_LENGTH) {
      setError(t.pages.settings.feedback.errors.tooLong);
      return;
    }

    setIsSubmitting(true);

    try {
      await submitFeedback(trimmed);
      setSuccess(true);
      setMessage('');
      onSuccess?.();
    } catch (err) {
      console.error('Failed to submit feedback:', err);
      setError(t.pages.settings.feedback.errors.failed);
    } finally {
      setIsSubmitting(false);
    }
  };

  const charCount = message.length;
  const isOverLimit = charCount > MAX_LENGTH;

  if (success) {
    return (
      <Card className="p-6">
        <div className="flex flex-col items-center justify-center py-8 text-center">
          <CheckCircle2 className="h-12 w-12 text-green-500 mb-4" />
          <p className="text-lg font-medium text-text-primary">
            {t.pages.settings.feedback.success}
          </p>
          <Button
            variant="outline"
            className="mt-6"
            onClick={() => setSuccess(false)}
          >
            {t.pages.settings.feedback.submit}
          </Button>
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="space-y-2">
          <textarea
            value={message}
            onChange={(e) => {
              setMessage(e.target.value);
              setError(null);
            }}
            placeholder={t.pages.settings.feedback.placeholder}
            disabled={isSubmitting}
            maxLength={MAX_LENGTH + 100}
            rows={8}
            className={cn(
              "flex w-full min-w-0 max-w-full rounded-md border border-input bg-transparent px-3 py-2 text-base shadow-xs transition-colors resize-none",
              "placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
              "focus:border-ring focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50 md:text-sm"
            )}
          />
          <div className="flex justify-between items-center">
            <div>
              {error && (
                <p className="text-sm text-red-500">{error}</p>
              )}
            </div>
            <p className={`text-sm ${isOverLimit ? 'text-red-500' : 'text-text-muted'}`}>
              {t.pages.settings.feedback.charCount.replace('{count}', String(charCount))}
            </p>
          </div>
        </div>

        <Button
          type="submit"
          disabled={isSubmitting || isOverLimit || !message.trim()}
          className="w-full sm:w-auto"
        >
          {isSubmitting
            ? t.pages.settings.feedback.sending
            : t.pages.settings.feedback.submit}
        </Button>
      </form>
    </Card>
  );
}
