'use client';

import { useState, useEffect, use } from 'react';
import Image from 'next/image';
import { motion } from 'motion/react';
import { supabase } from '@/lib/supabase/browser';
import { useTranslations } from '@/lib/i18n/client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { LegalModal } from '@/components/legal/LegalModal';
import { LocaleSwitcher } from '@/components/app/LocaleSwitcher';

// Animation variants for entrance animation
const cardVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
};

type AcceptTermsSearchParams = {
  next?: string | string[];
};

function pickFirst(value?: string | string[]) {
  if (Array.isArray(value)) {
    return value[0];
  }
  return value;
}

export default function AcceptTermsPage({
  params,
  searchParams,
}: {
  params: Promise<{ locale: string }>;
  searchParams: Promise<AcceptTermsSearchParams>;
}) {
  const { locale } = use(params);
  const resolvedSearchParams = use(searchParams);
  const nextPathFromUrl = pickFirst(resolvedSearchParams?.next);

  const { t } = useTranslations();
  const [legalModalOpen, setLegalModalOpen] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [nextPath, setNextPath] = useState(nextPathFromUrl || '/onboarding');

  // Determine the correct next path based on user's onboarding status
  useEffect(() => {
    async function determineNextPath() {
      // If URL already specifies a path (not default), use it
      if (nextPathFromUrl && nextPathFromUrl !== '/onboarding') {
        return;
      }

      // Check user's onboarding status to determine correct default
      const { data: { user } } = await supabase.auth.getUser();
      const onboardingCompleted = user?.user_metadata?.finishedOnboarding;

      if (onboardingCompleted) {
        // Existing user who has completed onboarding - go to dashboard
        setNextPath('/');
      }
      // Otherwise keep the default /onboarding for new users
    }

    determineNextPath();
  }, [nextPathFromUrl]);

  const handleAccept = async () => {
    setIsProcessing(true);
    setError(null);

    try {
      // Update user metadata with terms acceptance timestamp
      const { error: updateError } = await supabase.auth.updateUser({
        data: {
          terms_accepted_at: new Date().toISOString(),
        },
      });

      if (updateError) {
        console.error('Failed to update user metadata:', updateError);
        setError(t.pages.auth.acceptTerms.errors.updateFailed);
        setIsProcessing(false);
        return;
      }

      // Refresh session to get new JWT with updated terms_accepted_at claim
      // This is necessary because the app layout checks JWT claims, not user metadata
      await supabase.auth.refreshSession();

      // Redirect to the next destination (usually onboarding)
      // Use window.location.href to force full page reload with fresh JWT
      window.location.href = `/${locale}${nextPath.startsWith('/') ? nextPath : `/${nextPath}`}`;
    } catch (err) {
      console.error('Error accepting terms:', err);
      setError(t.pages.auth.acceptTerms.errors.genericError);
      setIsProcessing(false);
    }
  };

  const handleDecline = async () => {
    setIsProcessing(true);

    // Redirect to logout route which properly clears cookies, hides native tab bar, etc.
    window.location.href = `/${locale}/logout`;
  };

  return (
    <motion.div
      className="relative w-full"
      variants={cardVariants}
      initial="hidden"
      animate="visible"
    >
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader>
          <div className="flex items-center justify-between mb-1">
            <CardTitle className="text-2xl font-bold">{t.pages.auth.acceptTerms.title}</CardTitle>
            <Image
              src="/icons/short-logo-gradient.svg"
              alt="Tidex"
              width={32}
              height={32}
              priority
            />
          </div>
          <CardDescription>{t.pages.auth.acceptTerms.description}</CardDescription>
        </CardHeader>

        <CardContent className="space-y-6">
          <p className="text-sm text-text-secondary">
            {t.pages.auth.acceptTerms.explanation}
          </p>

          {error && (
            <div
              className="rounded-lg px-4 py-3 text-sm font-medium bg-error-subtle text-error-foreground"
              role="alert"
            >
              {error}
            </div>
          )}

          <div className="flex flex-col gap-3">
            <Button
              type="button"
              size="lg"
              onClick={() => setLegalModalOpen(true)}
              disabled={isProcessing}
              className="w-full"
            >
              {t.pages.auth.acceptTerms.reviewTermsButton}
            </Button>

            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={handleDecline}
              disabled={isProcessing}
              loading={isProcessing}
              className="w-full text-text-muted"
            >
              {t.pages.auth.acceptTerms.declineButton}
            </Button>
          </div>
        </CardContent>
      </Card>

      <div className="mt-6 flex justify-center">
        <LocaleSwitcher />
      </div>

      <LegalModal
        open={legalModalOpen}
        onOpenChange={setLegalModalOpen}
        showActions={true}
        onAccept={handleAccept}
        onDecline={handleDecline}
      />
    </motion.div>
  );
}
