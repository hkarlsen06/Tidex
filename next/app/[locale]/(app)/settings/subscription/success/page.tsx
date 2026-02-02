import { redirect } from 'next/navigation';
import type { Metadata } from 'next';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { Card } from '@/components/app/Card';
import { CheckCircle } from 'lucide-react';
import { SubscriptionSuccessButtons } from './SubscriptionSuccessButtons';
import { getAppDictionary } from '@/lib/i18n/dictionaries';
import type { Locale } from '@/lib/i18n/config';
import { SettingsPageWrapper } from '@/components/app/SettingsPageWrapper';

type Props = {
  params: Promise<{ locale: Locale }>;
};

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  const dict = await getAppDictionary(locale, ['pages.settings.subscription']);

  return {
    title: dict.pages.settings.subscription.success.metadataTitle,
  };
}

export default async function SubscriptionSuccessPage({ params }: Props) {
  const { locale } = await params;
  const dict = await getAppDictionary(locale, ['pages.settings.subscription']);
  const t = dict.pages.settings.subscription.success;

  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();

  // Use getClaims() for performance - parses JWT locally without network request
  const { data, error } = await supabase.auth.getClaims();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (error || !data?.claims) {
    redirect(`/${locale}/login`);
  }

  return (
    <SettingsPageWrapper routeKey="settings-subscription-success">
      <Card className="p-8">
        <div className="flex flex-col items-center text-center space-y-6">
          <div className="w-16 h-16 bg-green-100 dark:bg-green-900/30 rounded-full flex items-center justify-center">
            <CheckCircle className="w-10 h-10 text-green-600 dark:text-green-500" />
          </div>

          <div className="space-y-2">
            <h1 className="text-3xl font-bold">{t.heading}</h1>
            <p className="text-text-secondary">
              {t.description}
            </p>
          </div>

          <div className="w-full p-4 bg-surface-secondary rounded-lg text-left">
            <h3 className="font-semibold mb-2">{t.whatHappensTitle}</h3>
            <ul className="space-y-2 text-sm text-text-secondary">
              <li>✓ {t.item1}</li>
              <li>✓ {t.item2}</li>
              <li>✓ {t.item3}</li>
            </ul>
          </div>

          <SubscriptionSuccessButtons dict={t} locale={locale} />
        </div>
      </Card>
    </SettingsPageWrapper>
  );
}
