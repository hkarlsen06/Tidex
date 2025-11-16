'use client';

import Link from 'next/link';
import type { MouseEvent } from 'react';
import { Button } from '@/components/app/Button';
import { useNavigationFeedback } from '@/components/app/navigation-feedback';

export function SubscriptionCancelButtons() {
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
        <Link href="/settings/subscription" onClick={handleClick('/settings/subscription')}>Prøv igjen</Link>
      </Button>
      <Button asChild variant="outline" className="flex-1">
        <Link href="/home" onClick={handleClick('/home')}>Gå til Dashboard</Link>
      </Button>
    </div>
  );
}
