'use client';

import Link from 'next/link';
import type { MouseEvent } from 'react';
import { Button } from '@/components/app/Button';
import { useNavigationFeedback } from '@/components/app/navigation-feedback';

type SubscriptionCancelButtonsProps = {
  dict: {
    tryAgain: string;
    goToDashboard: string;
  };
  locale: string;
};

export function SubscriptionCancelButtons({ dict, locale }: SubscriptionCancelButtonsProps) {
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

  return (
    <div className="flex gap-4 w-full">
      <Button asChild className="flex-1">
        <Link href={`/${locale}/settings/subscription`} onClick={handleClick(`/${locale}/settings/subscription`)}>{dict.tryAgain}</Link>
      </Button>
      <Button asChild variant="outline" className="flex-1">
        <Link href={`/${locale}/home`} onClick={handleClick(`/${locale}/home`)}>{dict.goToDashboard}</Link>
      </Button>
    </div>
  );
}
