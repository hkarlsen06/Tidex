'use client';

import { useRouter } from 'next/navigation';
import { ChevronLeft } from 'lucide-react';
import { Button } from '@appui/Button';

interface BackButtonProps {
  label?: string;
  fallbackHref?: string;
}

export function BackButton({ label = 'Tilbake', fallbackHref }: BackButtonProps) {
  const router = useRouter();

  const handleBack = () => {
    if (fallbackHref) {
      router.push(fallbackHref);
    } else {
      router.back();
    }
  };

  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={handleBack}
      className="mb-4 -ml-2"
    >
      <ChevronLeft className="h-4 w-4 mr-1" />
      {label}
    </Button>
  );
}
