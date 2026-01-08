'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import type { MouseEvent } from 'react';
import { Button } from '@/components/app/Button';
import { useNavigationFeedback } from '@/components/app/navigation-feedback';

type SubscriptionSuccessButtonsProps = {
  dict: {
    goToDashboard: string;
    viewSubscription: string;
  };
  locale: string;
};

export function SubscriptionSuccessButtons({ dict, locale }: SubscriptionSuccessButtonsProps) {
  const router = useRouter();
  const { navigate } = useNavigationFeedback();

  const handleClick = (href: string) => (event: MouseEvent<HTMLAnchorElement>) => {
    if (
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey ||
      event.button !== 0
    ) {
      return;
    }

    event.preventDefault();
    navigate(href);
  };

  const handleViewSubscription = (event: MouseEvent<HTMLAnchorElement>) => {
    if (
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey ||
      event.button !== 0
    ) {
      return;
    }

    event.preventDefault();
    // Refresh to invalidate client-side cache, then navigate
    router.refresh();
    navigate(`/${locale}/settings/subscription`);
  };

  return (
    <div className="flex gap-4 w-full">
      <Button asChild className="flex-1">
        <Link href={`/${locale}/dashboard`} onClick={handleClick(`/${locale}/dashboard`)}>{dict.goToDashboard}</Link>
      </Button>
      <Button asChild variant="outline" className="flex-1">
        <Link href={`/${locale}/settings/subscription`} onClick={handleViewSubscription}>{dict.viewSubscription}</Link>
      </Button>
    </div>
  );
}
