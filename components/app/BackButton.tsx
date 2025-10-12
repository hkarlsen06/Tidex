'use client';

import { useRouter } from 'next/navigation';
import { ChevronLeft } from 'lucide-react';
import { Button } from '@appui/Button';
import { useNavigationFeedback } from './navigation-feedback';

interface BackButtonProps {
  label?: string;
  fallbackHref?: string;
}

export function BackButton({ label = 'Tilbake', fallbackHref }: BackButtonProps) {
  const router = useRouter();
  const { navigate } = useNavigationFeedback();

  const handleBack = () => {
    if (fallbackHref) {
      navigate(fallbackHref);
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
