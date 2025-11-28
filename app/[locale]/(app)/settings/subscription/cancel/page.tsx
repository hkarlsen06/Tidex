import { redirect } from 'next/navigation';
import type { Metadata } from 'next';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { Card } from '@/components/app/Card';
import { XCircle } from 'lucide-react';
import { SubscriptionCancelButtons } from './SubscriptionCancelButtons';
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
    title: dict.pages.settings.subscription.cancel.metadataTitle,
  };
}

export default async function SubscriptionCancelPage({ params }: Props) {
  const { locale } = await params;
  const dict = await getAppDictionary(locale, ['pages.settings.subscription']);
  const t = dict.pages.settings.subscription.cancel;

  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect('/login');
  }

  return (
    <SettingsPageWrapper routeKey="settings-subscription-cancel">
      <Card className="p-8">
        <div className="flex flex-col items-center text-center space-y-6">
          <div className="w-16 h-16 bg-surface-secondary rounded-full flex items-center justify-center">
            <XCircle className="w-10 h-10 text-text-secondary" />
          </div>

          <div className="space-y-2">
            <h1 className="text-3xl font-bold">{t.heading}</h1>
            <p className="text-text-secondary">
              {t.description}
            </p>
          </div>

          <div className="w-full p-4 bg-surface-secondary rounded-lg text-left">
            <h3 className="font-semibold mb-2">{t.needHelpTitle}</h3>
            <p className="text-sm text-text-secondary">
              {t.needHelpDescription}
            </p>
          </div>

          <SubscriptionCancelButtons dict={t} locale={locale} />
        </div>
      </Card>
    </SettingsPageWrapper>
  );
}
