'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { AlertCircle, RotateCcw, Loader2 } from 'lucide-react';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { restoreSubscription } from '@/app/[locale]/(app)/settings/subscription/_actions/restoreSubscription';

interface FreePlanInfoProps {
  t: Dictionary;
}

export function FreePlanInfo({ t }: FreePlanInfoProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  const handleRestore = () => {
    setFeedback(null);

    startTransition(async () => {
      const result = await restoreSubscription();

      if (result.success) {
        setFeedback({ type: 'success', message: t.pages.settings.subscription.freePlan.restore.success });
        router.refresh();
        return;
      }

      let message: string;
      switch (result.error) {
        case 'already_exists':
          router.refresh();
          return;
        case 'not_found':
        case 'no_valid_subscription':
          message = t.pages.settings.subscription.freePlan.restore.notFound;
          break;
        default:
          message = t.pages.settings.subscription.freePlan.restore.error;
      }
      setFeedback({ type: 'error', message });
    });
  };

  return (
    <Card className="p-6 border-border-subtle bg-surface-secondary/50">
      <div className="flex gap-3">
        <AlertCircle className="h-5 w-5 text-text-secondary shrink-0 mt-0.5" />
        <div className="flex-1">
          <h4 className="font-semibold text-sm mb-1">{t.pages.settings.subscription.freePlan.title}</h4>
          <p className="text-sm text-text-secondary">
            {t.pages.settings.subscription.freePlan.description}
          </p>

          {feedback && (
            <p
              className={`text-sm mt-3 ${
                feedback.type === 'success' ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'
              }`}
            >
              {feedback.message}
            </p>
          )}

          <Button
            variant="ghost"
            size="sm"
            onClick={handleRestore}
            disabled={isPending}
            className="mt-3 text-text-secondary hover:text-text-primary"
          >
            {isPending ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                {t.pages.settings.subscription.freePlan.restore.loading}
              </>
            ) : (
              <>
                <RotateCcw className="h-4 w-4 mr-2" />
                {t.pages.settings.subscription.freePlan.restore.button}
              </>
            )}
          </Button>
        </div>
      </div>
    </Card>
  );
}
